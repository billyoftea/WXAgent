package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"time"

	"github.com/billyoftea/wxagent/go_backend/internal/config"
	"github.com/billyoftea/wxagent/go_backend/internal/pipeline"
	"github.com/billyoftea/wxagent/go_backend/internal/server"
)

func main() {
	configPath := flag.String("config", "", "Path to config.json")
	flag.Parse()

	if flag.NArg() < 1 {
		printUsage()
		os.Exit(1)
	}

	cmd := flag.Arg(0)

	// Load config
	cfg, err := config.LoadPipeline(*configPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error loading config: %v\n", err)
		os.Exit(1)
	}

	pipe, err := pipeline.New(cfg)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error initializing pipeline: %v\n", err)
		os.Exit(1)
	}

	switch cmd {
	case "refresh-key":
		runRefreshKey(pipe)
	case "export":
		runExport(pipe)
	case "summarize":
		runSummarize(pipe)
	case "server":
		runServer(pipe)
	case "start":
		runStart(pipe)
	default:
		fmt.Fprintf(os.Stderr, "Unknown command: %s\n", cmd)
		printUsage()
		os.Exit(1)
	}
}

func printUsage() {
	fmt.Println("Usage: wxagent_backend [options] <command>")
	fmt.Println("Commands:")
	fmt.Println("  start         Start backend server and launch UI")
	fmt.Println("  refresh-key   Refresh WeChat database key")
	fmt.Println("  export        Trigger echotrace export")
	fmt.Println("  summarize     Run summary pipeline")
	fmt.Println("  server        Start HTTP server")
	fmt.Println("Options:")
	flag.PrintDefaults()
}

func runRefreshKey(p *pipeline.Pipeline) {
	fs := flag.NewFlagSet("refresh-key", flag.ExitOnError)
	ensure := fs.Bool("ensure", false, "Auto launch wx_key if missing")
	wait := fs.Int("wait", 120, "Wait seconds")
	poll := fs.Int("poll", 5, "Poll interval seconds")
	fs.Parse(flag.Args()[1:])

	payload, err := p.RefreshKey(*ensure, *wait, *poll)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error refreshing key: %v\n", err)
		os.Exit(1)
	}

	out, _ := json.MarshalIndent(payload, "", "  ")
	fmt.Println(string(out))
}

func runExport(p *pipeline.Pipeline) {
	fs := flag.NewFlagSet("export", flag.ExitOnError)
	fs.Parse(flag.Args()[1:])

	if err := p.TriggerExport(fs.Args(), false); err != nil {
		fmt.Fprintf(os.Stderr, "Error triggering export: %v\n", err)
		os.Exit(1)
	}
	fmt.Println("Export triggered successfully.")
}

func runSummarize(p *pipeline.Pipeline) {
	fs := flag.NewFlagSet("summarize", flag.ExitOnError)
	start := fs.String("start-date", "", "Start date YYYY-MM-DD")
	end := fs.String("end-date", "", "End date YYYY-MM-DD")
	full := fs.Bool("full", false, "Full export (ignore incremental)")
	// questions handling is tricky with flag, skipping for now or simple string
	fs.Parse(flag.Args()[1:])

	res, err := p.RunSummary(*start, *end, !*full, nil)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error running summary: %v\n", err)
		os.Exit(1)
	}
	out, _ := json.MarshalIndent(res, "", "  ")
	fmt.Println(string(out))
}

func runServer(p *pipeline.Pipeline) {
	fs := flag.NewFlagSet("server", flag.ExitOnError)
	port := fs.Int("port", 8000, "Port to listen on")
	host := fs.String("host", "0.0.0.0", "Host to listen on")
	fs.Parse(flag.Args()[1:])

	addr := fmt.Sprintf("%s:%d", *host, *port)
	srv := server.New(p)

	fmt.Printf("🚀 Starting server on %s...\n", addr)
	if err := srv.Run(addr); err != nil {
		fmt.Fprintf(os.Stderr, "Server error: %v\n", err)
		os.Exit(1)
	}
}

func runStart(p *pipeline.Pipeline) {
	fs := flag.NewFlagSet("start", flag.ExitOnError)
	port := fs.Int("port", 8000, "Port to listen on")
	host := fs.String("host", "127.0.0.1", "Host to listen on")
	uiPath := fs.String("ui", "echotrace.exe", "Path to UI executable")
	fs.Parse(flag.Args()[1:])

	addr := fmt.Sprintf("%s:%d", *host, *port)
	srv := server.New(p)

	// Start server in background
	go func() {
		fmt.Printf("🚀 Starting backend server on %s...\n", addr)
		if err := srv.Run(addr); err != nil {
			fmt.Fprintf(os.Stderr, "Server error: %v\n", err)
			os.Exit(1)
		}
	}()

	// Give server a moment to start
	time.Sleep(1 * time.Second)

	// Resolve UI path
	finalUIPath := *uiPath
	if finalUIPath == "echotrace.exe" {
		if _, err := os.Stat(finalUIPath); os.IsNotExist(err) {
			// Try bundled path
			bundledPath := "bin/echotrace/echotrace.exe"
			if _, err := os.Stat(bundledPath); err == nil {
				finalUIPath = bundledPath
			} else {
				// Try dev path
				devPath := "../echotrace/build/windows/x64/runner/Release/echotrace.exe"
				if _, err := os.Stat(devPath); err == nil {
					finalUIPath = devPath
				}
			}
		}
	}

	// Launch UI
	fmt.Printf("🎨 Launching UI: %s...\n", finalUIPath)
	cmd := exec.Command(finalUIPath)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr

	if err := cmd.Start(); err != nil {
		fmt.Printf("❌ Failed to start UI: %v\n", err)
		fmt.Println("Running in server-only mode. Press Ctrl+C to exit.")
		select {} // Block forever
	}

	// Wait for UI to exit
	if err := cmd.Wait(); err != nil {
		fmt.Printf("UI exited with error: %v\n", err)
	}

	fmt.Println("👋 UI closed, shutting down...")
}
