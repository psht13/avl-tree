#!/usr/bin/env bash
set -euo pipefail
ROOT="${1:-smart-tv-remote}"
mkdir -p "$ROOT"

# From bootstrap-034.sh
mkdir -p "$ROOT/remoteapp"
cat > "$ROOT/remoteapp/server.go" <<'__SRT_034_EOF__'
package remoteapp

import (
	"context"
	"embed"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"net"
	"net/http"
	"sync"
	"time"
)

//go:embed web/index.html
var webFS embed.FS

type Server struct {
	mu       sync.Mutex
	App      *App
	Listener net.Listener
	HTTP     *http.Server
	URL      string
	closed   bool
}

func StartServer(storageDir string) (*Server, error) {
	app := NewApp(storageDir)
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		return nil, err
	}
	server := &http.Server{
		Handler:           app.routes(),
		ReadHeaderTimeout: 5 * time.Second,
		IdleTimeout:       60 * time.Second,
	}
	result := &Server{
		App:      app,
		Listener: listener,
		HTTP:     server,
		URL:      "http://" + listener.Addr().String(),
	}
	go func() {
		_ = server.Serve(listener)
	}()
	go func() {
		time.Sleep(350 * time.Millisecond)
		app.autoConnect()
	}()
	return result, nil
}

func (s *Server) Close() error {
	s.mu.Lock()
	if s.closed {
		s.mu.Unlock()
		return nil
	}
	s.closed = true
	s.mu.Unlock()
	if s.App != nil {
		s.App.disconnect()
	}
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	return s.HTTP.Shutdown(ctx)
}

func keyReturnsToDpad(key string) bool {
	switch key {
	case "KEY_HOME", "KEY_SOURCE", "KEY_MENU", "KEY_RETURN", "KEY_EXIT", "KEY_HDMI":
		return true
	default:
		return false
	}
}

func (a *App) routes() http.Handler {
	mux := http.NewServeMux()
	content, _ := fs.ReadFile(webFS, "web/index.html")
	staticFS, err := fs.Sub(webFS, "web")
	if err != nil {
		panic(err)
	}
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/" {
			http.NotFound(w, r)
			return
		}
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		w.Header().Set("Cache-Control", "no-store")
		_, _ = w.Write(content)
	})
	mux.HandleFunc("/api/state", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusOK, a.snapshot())
	})
	mux.HandleFunc("/api/provider", func(w http.ResponseWriter, r *http.Request) {
		var body struct {
			Provider string `json:"provider"`
		}
		if err := decodeJSON(r, &body); err != nil {
			writeError(w, http.StatusBadRequest, err)
			return
		}
		if err := a.SetProvider(body.Provider); err != nil {
			writeError(w, http.StatusBadRequest, err)
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{"ok": true})
	})
	mux.HandleFunc("/api/connect", func(w http.ResponseWriter, r *http.Request) {
		var body struct {
			Provider string `json:"provider"`
			IP       string `json:"ip"`
		}
		if err := decodeJSON(r, &body); err != nil {
			writeError(w, http.StatusBadRequest, err)
			return
		}
		a.connectAsync(body.Provider, body.IP)
		writeJSON(w, http.StatusAccepted, map[string]any{"ok": true})
	})
	mux.HandleFunc("/api/pair", func(w http.ResponseWriter, r *http.Request) {
		var body struct {
			Code string `json:"code"`
		}
		if err := decodeJSON(r, &body); err != nil {
			writeError(w, http.StatusBadRequest, err)
			return
		}
		if err := a.completeGooglePairing(body.Code); err != nil {
			writeError(w, http.StatusBadGateway, err)
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{"ok": true})
	})
	mux.HandleFunc("/api/discover", func(w http.ResponseWriter, r *http.Request) {
		devices, err := a.discover()
		if err != nil {
			writeError(w, http.StatusBadGateway, err)
			return
		}
		selected, selectErr := a.selectAndConnectDiscovered(devices)
		writeJSON(w, http.StatusOK, map[string]any{
			"devices":  devices,
			"selected": selected,
			"message": func() string {
				if selectErr != nil {
					return selectErr.Error()
				}
				return "TV знайдено, підключаюсь"
			}(),
		})
	})
	mux.HandleFunc("/api/key", func(w http.ResponseWriter, r *http.Request) {
		var body struct {
			Key string `json:"key"`
		}
		if err := decodeJSON(r, &body); err != nil || body.Key == "" {
			writeError(w, http.StatusBadRequest, errors.New("не задано key"))
			return
		}
		err := a.sendKey(body.Key)
		if err == nil && keyReturnsToDpad(body.Key) {
			a.setControlModeHint("dpad")
		}
		writeCommandResult(w, err)
	})
	mux.HandleFunc("/api/move", func(w http.ResponseWriter, r *http.Request) {
		var body struct{ X, Y int }
		if err := decodeJSON(r, &body); err != nil {
			writeError(w, http.StatusBadRequest, err)
			return
		}
		writeCommandResult(w, a.move(body.X, body.Y))
	})
	mux.HandleFunc("/api/click", func(w http.ResponseWriter, r *http.Request) {
		writeCommandResult(w, a.click())
	})
	mux.HandleFunc("/api/text", func(w http.ResponseWriter, r *http.Request) {
		var body struct {
			Text string `json:"text"`
		}
		if err := decodeJSON(r, &body); err != nil {
			writeError(w, http.StatusBadRequest, err)
			return
		}
		writeCommandResult(w, a.sendText(body.Text))
	})
	mux.HandleFunc("/api/launch", func(w http.ResponseWriter, r *http.Request) {
		var body struct {
			App string `json:"app"`
		}
		if err := decodeJSON(r, &body); err != nil {
			writeError(w, http.StatusBadRequest, err)
			return
		}
		result, err := a.launch(body.App)
		if err != nil {
			writeError(w, http.StatusBadGateway, err)
			return
		}
		// Google TV uses D-pad navigation even when a browser opens. Samsung
		// can switch to pointer mode, but only after the browser launch is
		// confirmed. This prevents a failed launch from silently changing the
		// controls into an unusable cursor.
		provider := a.snapshot().Provider
		if result.Confirmed {
			mode := "dpad"
			if provider == ProviderSamsung && body.App == "browser" {
				mode = "pointer"
			}
			a.setControlModeHint(mode)
		}
		writeJSON(w, http.StatusOK, map[string]any{
			"ok":        true,
			"confirmed": result.Confirmed,
			"message":   result.Message,
			"appId":     result.AppID,
			"attempts":  result.Attempts,
		})
	})
	mux.HandleFunc("/api/disconnect", func(w http.ResponseWriter, r *http.Request) {
		a.disconnect()
		writeJSON(w, http.StatusOK, map[string]any{"ok": true})
	})
	mux.HandleFunc("/api/forget", func(w http.ResponseWriter, r *http.Request) {
		if err := a.forget(); err != nil {
			writeError(w, http.StatusInternalServerError, err)
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{"ok": true})
	})
	return securityHeaders(mux)
}

func securityHeaders(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("X-Content-Type-Options", "nosniff")
		w.Header().Set("X-Frame-Options", "SAMEORIGIN")
		w.Header().Set("Referrer-Policy", "no-referrer")
		next.ServeHTTP(w, r)
	})
}

func decodeJSON(r *http.Request, target any) error {
	defer r.Body.Close()
	decoder := json.NewDecoder(io.LimitReader(r.Body, 1<<20))
	return decoder.Decode(target)
}

func writeJSON(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(value)
}

func writeError(w http.ResponseWriter, status int, err error) {
	writeJSON(w, status, map[string]any{"ok": false, "error": err.Error()})
}

func writeCommandResult(w http.ResponseWriter, err error) {
	if err != nil {
		writeError(w, http.StatusBadGateway, err)
		return
	}
__SRT_034_EOF__

# From bootstrap-035.sh
mkdir -p "$ROOT/remoteapp"
cat >> "$ROOT/remoteapp/server.go" <<'__SRT_035_EOF__'
	writeJSON(w, http.StatusOK, map[string]any{"ok": true})
}

func (s *Server) String() string {
	return fmt.Sprintf("%s %s", appName, s.URL)
}
__SRT_035_EOF__
