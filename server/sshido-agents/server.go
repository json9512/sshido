package main

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net"
	"os"
	"strings"
)

const maxLine = 4 * 1024 * 1024

func listenUnix(path string, mode os.FileMode) (net.Listener, error) {
	if err := os.Remove(path); err != nil && !errors.Is(err, os.ErrNotExist) {
		return nil, fmt.Errorf("remove stale socket %s: %w", path, err)
	}
	ln, err := net.Listen("unix", path)
	if err != nil {
		return nil, fmt.Errorf("listen %s: %w", path, err)
	}
	if err := os.Chmod(path, mode); err != nil {
		ln.Close()
		return nil, fmt.Errorf("chmod %s: %w", path, err)
	}
	return ln, nil
}

func serve(ctx context.Context, ln net.Listener, handle func(context.Context, net.Conn)) {
	go func() {
		<-ctx.Done()
		ln.Close()
	}()
	for {
		conn, err := ln.Accept()
		if err != nil {
			if ctx.Err() == nil {
				log.Printf("accept on %s: %v", ln.Addr(), err)
			}
			return
		}
		go handle(ctx, conn)
	}
}

func (d *Daemon) ServeBus(ctx context.Context, conn net.Conn) {
	defer conn.Close()
	reader := bufio.NewReaderSize(conn, 64*1024)
	line, err := reader.ReadBytes('\n')
	if err != nil && len(line) == 0 {
		log.Printf("bus: empty request: %v", err)
		return
	}
	resp := d.handleBus(ctx, line)
	if err := json.NewEncoder(conn).Encode(resp); err != nil {
		log.Printf("bus: write response: %v", err)
	}
}

func busDeny(format string, args ...any) BusResponse {
	msg := fmt.Sprintf(format, args...)
	log.Printf("bus: denied: %s", msg)
	return BusResponse{Error: msg}
}

func (d *Daemon) handleBus(ctx context.Context, line []byte) BusResponse {
	var req BusRequest
	if err := json.Unmarshal(line, &req); err != nil {
		return busDeny("malformed request: %v", err)
	}
	if req.Token == "" {
		return busDeny("missing token (op %q)", req.Op)
	}
	caller, err := d.store.AgentByToken(req.Token)
	if err != nil {
		return busDeny("unknown token (op %q): %v", req.Op, err)
	}
	switch req.Op {
	case BusReport:
		return d.busReport(ctx, caller, req)
	case BusList:
		return d.busList(caller)
	case BusSpawn:
		return d.busSpawn(ctx, caller, req)
	case BusSend:
		return d.busSend(caller, req)
	case BusStop:
		return d.busStop(ctx, caller, req)
	case BusAttach:
		return d.busAttach(caller, req)
	case BusGoal:
		return d.busGoal(caller, req)
	case BusStatus:
		return d.busStatus(caller, req)
	case BusVerify:
		return d.busVerify(caller, req)
	case BusLog:
		return d.busLog(caller, req)
	case BusVerdict:
		return d.busVerdict(caller, req)
	case BusRecord:
		return d.busRecord(caller, req)
	}
	return busDeny("agent %s: unknown op %q", caller.ID, req.Op)
}

func (d *Daemon) busReport(ctx context.Context, caller Agent, req BusRequest) BusResponse {
	if strings.TrimSpace(req.Text) == "" {
		return busDeny("agent %s: report without text", caller.ID)
	}
	switch req.Kind {
	case KindProgress:
		d.post(caller.ChatID, caller.ID, caller.Name, KindProgress, req.Text)
		return BusResponse{OK: true}
	case KindNeedsInput:
		d.post(caller.ChatID, caller.ID, caller.Name, KindNeedsInput, req.Text)
		d.logEntry(caller, "Asked the person: "+req.Text)
		d.notify(ctx, caller.Name+" needs input", req.Text, true)
		return BusResponse{OK: true}
	}
	return busDeny("agent %s: report kind %q is not progress or needs_input", caller.ID, req.Kind)
}

func (d *Daemon) busList(caller Agent) BusResponse {
	agents, err := d.store.ChatAgents(caller.ChatID)
	if err != nil {
		log.Printf("bus: list for %s failed: %v", caller.ID, err)
		return BusResponse{Error: err.Error()}
	}
	return BusResponse{OK: true, Agents: agents}
}

const maxLiveWorkers = 12

func liveWorkers(agents []Agent) int {
	n := 0
	for _, a := range agents {
		if a.Role == RoleWorker && a.Status != StatusStopped {
			n++
		}
	}
	return n
}

func (d *Daemon) busSpawn(ctx context.Context, caller Agent, req BusRequest) BusResponse {
	if caller.Role != RoleOrchestrator {
		return busDeny("agent %s (%s) may not spawn agents; ask the orchestrator in your report", caller.ID, caller.Role)
	}
	name, goal, task := strings.TrimSpace(req.Name), strings.TrimSpace(req.Goal), strings.TrimSpace(req.Task)
	if name == "" || goal == "" || task == "" {
		return busDeny("agent %s: spawn needs --name, --goal and --task", caller.ID)
	}
	agents, err := d.store.ChatAgents(caller.ChatID)
	if err != nil {
		log.Printf("bus: spawn for %s: %v", caller.ID, err)
		return BusResponse{Error: err.Error()}
	}
	if liveWorkers(agents) >= maxLiveWorkers {
		return busDeny("agent %s: %d subagents are already running; stop one you no longer need with agentctl stop --to <id>", caller.ID, maxLiveWorkers)
	}
	harness, model, err := d.cfg.Workers.pick(req.Harness, req.Model)
	if err != nil {
		return busDeny("agent %s: spawn %q: %v", caller.ID, name, err)
	}
	worker, err := d.createAgent(ctx, Agent{
		ChatID: caller.ChatID, Name: name, Role: RoleWorker, Harness: harness, Model: model,
		Task: task, Goal: truncate(goal, maxRecordField), WorkStatus: WorkInProgress,
	})
	if err != nil {
		log.Printf("bus: spawn %q for %s failed: %v", name, caller.ID, err)
		return BusResponse{Error: err.Error()}
	}
	d.logEntry(worker, "Spawned by the orchestrator.\n\nGoal: "+goal+"\n\nTask:\n"+task)
	d.logEntry(caller, fmt.Sprintf("Spawned %s (%s, %s) for: %s", name, worker.ID, harness, goal))
	d.post(caller.ChatID, worker.ID, "orchestrator", KindProgress, fmt.Sprintf("Started %s (%s) for: %s", name, harness, truncate(goal, 200)))
	d.enqueue(worker, "Task:\n"+task)
	return BusResponse{OK: true, AgentID: worker.ID}
}

func (d *Daemon) busAttach(caller Agent, req BusRequest) BusResponse {
	att, err := resolveAttachment(d.cfg.WorkspaceDir, req.Path)
	if err != nil {
		return busDeny("agent %s: attach %q: %v", caller.ID, req.Path, err)
	}
	m, err := d.store.AddAttachment(caller.ChatID, caller.ID, caller.Name, strings.TrimSpace(req.Text), att)
	if err != nil {
		log.Printf("bus: attach for %s failed: %v", caller.ID, err)
		return BusResponse{Error: err.Error()}
	}
	d.hub.Publish(AppEvent{Type: EventMessage, Message: &m})
	return BusResponse{OK: true}
}

func (d *Daemon) target(caller Agent, to, op string) (Agent, error) {
	id := strings.TrimSpace(to)
	if id == "" || id == "self" || id == caller.ID {
		return caller, nil
	}
	target, err := d.store.Agent(id)
	if err != nil {
		return Agent{}, fmt.Errorf("%s from %s to unknown agent %q", op, caller.ID, id)
	}
	if target.ChatID != caller.ChatID {
		return Agent{}, fmt.Errorf("%s from %s to agent %s in another chat", op, caller.ID, id)
	}
	return target, nil
}

func (d *Daemon) busSend(caller Agent, req BusRequest) BusResponse {
	if caller.Role != RoleOrchestrator {
		return busDeny("agent %s (%s) may not message other agents", caller.ID, caller.Role)
	}
	target, err := d.target(caller, req.To, "send")
	if err != nil {
		return busDeny("%v", err)
	}
	if target.ID == caller.ID {
		return busDeny("send from %s to itself", caller.ID)
	}
	if target.Status == StatusStopped {
		return busDeny("send from %s to stopped agent %s; spawn a new one", caller.ID, target.ID)
	}
	if strings.TrimSpace(req.Text) == "" {
		return busDeny("send from %s to %s without text", caller.ID, target.ID)
	}
	updated, err := d.saveRecord(target, newWork(target), "Message from the orchestrator:\n\n"+req.Text)
	if err != nil {
		log.Printf("bus: send record for %s: %v", target.ID, err)
		return BusResponse{Error: err.Error()}
	}
	d.enqueue(updated, "Message from the orchestrator:\n\n"+req.Text)
	return BusResponse{OK: true, AgentID: target.ID}
}

func (d *Daemon) busStop(ctx context.Context, caller Agent, req BusRequest) BusResponse {
	if caller.Role != RoleOrchestrator {
		return busDeny("agent %s (%s) may not stop agents", caller.ID, caller.Role)
	}
	target, err := d.target(caller, req.To, "stop")
	if err != nil {
		return busDeny("%v", err)
	}
	if target.Role != RoleWorker {
		return busDeny("stop from %s: %s is not a subagent", caller.ID, target.ID)
	}
	if err := d.StopAgent(ctx, target.ID); err != nil {
		log.Printf("bus: stop %s for %s: %v", target.ID, caller.ID, err)
		return BusResponse{Error: err.Error()}
	}
	d.logEntry(caller, fmt.Sprintf("Stopped %s (%s).", target.Name, target.ID))
	return BusResponse{OK: true, AgentID: target.ID}
}

func requireText(caller Agent, op, text string) (string, *BusResponse) {
	trimmed := strings.TrimSpace(text)
	if trimmed == "" {
		deny := busDeny("agent %s: %s without text", caller.ID, op)
		return "", &deny
	}
	return truncate(trimmed, maxRecordField), nil
}

func (d *Daemon) saved(caller Agent, r Record, entry string) BusResponse {
	if _, err := d.saveRecord(caller, r, entry); err != nil {
		log.Printf("bus: record for %s failed: %v", caller.ID, err)
		return BusResponse{Error: err.Error()}
	}
	return BusResponse{OK: true}
}

func (d *Daemon) busGoal(caller Agent, req BusRequest) BusResponse {
	text, deny := requireText(caller, "goal", req.Text)
	if deny != nil {
		return *deny
	}
	r := recordOf(caller)
	return d.saved(caller, Record{Goal: text, WorkStatus: r.WorkStatus, Verification: r.Verification, Verdict: r.Verdict, VerdictNote: r.VerdictNote},
		"Goal: "+text)
}

func (d *Daemon) busVerify(caller Agent, req BusRequest) BusResponse {
	text, deny := requireText(caller, "verify", req.Text)
	if deny != nil {
		return *deny
	}
	r := recordOf(caller)
	return d.saved(caller, Record{Goal: r.Goal, WorkStatus: r.WorkStatus, Verification: text, Verdict: r.Verdict, VerdictNote: r.VerdictNote},
		"Verification:\n\n"+text)
}

func (d *Daemon) busLog(caller Agent, req BusRequest) BusResponse {
	text, deny := requireText(caller, "log", req.Text)
	if deny != nil {
		return *deny
	}
	d.logEntry(caller, text)
	return BusResponse{OK: true}
}

func (d *Daemon) busStatus(caller Agent, req BusRequest) BusResponse {
	status := strings.TrimSpace(req.Kind)
	if status != WorkInProgress && status != WorkBlocked && status != WorkDone {
		return busDeny("agent %s: status %q is not %s, %s or %s", caller.ID, status, WorkInProgress, WorkBlocked, WorkDone)
	}
	if status == WorkDone && strings.TrimSpace(caller.Verification) == "" {
		return busDeny("agent %s: status done needs a verification first; run agentctl verify \"<what you checked and what you saw>\"", caller.ID)
	}
	entry := "Status: " + status
	if note := strings.TrimSpace(req.Text); note != "" {
		entry = entry + " - " + truncate(note, maxRecordField)
	}
	r := recordOf(caller)
	return d.saved(caller, Record{Goal: r.Goal, WorkStatus: status, Verification: r.Verification, Verdict: r.Verdict, VerdictNote: r.VerdictNote},
		entry)
}

func (d *Daemon) busVerdict(caller Agent, req BusRequest) BusResponse {
	if caller.Role != RoleOrchestrator {
		return busDeny("agent %s (%s) may not give verdicts; the orchestrator reviews your record", caller.ID, caller.Role)
	}
	verdict := strings.TrimSpace(req.Kind)
	if verdict != VerdictPass && verdict != VerdictFail {
		return busDeny("agent %s: verdict %q is not pass or fail", caller.ID, verdict)
	}
	reason, deny := requireText(caller, "verdict", req.Text)
	if deny != nil {
		return *deny
	}
	target, err := d.target(caller, req.To, "verdict")
	if err != nil {
		return busDeny("%v", err)
	}
	if verdict == VerdictPass && strings.TrimSpace(target.Verification) == "" {
		return busDeny("verdict from %s: %s has no verification to pass; ask for evidence or verify it yourself first", caller.ID, target.ID)
	}
	r := recordOf(target)
	if _, err := d.saveRecord(target, Record{Goal: r.Goal, WorkStatus: r.WorkStatus, Verification: r.Verification, Verdict: verdict, VerdictNote: reason},
		"Verdict from the orchestrator: "+verdict+" - "+reason); err != nil {
		log.Printf("bus: verdict for %s: %v", target.ID, err)
		return BusResponse{Error: err.Error()}
	}
	if target.ID != caller.ID {
		d.logEntry(caller, fmt.Sprintf("Verdict for %s (%s): %s - %s", target.Name, target.ID, verdict, reason))
	}
	d.post(caller.ChatID, target.ID, caller.Name, KindProgress, fmt.Sprintf("Verdict for %s: %s. %s", target.Name, verdict, reason))
	return BusResponse{OK: true, AgentID: target.ID}
}

func (d *Daemon) busRecord(caller Agent, req BusRequest) BusResponse {
	target, err := d.target(caller, req.To, "record")
	if err != nil {
		return busDeny("%v", err)
	}
	if target.ID != caller.ID && caller.Role != RoleOrchestrator {
		return busDeny("agent %s (%s) may read only its own record", caller.ID, caller.Role)
	}
	full, err := readLog(d.cfg.WorkspaceDir, target.ID)
	if err != nil {
		log.Printf("bus: record of %s for %s: %v", target.ID, caller.ID, err)
		return BusResponse{Error: err.Error()}
	}
	text := fmt.Sprintf("%s (%s), %s on %s\n%s\nFiles: %s/\n\nTrack record:\n%s",
		target.Name, target.ID, target.Role, target.Harness, recordSummary(target), agentRecordPath(target.ID), orNotSet(full))
	return BusResponse{OK: true, AgentID: target.ID, Text: text}
}

func (d *Daemon) ServeApp(ctx context.Context, conn net.Conn) {
	defer conn.Close()
	events, unsubscribe := d.hub.Subscribe()
	defer unsubscribe()
	out := make(chan AppEvent, 64)
	done := make(chan struct{})
	go writeEvents(conn, out, events, done)
	defer close(done)

	scanner := bufio.NewScanner(conn)
	scanner.Buffer(make([]byte, 0, 64*1024), maxLine)
	for scanner.Scan() {
		d.handleApp(ctx, scanner.Bytes(), out)
	}
	if err := scanner.Err(); err != nil {
		log.Printf("app: read: %v", err)
	}
}

func writeEvents(conn net.Conn, direct chan AppEvent, live <-chan AppEvent, done chan struct{}) {
	enc := json.NewEncoder(conn)
	for {
		select {
		case ev := <-direct:
			if enc.Encode(ev) != nil {
				return
			}
		case ev, ok := <-live:
			if !ok || enc.Encode(ev) != nil {
				return
			}
		case <-done:
			return
		}
	}
}

func appDeny(out chan AppEvent, format string, args ...any) {
	msg := fmt.Sprintf(format, args...)
	log.Printf("app: denied: %s", msg)
	out <- AppEvent{Type: EventError, Error: msg}
}

func (d *Daemon) handleApp(ctx context.Context, line []byte, out chan AppEvent) {
	var req AppRequest
	if err := json.Unmarshal(line, &req); err != nil {
		appDeny(out, "malformed request: %v", err)
		return
	}
	switch req.Op {
	case OpHello:
		d.appHello(req.Since, out)
	case OpSend:
		if err := d.HandleUserMessage(ctx, req.ChatID, req.Text); err != nil {
			appDeny(out, "send: %v", err)
		}
	case OpCreateChat:
		if _, err := d.CreateChat(req.Title); err != nil {
			appDeny(out, "create chat: %v", err)
		}
	case OpDeleteChat:
		if err := d.DeleteChat(ctx, req.ChatID); err != nil {
			appDeny(out, "delete chat %s: %v", req.ChatID, err)
		}
	case OpStop:
		if err := d.StopAgent(ctx, req.AgentID); err != nil {
			appDeny(out, "stop %s: %v", req.AgentID, err)
		}
	default:
		appDeny(out, "unknown op %q", req.Op)
	}
}

func (d *Daemon) appHello(since int64, out chan AppEvent) {
	chats, err := d.store.Chats()
	if err != nil {
		appDeny(out, "list chats: %v", err)
		return
	}
	agents, err := d.store.Agents()
	if err != nil {
		appDeny(out, "list agents: %v", err)
		return
	}
	messages, err := d.store.MessagesSince(since)
	if err != nil {
		appDeny(out, "history: %v", err)
		return
	}
	for i := range chats {
		out <- AppEvent{Type: EventChat, Chat: &chats[i]}
	}
	for i := range agents {
		out <- AppEvent{Type: EventAgent, Agent: &agents[i]}
	}
	for i := range messages {
		out <- AppEvent{Type: EventMessage, Message: &messages[i]}
	}
	out <- AppEvent{Type: EventReady}
}
