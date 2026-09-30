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
	case BusAttach:
		return d.busAttach(caller, req)
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

func (d *Daemon) busSpawn(ctx context.Context, caller Agent, req BusRequest) BusResponse {
	if caller.Role != RoleOrchestrator {
		return busDeny("agent %s (%s) may not spawn agents", caller.ID, caller.Role)
	}
	name := strings.TrimSpace(req.Name)
	if name == "" || strings.TrimSpace(req.Task) == "" {
		return busDeny("spawn needs --name and --task")
	}
	harness := firstNonEmpty(req.Harness, d.cfg.WorkerHarness)
	model := firstNonEmpty(req.Model, d.cfg.WorkerModel)
	worker, err := d.createAgent(ctx, caller.ChatID, name, RoleWorker, harness, model, req.Task)
	if err != nil {
		log.Printf("bus: spawn %q for %s failed: %v", name, caller.ID, err)
		return BusResponse{Error: err.Error()}
	}
	d.post(caller.ChatID, worker.ID, "orchestrator", KindProgress, fmt.Sprintf("Started %s (%s) on: %s", name, harness, truncate(req.Task, 200)))
	d.enqueue(worker, req.Task)
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

func (d *Daemon) busSend(caller Agent, req BusRequest) BusResponse {
	if caller.Role != RoleOrchestrator {
		return busDeny("agent %s (%s) may not message other agents", caller.ID, caller.Role)
	}
	target, err := d.store.Agent(req.To)
	if err != nil {
		return busDeny("send from %s to unknown agent %q", caller.ID, req.To)
	}
	if target.ChatID != caller.ChatID {
		return busDeny("send from %s to agent %s in another chat", caller.ID, req.To)
	}
	if strings.TrimSpace(req.Text) == "" {
		return busDeny("send from %s to %s without text", caller.ID, req.To)
	}
	d.enqueue(target, "Message from the orchestrator:\n\n"+req.Text)
	return BusResponse{OK: true, AgentID: target.ID}
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
		go func() {
			if _, err := d.CreateChat(ctx, req); err != nil {
				appDeny(out, "create chat: %v", err)
			}
		}()
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
