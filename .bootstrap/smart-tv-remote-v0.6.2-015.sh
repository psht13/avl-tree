#!/usr/bin/env bash
set -euo pipefail
ROOT="${1:-smart-tv-remote}"
mkdir -p "$ROOT/remoteapp"
cat > "$ROOT/remoteapp/app.go" <<'__SRT_015_EOF__'
package remoteapp

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

const (
	appName         = "Smart TV Remote"
	appVersion      = "0.6.2"
	ProviderSamsung = "samsung"
	ProviderGoogle  = "google"
)

type DeviceConfig struct {
	IP          string `json:"ip,omitempty"`
	Token       string `json:"token,omitempty"`
	DeviceID    string `json:"deviceId,omitempty"`
	DisplayName string `json:"displayName,omitempty"`
	ModelName   string `json:"modelName,omitempty"`
	LastPort    int    `json:"lastPort,omitempty"`
}

type Config struct {
	Provider string       `json:"provider"`
	Samsung  DeviceConfig `json:"samsung"`
	Google   DeviceConfig `json:"google"`
}

type Snapshot struct {
	Version           string   `json:"version"`
	Provider          string   `json:"provider"`
	ProviderLabel     string   `json:"providerLabel"`
	Status            string   `json:"status"`
	Message           string   `json:"message"`
	Connected         bool     `json:"connected"`
	Connecting        bool     `json:"connecting"`
	Discovering       bool     `json:"discovering"`
	PairingRequired   bool     `json:"pairingRequired"`
	IP                string   `json:"ip"`
	Port              int      `json:"port"`
	HasToken          bool     `json:"hasToken"`
	DisplayName       string   `json:"displayName,omitempty"`
	ModelName         string   `json:"modelName,omitempty"`
	DeviceID          string   `json:"deviceId,omitempty"`
	ControlModeHint   string   `json:"controlModeHint"`
	AutoModeSupported bool     `json:"autoModeSupported"`
	PointerNote       string   `json:"pointerNote,omitempty"`
	Logs              []string `json:"logs"`
}

type App struct {
	mu                sync.RWMutex
	cfg               Config
	samsung           *SamsungClient
	google            *GoogleTVClient
	status            string
	message           string
	connecting        bool
	discovering       bool
	pairingRequired   bool
	logs              []string
	storageDir        string
	configPath        string
	controlModeHint   string
	autoModeSupported bool
	monitorCancel     context.CancelFunc
}

func NewApp(storageDir string) *App {
	if strings.TrimSpace(storageDir) == "" {
		storageDir = defaultStorageDir()
	}
	_ = os.MkdirAll(storageDir, 0o700)
	a := &App{
		storageDir:      storageDir,
		configPath:      filepath.Join(storageDir, "config.json"),
		status:          "idle",
		message:         "TV ще не підключено",
		controlModeHint: "unknown",
	}
	_ = a.loadConfig()
	if a.cfg.Provider != ProviderSamsung && a.cfg.Provider != ProviderGoogle {
		a.cfg.Provider = ProviderSamsung
	}
	a.samsung = NewSamsungClient()
	a.google = NewGoogleTVClient(storageDir)
	a.configureCallbacks()
	return a
}

func defaultStorageDir() string {
	dir, err := os.UserConfigDir()
	if err != nil || dir == "" {
		dir = os.TempDir()
	}
	return filepath.Join(dir, "SmartTVRemote")
}

func providerLabel(provider string) string {
	if provider == ProviderGoogle {
		return "Thomson / Google TV"
	}
	return "Samsung Tizen"
}

func (a *App) configureCallbacks() {
	a.samsung.OnLog = a.addLog
	a.samsung.OnStatus = func(status, message string) {
		a.mu.Lock()
		if a.cfg.Provider == ProviderSamsung {
			a.status = status
			a.message = message
			if status == "connected" || status == "error" || status == "disconnected" {
				a.connecting = false
			}
		}
		a.mu.Unlock()
		if status == "error" || status == "disconnected" {
			a.stopControlModeMonitor()
		}
	}
	a.samsung.OnToken = func(token string, port int) {
		a.mu.Lock()
		a.cfg.Samsung.Token = token
		a.cfg.Samsung.LastPort = port
		a.mu.Unlock()
		_ = a.saveConfig()
		a.addLog("Токен Samsung TV збережено. Наступного разу підтвердження зазвичай не потрібне.")
	}

	a.google.OnLog = a.addLog
	a.google.OnStatus = func(status, message string) {
		a.mu.Lock()
		if a.cfg.Provider == ProviderGoogle {
			a.status = status
			a.message = message
			a.pairingRequired = status == "pairing" || status == "awaiting-code"
			if status == "connected" || status == "error" || status == "disconnected" || status == "awaiting-code" {
				a.connecting = false
			}
		}
		a.mu.Unlock()
	}
	a.google.OnDevice = func(model, vendor, currentApp string) {
		a.mu.Lock()
		if model != "" {
			a.cfg.Google.ModelName = model
		}
		if a.cfg.Google.DisplayName == "" || a.cfg.Google.DisplayName == "Google TV / Android TV" {
			a.cfg.Google.DisplayName = firstNonEmpty(vendor+" "+model, model, "Thomson Google TV")
		}
		a.mu.Unlock()
		_ = a.saveConfig()
	}
}

func (a *App) addLog(message string) {
	line := time.Now().Format("15:04:05") + "  " + message
	a.mu.Lock()
	a.logs = append([]string{line}, a.logs...)
	if len(a.logs) > 70 {
		a.logs = a.logs[:70]
	}
	a.mu.Unlock()
}

func (a *App) activeConfigLocked() *DeviceConfig {
	if a.cfg.Provider == ProviderGoogle {
		return &a.cfg.Google
	}
	return &a.cfg.Samsung
}

func (a *App) activeConnected() bool {
	a.mu.RLock()
	provider := a.cfg.Provider
	a.mu.RUnlock()
	if provider == ProviderGoogle {
		return a.google.IsConnected()
	}
	return a.samsung.IsConnected()
}

func (a *App) activePort() int {
	a.mu.RLock()
	provider := a.cfg.Provider
	a.mu.RUnlock()
	if provider == ProviderGoogle {
		return a.google.Port()
	}
	return a.samsung.Port()
}

func (a *App) snapshot() Snapshot {
	a.mu.RLock()
	cfg := *a.activeConfigLocked()
	provider := a.cfg.Provider
	logs := append([]string(nil), a.logs...)
	status := a.status
	message := a.message
	connecting := a.connecting
	discovering := a.discovering
	pairingRequired := a.pairingRequired
	controlModeHint := a.controlModeHint
	autoModeSupported := a.autoModeSupported
	a.mu.RUnlock()

	hasToken := cfg.Token != ""
	pointerNote := "Samsung Browser підтримує команди вільного курсора."
	if provider == ProviderGoogle {
		hasToken = a.google.HasPairedCertificate()
		pointerNote = "На Google TV джойстик надсилає швидкі D-pad команди. Справжній вільний курсор без TV Helper не гарантується."
	}
	return Snapshot{
		Version:           appVersion,
		Provider:          provider,
		ProviderLabel:     providerLabel(provider),
		Status:            status,
		Message:           message,
		Connected:         a.activeConnected(),
		Connecting:        connecting,
		Discovering:       discovering,
		PairingRequired:   pairingRequired,
		IP:                cfg.IP,
		Port:              a.activePort(),
		HasToken:          hasToken,
		DisplayName:       cfg.DisplayName,
		ModelName:         cfg.ModelName,
		DeviceID:          cfg.DeviceID,
		ControlModeHint:   controlModeHint,
		AutoModeSupported: autoModeSupported,
		PointerNote:       pointerNote,
		Logs:              logs,
	}
}

func (a *App) loadConfig() error {
	data, err := os.ReadFile(a.configPath)
	if errors.Is(err, os.ErrNotExist) {
		return nil
	}
	if err != nil {
		return err
	}
	var cfg Config
	if err := json.Unmarshal(data, &cfg); err != nil {
		return err
	}
	a.cfg = cfg
	if a.cfg.Provider == "" {
		a.cfg.Provider = ProviderSamsung
	}
	active := a.activeConfigLocked()
	if active.IP != "" {
		a.message = "Збережено " + providerLabel(a.cfg.Provider) + ": " + active.IP
	}
	return nil
}

func (a *App) saveConfig() error {
	a.mu.RLock()
	cfg := a.cfg
__SRT_015_EOF__
