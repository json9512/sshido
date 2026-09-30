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
  agentctl goal "<the outcome, and how you will know it is met>"
  agentctl log "<what you did or decided>"
  agentctl verify "<what you checked and what you saw>"
  agentctl status in_progress|blocked|done ["<note>"]
  agentctl record [--to <agent-id>]
  agentctl report --progress "<text>" | --needs-input "<question>"
  agentctl attach <path> [--caption "<text>"]
orchestrator only:
  agentctl spawn --name <name> --goal "<what done looks like>" --task "<task>" [--harness <harness>] [--model <model>]
  agentctl send --to <agent-id> "<message>"
  agentctl verdict --to <agent-id>|self --pass|--fail "<why>"
  agentctl stop --to <agent-id>
  agentctl list`

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
		Model: req.Model, Task: req.Task, Goal: req.Goal, Kind: req.Kind, Text: req.Text, To: req.To, Path: req.Path,
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
	goal := fs.String("goal", "", "")
	task := fs.String("task", "", "")
	pass := fs.Bool("pass", false, "")
	fail := fs.Bool("fail", false, "")
	harness := fs.String("harness", "", "")
	model := fs.String("model", "", "")
	to := fs.String("to", "", "")
	progress := fs.String("progress", "", "")
	needsInput := fs.String("needs-input", "", "")
	caption := fs.String("caption", "", "")
	positional, err := parseInterleaved(fs, rest)
	if err != nil {
		return BusRequest{}, err
	}
	text := strings.Join(positional, " ")
	switch op {
	case BusSpawn:
		return BusRequest{Op: op, Name: *name, Goal: *goal, Task: *task, Harness: *harness, Model: *model}, nil
	case BusSend:
		return BusRequest{Op: op, To: *to, Text: text}, nil
	case BusStop, BusRecord:
		return BusRequest{Op: op, To: *to}, nil
	case BusList:
		return BusRequest{Op: op}, nil
	case BusGoal, BusVerify, BusLog:
		return BusRequest{Op: op, Text: text}, nil
	case BusStatus:
		return parseStatus(positional)
	case BusVerdict:
		return parseVerdict(*to, *pass, *fail, text)
	case BusReport:
		return parseReport(*progress, *needsInput)
	case BusAttach:
		if len(positional) != 1 {
			return BusRequest{}, errors.New("attach needs exactly one file path")
		}
		return BusRequest{Op: op, Path: positional[0], Text: *caption}, nil
	}
	return BusRequest{}, fmt.Errorf("unknown command %q", op)
}

func parseInterleaved(fs *flag.FlagSet, args []string) ([]string, error) {
	positional := []string{}
	remaining := args
	for {
		if err := fs.Parse(remaining); err != nil {
			return nil, err
		}
		rest := fs.Args()
		if len(rest) == 0 {
			return positional, nil
		}
		positional = append(positional, rest[0])
		remaining = rest[1:]
	}
}

func parseStatus(positional []string) (BusRequest, error) {
	if len(positional) == 0 {
		return BusRequest{}, errors.New("status needs in_progress, blocked or done")
	}
	return BusRequest{Op: BusStatus, Kind: positional[0], Text: strings.Join(positional[1:], " ")}, nil
}

func parseVerdict(to string, pass, fail bool, reason string) (BusRequest, error) {
	if pass == fail {
		return BusRequest{}, errors.New("verdict needs exactly one of --pass or --fail")
	}
	if pass {
		return BusRequest{Op: BusVerdict, To: to, Kind: VerdictPass, Text: reason}, nil
	}
	return BusRequest{Op: BusVerdict, To: to, Kind: VerdictFail, Text: reason}, nil
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
		fmt.Fprintln(w, "ID\tNAME\tROLE\tHARNESS\tSTATUS\tWORK\tVERDICT")
		for _, a := range resp.Agents {
			fmt.Fprintf(w, "%s\t%s\t%s\t%s\t%s\t%s\t%s\n", a.ID, a.Name, a.Role, a.Harness, a.Status,
				firstNonEmpty(a.WorkStatus, "-"), firstNonEmpty(a.Verdict, "-"))
		}
		w.Flush()
	case BusRecord:
		fmt.Println(resp.Text)
	}
}
