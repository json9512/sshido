package main

import (
	"bufio"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"net"
	"os"
	"strings"
	"text/tabwriter"
)

func runAttach() int {
	conn, err := net.Dial("unix", appSocket(env("SSHIDO_DATA_DIR", "/data")))
	if err != nil {
		fmt.Fprintf(os.Stderr, "attach: daemon not reachable: %v\n", err)
		return 1
	}
	defer conn.Close()
	unix := conn.(*net.UnixConn)
	go func() {
		if _, err := io.Copy(unix, os.Stdin); err != nil {
			fmt.Fprintf(os.Stderr, "attach: stdin: %v\n", err)
		}
		unix.CloseWrite()
	}()
	if _, err := io.Copy(os.Stdout, unix); err != nil {
		fmt.Fprintf(os.Stderr, "attach: stdout: %v\n", err)
		return 1
	}
	return 0
}

const ctlUsage = `usage:
  agentctl spawn --name <name> --task "<task>" [--harness claude|codex|gemini|grok|local] [--model <model>]
  agentctl send --to <agent-id> "<message>"
  agentctl list
  agentctl report --progress "<text>" | --needs-input "<question>"`

func runCtl(args []string) int {
	if len(args) == 0 {
		fmt.Fprintln(os.Stderr, ctlUsage)
		return 2
	}
	req, err := parseCtl(args)
	if err != nil {
		fmt.Fprintf(os.Stderr, "agentctl: %v\n%s\n", err, ctlUsage)
		return 2
	}
	resp, err := callBus(env("SSHIDO_BUS", "/bus/bus.sock"), BusRequest{
		Token: os.Getenv("SSHIDO_AGENT_TOKEN"), Op: req.Op, Name: req.Name, Harness: req.Harness,
		Model: req.Model, Task: req.Task, Kind: req.Kind, Text: req.Text, To: req.To,
	})
	if err != nil {
		fmt.Fprintf(os.Stderr, "agentctl: %v\n", err)
		return 1
	}
	if !resp.OK {
		fmt.Fprintf(os.Stderr, "agentctl: %s\n", resp.Error)
		return 1
	}
	printCtl(req.Op, resp)
	return 0
}

func parseCtl(args []string) (BusRequest, error) {
	op, rest := args[0], args[1:]
	fs := flag.NewFlagSet(op, flag.ContinueOnError)
	fs.SetOutput(io.Discard)
	name := fs.String("name", "", "")
	task := fs.String("task", "", "")
	harness := fs.String("harness", "", "")
	model := fs.String("model", "", "")
	to := fs.String("to", "", "")
	progress := fs.String("progress", "", "")
	needsInput := fs.String("needs-input", "", "")
	if err := fs.Parse(rest); err != nil {
		return BusRequest{}, err
	}
	text := strings.Join(fs.Args(), " ")
	switch op {
	case BusSpawn:
		return BusRequest{Op: op, Name: *name, Task: *task, Harness: *harness, Model: *model}, nil
	case BusSend:
		return BusRequest{Op: op, To: *to, Text: text}, nil
	case BusList:
		return BusRequest{Op: op}, nil
	case BusReport:
		return parseReport(*progress, *needsInput)
	}
	return BusRequest{}, fmt.Errorf("unknown command %q", op)
}

func parseReport(progress, needsInput string) (BusRequest, error) {
	if (progress == "") == (needsInput == "") {
		return BusRequest{}, errors.New("report needs exactly one of --progress or --needs-input")
	}
	if progress != "" {
		return BusRequest{Op: BusReport, Kind: KindProgress, Text: progress}, nil
	}
	return BusRequest{Op: BusReport, Kind: KindNeedsInput, Text: needsInput}, nil
}

func callBus(path string, req BusRequest) (BusResponse, error) {
	conn, err := net.Dial("unix", path)
	if err != nil {
		return BusResponse{}, fmt.Errorf("daemon not reachable at %s: %w", path, err)
	}
	defer conn.Close()
	if err := json.NewEncoder(conn).Encode(req); err != nil {
		return BusResponse{}, fmt.Errorf("send request: %w", err)
	}
	line, err := bufio.NewReader(conn).ReadBytes('\n')
	if err != nil && len(line) == 0 {
		return BusResponse{}, fmt.Errorf("read response: %w", err)
	}
	var resp BusResponse
	if err := json.Unmarshal(line, &resp); err != nil {
		return BusResponse{}, fmt.Errorf("bad response: %w", err)
	}
	return resp, nil
}

func printCtl(op string, resp BusResponse) {
	switch op {
	case BusSpawn:
		fmt.Println(resp.AgentID)
	case BusList:
		w := tabwriter.NewWriter(os.Stdout, 0, 0, 2, ' ', 0)
		fmt.Fprintln(w, "ID\tNAME\tROLE\tHARNESS\tSTATUS")
		for _, a := range resp.Agents {
			fmt.Fprintf(w, "%s\t%s\t%s\t%s\t%s\n", a.ID, a.Name, a.Role, a.Harness, a.Status)
		}
		w.Flush()
	}
}
