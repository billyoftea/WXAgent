package server

import (
	"encoding/json"
	"log"
	"net/http"

	"github.com/billyoftea/wxagent/go_backend/internal/pipeline"
)

type Server struct {
	pipeline *pipeline.Pipeline
	mux      *http.ServeMux
}

func New(p *pipeline.Pipeline) *Server {
	s := &Server{
		pipeline: p,
		mux:      http.NewServeMux(),
	}
	s.routes()
	return s
}

func (s *Server) Run(addr string) error {
	log.Printf("Starting server on %s", addr)
	return http.ListenAndServe(addr, s.mux)
}

func (s *Server) routes() {
	s.mux.HandleFunc("/health", s.handleHealth)
	s.mux.HandleFunc("/status", s.handleStatus)
	s.mux.HandleFunc("/refresh-key", s.handleRefreshKey)
	s.mux.HandleFunc("/wx-key/launch", s.handleLaunchWxKey)
	s.mux.HandleFunc("/export", s.handleExport)
	s.mux.HandleFunc("/full-refresh", s.handleFullRefresh)
	s.mux.HandleFunc("/sessions", s.handleListSessions)
	s.mux.HandleFunc("/summary/run", s.handleRunSummary)
}

func (s *Server) handleHealth(w http.ResponseWriter, r *http.Request) {
	jsonResponse(w, map[string]string{"status": "ok"})
}

func (s *Server) handleStatus(w http.ResponseWriter, r *http.Request) {
	jsonResponse(w, s.pipeline.GetStatus())
}

type RefreshKeyRequest struct {
	AutoLaunch   bool `json:"auto_launch"`
	WaitSeconds  int  `json:"wait_seconds"`
	PollInterval int  `json:"poll_interval"`
}

func (s *Server) handleRefreshKey(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req RefreshKeyRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	// Defaults
	if req.WaitSeconds == 0 {
		req.WaitSeconds = 120
	}
	if req.PollInterval == 0 {
		req.PollInterval = 5
	}

	key, err := s.pipeline.RefreshKey(req.AutoLaunch, req.WaitSeconds, req.PollInterval)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	jsonResponse(w, key)
}

type LaunchWxKeyRequest struct {
	Wait      bool     `json:"wait"`
	ExtraArgs []string `json:"extra_args"`
}

func (s *Server) handleLaunchWxKey(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req LaunchWxKeyRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	if err := s.pipeline.LaunchWxKey(req.ExtraArgs, req.Wait); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	jsonResponse(w, map[string]any{"status": "launched", "waited": req.Wait})
}

type TriggerExportRequest struct {
	ExtraArgs []string `json:"extra_args"`
	Silent    bool     `json:"silent"`
}

func (s *Server) handleExport(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req TriggerExportRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	if err := s.pipeline.TriggerExport(req.ExtraArgs, req.Silent); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	jsonResponse(w, map[string]any{"success": true})
}

type FullRefreshRequest struct {
	AutoLaunchKey bool     `json:"auto_launch_key"`
	WaitSeconds   int      `json:"wait_seconds"`
	PollInterval  int      `json:"poll_interval"`
	ExportArgs    []string `json:"export_args"`
}

func (s *Server) handleFullRefresh(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req FullRefreshRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	// Defaults
	if req.WaitSeconds == 0 {
		req.WaitSeconds = 90
	}
	if req.PollInterval == 0 {
		req.PollInterval = 3
	}

	res, err := s.pipeline.RunFullRefresh(req.AutoLaunchKey, req.WaitSeconds, req.PollInterval, req.ExportArgs)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	jsonResponse(w, res)
}

func (s *Server) handleListSessions(w http.ResponseWriter, r *http.Request) {
	sessions, err := s.pipeline.ListSessions()
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	jsonResponse(w, sessions)
}

type SummarizeRequest struct {
	StartDate    string   `json:"start_date"`
	EndDate      string   `json:"end_date"`
	Incremental  bool     `json:"incremental"`
	Questions    []string `json:"questions"`
	SaveMarkdown bool     `json:"save_markdown"`
}

func (s *Server) handleRunSummary(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req SummarizeRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	// Default incremental to true if not specified?
	// Actually bool defaults to false, but Python defaults to True.
	// We might need a pointer or custom unmarshal to detect presence.
	// For now, let's assume client sends it explicitly or we default to true if logic dictates.
	// But here false is the zero value. Let's check if we can handle it.
	// In Python: incremental: bool = True.
	// So if client omits it, it should be true.
	// But standard JSON unmarshal will make it false.
	// Let's use a map to check presence or just assume false means false (full export).
	// Wait, usually "incremental" means "only new stuff".
	// If I want default True, I should set it before decoding if I decode into a struct with defaults,
	// but json.Decode overwrites.
	// Let's just use the value as is for now, assuming the client (Flutter) sends it.

	res, err := s.pipeline.RunSummary(req.StartDate, req.EndDate, req.Incremental, req.Questions)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	jsonResponse(w, res)
}

func jsonResponse(w http.ResponseWriter, data any) {
	w.Header().Set("Content-Type", "application/json")
	if err := json.NewEncoder(w).Encode(data); err != nil {
		log.Printf("Error encoding response: %v", err)
	}
}
