package main

import (
	"context"
	"fmt"
	"log"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"
	"time"
)

func main() {
	if filepath.Base(os.Args[0]) == "agentctl" {
		os.Exit(runCtl(os.Args[1:]))
	}
	if len(os.Args) < 2 {
		fmt.Fprintln(os.Stderr, "usage: sshido-agents daemon | attach | file <message-id> | ctl <op>")
		os.Exit(2)
	}
	switch os.Args[1] {
	case "daemon":
		os.Exit(runDaemon())
	case "attach":
		os.Exit(runAttach())
	case "ctl":
		os.Exit(runCtl(os.Args[2:]))
	case "file":
		os.Exit(runFile(os.Args[2:]))
	}
	fmt.Fprintf(os.Stderr, "unknown command %q\n", os.Args[1])
	os.Exit(2)
}

func appSocket(dataDir string) string { return filepath.Join(dataDir, "app.sock") }

func runDaemon() int {
	cfg, err := loadConfig()
	if err != nil {
		log.Printf("config: %v", err)
		return 1
	}
	store, err := openStore(filepath.Join(cfg.DataDir, "agents.db"), time.Now)
	if err != nil {
		log.Printf("%v", err)
		return 1
	}
	defer store.Close()

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()
	d := newDaemon(cfg, store, newPodmanAPI(cfg.PodmanSocket), newRelayPusher(cfg.NotifyURL, cfg.HostName))
	if err := d.Recover(ctx); err != nil {
		log.Printf("recover: %v", err)
	}
	bus, err := listenUnix(filepath.Join(cfg.BusDir, "bus.sock"), 0o666)
	if err != nil {
		log.Printf("%v", err)
		return 1
	}
	app, err := listenUnix(appSocket(cfg.DataDir), 0o600)
	if err != nil {
		log.Printf("%v", err)
		return 1
	}
	log.Printf("sshido-agents daemon ready: orchestrator=%s worker=%s image=%s", cfg.OrchestratorHarness, cfg.WorkerHarness, cfg.AgentImage)
	go serve(ctx, bus, d.ServeBus)
	serve(ctx, app, d.ServeApp)
	return 0
}
