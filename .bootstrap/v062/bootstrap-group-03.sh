#!/usr/bin/env bash
set -euo pipefail
ROOT="${1:-smart-tv-remote}"
mkdir -p "$ROOT"

# From bootstrap-017.sh
mkdir -p "$ROOT/remoteapp"
cat >> "$ROOT/remoteapp/app.go" <<'__SRT_017_EOF__'
func (a *App) selectAndConnectDiscovered(devices []DeviceInfo) (*DeviceInfo, error) {
	a.mu.RLock()
	cfg := *a.activeConfigLocked()
	provider := a.cfg.Provider
	a.mu.RUnlock()
	selected := selectDevice(devices, cfg)
	if selected == nil {
		if len(devices) == 0 {
			return nil, errors.New(providerLabel(provider) + " не знайдено в цій Wi-Fi мережі")
		}
		return nil, errors.New("знайдено кілька TV. Введи IP потрібного телевізора вручну")
	}
	a.mu.Lock()
	active := a.activeConfigLocked()
	active.IP = selected.IP
	active.DeviceID = firstNonEmpty(selected.ID, selected.DUID, active.DeviceID)
	active.DisplayName = firstNonEmpty(selected.DisplayName, active.DisplayName, providerLabel(provider))
	active.ModelName = firstNonEmpty(selected.ModelName, selected.Model, active.ModelName)
	a.mu.Unlock()
	_ = a.saveConfig()
	a.connectAsync(provider, selected.IP)
	return selected, nil
}

func selectDevice(devices []DeviceInfo, cfg DeviceConfig) *DeviceInfo {
	if cfg.IP != "" {
		for i := range devices {
			if devices[i].IP == cfg.IP {
				return &devices[i]
			}
		}
	}
	if cfg.DeviceID != "" {
		for i := range devices {
			if strings.EqualFold(cfg.DeviceID, devices[i].ID) || strings.EqualFold(cfg.DeviceID, devices[i].DUID) {
				return &devices[i]
			}
		}
	}
	if len(devices) == 1 {
		return &devices[0]
	}
	return nil
}

type controlModeDetection struct {
	Mode      string
	Supported bool
}

func flexibleBool(value any) (bool, bool) {
	switch typed := value.(type) {
	case bool:
		return typed, true
	case string:
		switch strings.ToLower(strings.TrimSpace(typed)) {
		case "true", "1":
			return true, true
		case "false", "0":
			return false, true
		}
	case float64:
		if typed == 1 {
			return true, true
		}
		if typed == 0 {
			return false, true
		}
	}
	return false, false
}

func fetchSamsungAppState(ip, appID string, timeout time.Duration) (active bool, supported bool) {
	client := &http.Client{Timeout: timeout, Transport: &http.Transport{DisableKeepAlives: true}}
	endpoint := "http://" + net.JoinHostPort(ip, "8001") + "/api/v2/applications/" + url.PathEscape(appID)
	resp, err := client.Get(endpoint)
	if err != nil {
		return false, false
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return false, false
	}
	var payload map[string]any
	if err := json.NewDecoder(resp.Body).Decode(&payload); err != nil {
		return false, false
	}
	visible, visibleKnown := flexibleBool(payload["visible"])
	running, runningKnown := flexibleBool(payload["running"])
	if visibleKnown {
		return visible, true
	}
	if runningKnown {
		return running, true
	}
	return false, true
}

func detectSamsungControlMode(ip string) controlModeDetection {
	browserIDs := []string{"org.tizen.browser", "3202010022079"}
	supported := false
	for _, appID := range browserIDs {
		active, appSupported := fetchSamsungAppState(ip, appID, 900*time.Millisecond)
		if !appSupported {
			continue
		}
		supported = true
		if active {
			return controlModeDetection{Mode: "pointer", Supported: true}
		}
	}
	if supported {
		return controlModeDetection{Mode: "dpad", Supported: true}
	}
	return controlModeDetection{Mode: "unknown", Supported: false}
}

func (a *App) setControlModeHint(mode string) {
	if mode != "pointer" && mode != "dpad" && mode != "unknown" {
		return
	}
	a.mu.Lock()
	a.controlModeHint = mode
	a.mu.Unlock()
}

func (a *App) stopControlModeMonitor() {
	a.mu.Lock()
	cancel := a.monitorCancel
	a.monitorCancel = nil
	a.autoModeSupported = false
	a.mu.Unlock()
	if cancel != nil {
		cancel()
	}
}

func (a *App) startControlModeMonitor(ip string) {
	a.mu.Lock()
	previousCancel := a.monitorCancel
	ctx, cancel := context.WithCancel(context.Background())
	a.monitorCancel = cancel
	a.autoModeSupported = false
	a.mu.Unlock()
	if previousCancel != nil {
		previousCancel()
	}
	go func() {
		ticker := time.NewTicker(2100 * time.Millisecond)
		defer ticker.Stop()
		first := true
		for {
			detection := detectSamsungControlMode(ip)
			select {
			case <-ctx.Done():
				return
			default:
			}
			a.mu.Lock()
			oldMode := a.controlModeHint
			oldSupported := a.autoModeSupported
			a.autoModeSupported = detection.Supported
			if detection.Supported && detection.Mode != "unknown" {
				a.controlModeHint = detection.Mode
			}
			newMode := a.controlModeHint
			a.mu.Unlock()
			if first || oldSupported != detection.Supported {
				if detection.Supported {
					a.addLog("Автоматичне визначення активного Samsung Browser доступне.")
				} else if first {
					a.addLog("TV не віддає стан застосунків. Залишено автоперемикання після запуску та ручний режим.")
				}
			}
			if detection.Supported && oldMode != newMode {
				if newMode == "pointer" {
					a.addLog("Samsung Browser видимий: центральний блок переходить у курсор.")
				} else {
					a.addLog("Samsung Browser не видимий: повертаю звичайний D-pad.")
				}
			}
			first = false
			select {
			case <-ctx.Done():
				return
			case <-ticker.C:
			}
		}
	}()
}

func (a *App) sendKey(key string) error {
	a.mu.RLock()
	provider := a.cfg.Provider
	a.mu.RUnlock()
	if provider == ProviderGoogle {
		return a.google.SendKey(key)
	}
	return a.samsung.SendKey(key)
}

func (a *App) move(x, y int) error {
	a.mu.RLock()
	provider := a.cfg.Provider
	a.mu.RUnlock()
	if provider == ProviderGoogle {
		return a.google.Move(x, y)
	}
	return a.samsung.Move(x, y)
}

func (a *App) click() error {
	a.mu.RLock()
	provider := a.cfg.Provider
	a.mu.RUnlock()
	if provider == ProviderGoogle {
		return a.google.Click()
	}
	return a.samsung.Click()
}

func (a *App) sendText(text string) error {
	a.mu.RLock()
	provider := a.cfg.Provider
	a.mu.RUnlock()
	if provider == ProviderGoogle {
		return a.google.SendText(text)
	}
	return a.samsung.SendText(text)
}

func (a *App) launch(app string) (LaunchResult, error) {
	a.mu.RLock()
	provider := a.cfg.Provider
	a.mu.RUnlock()
	if provider == ProviderGoogle {
		return a.google.LaunchApp(app)
	}
	switch app {
	case "browser":
		return a.samsung.LaunchBrowser()
	case "youtube":
		return a.samsung.LaunchYouTube()
	case "netflix":
		return a.samsung.LaunchNetflix()
	case "playstation":
		if err := a.samsung.LaunchPlayStation(); err != nil {
			return LaunchResult{}, err
		}
		return LaunchResult{
			Confirmed: true,
			Message:   "Відкриваю останній активний HDMI-вхід",
			Attempts:  []string{"KEY_HDMI"},
		}, nil
	default:
		return LaunchResult{}, errors.New("невідомий застосунок")
	}
}

func (a *App) disconnect() {
	a.stopControlModeMonitor()
	a.closeActive()
	a.mu.Lock()
	a.status = "disconnected"
	a.message = "Відключено вручну"
	a.controlModeHint = "unknown"
	a.pairingRequired = false
	a.mu.Unlock()
}

func (a *App) forget() error {
	a.stopControlModeMonitor()
	a.closeActive()
	a.mu.Lock()
	provider := a.cfg.Provider
	if provider == ProviderGoogle {
		a.cfg.Google = DeviceConfig{}
	} else {
		a.cfg.Samsung = DeviceConfig{}
	}
	a.status = "idle"
	a.message = "TV ще не підключено"
	a.connecting = false
	a.pairingRequired = false
	a.controlModeHint = "unknown"
	a.autoModeSupported = false
	a.logs = nil
	a.mu.Unlock()
	if provider == ProviderGoogle {
		a.google.resetCertificateFiles()
	}
	return a.saveConfig()
}
__SRT_017_EOF__

# From bootstrap-018.sh
mkdir -p "$ROOT/remoteapp"
cat > "$ROOT/remoteapp/discovery.go" <<'__SRT_018_EOF__'
package remoteapp

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"sort"
	"strings"
	"sync"
	"time"
)

type DeviceInfo struct {
	Provider    string `json:"provider"`
	IP          string `json:"ip"`
	ID          string `json:"id,omitempty"`
	DUID        string `json:"duid,omitempty"`
	DisplayName string `json:"displayName,omitempty"`
	Model       string `json:"model,omitempty"`
	ModelName   string `json:"modelName,omitempty"`
	Type        string `json:"type,omitempty"`
	OS          string `json:"os,omitempty"`
}

func canReachSamsung(ip string, timeout time.Duration) bool {
	info, _ := fetchSamsungDeviceInfo(ip, timeout)
	return info != nil
}

func fetchSamsungDeviceInfo(ip string, timeout time.Duration) (*DeviceInfo, error) {
	client := &http.Client{Timeout: timeout, Transport: &http.Transport{DisableKeepAlives: true}}
	resp, err := client.Get("http://" + net.JoinHostPort(ip, "8001") + "/api/v2/")
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("HTTP %s", resp.Status)
	}
	var payload struct {
		Device map[string]any `json:"device"`
		ID     string         `json:"id"`
		Name   string         `json:"name"`
		Type   string         `json:"type"`
	}
	if err := json.NewDecoder(io.LimitReader(resp.Body, 1<<20)).Decode(&payload); err != nil {
		return nil, err
	}
	get := func(key string) string {
		if value, ok := payload.Device[key].(string); ok {
			return strings.TrimSpace(value)
		}
		return ""
	}
	info := &DeviceInfo{
		Provider:    ProviderSamsung,
		IP:          ip,
		ID:          firstNonEmpty(get("id"), payload.ID),
		DUID:        get("duid"),
		DisplayName: firstNonEmpty(get("name"), payload.Name, "Samsung TV"),
		Model:       get("model"),
		ModelName:   get("modelName"),
		Type:        firstNonEmpty(get("type"), payload.Type),
		OS:          firstNonEmpty(get("OS"), get("os")),
	}
	joined := strings.ToLower(strings.Join([]string{info.DisplayName, info.Type, info.OS, get("description")}, " "))
	if !strings.Contains(joined, "samsung") && !strings.Contains(joined, "tizen") {
		return nil, errors.New("пристрій не схожий на Samsung TV")
	}
	return info, nil
}

func discoverSamsungTVs() ([]DeviceInfo, error) {
	return scanSubnet(func(ip string) (*DeviceInfo, error) {
		return fetchSamsungDeviceInfo(ip, 650*time.Millisecond)
	})
}

func canReachGoogleTV(ip string, timeout time.Duration) bool {
	for _, port := range []string{"6466", "6467"} {
		conn, err := net.DialTimeout("tcp", net.JoinHostPort(ip, port), timeout)
		if err == nil {
			_ = conn.Close()
			return true
		}
	}
	return false
}

func discoverGoogleTVs() ([]DeviceInfo, error) {
	return scanSubnet(func(ip string) (*DeviceInfo, error) {
		if !canReachGoogleTV(ip, 450*time.Millisecond) {
			return nil, errors.New("not google tv")
		}
		return &DeviceInfo{
			Provider:    ProviderGoogle,
			IP:          ip,
			DisplayName: "Google TV / Android TV",
			ModelName:   "Thomson або сумісний Google TV",
			OS:          "Google TV",
		}, nil
	})
}

func scanSubnet(probe func(string) (*DeviceInfo, error)) ([]DeviceInfo, error) {
	local, err := localPrivateIPv4()
	if err != nil {
		return nil, err
	}
	parts := strings.Split(local.String(), ".")
	if len(parts) != 4 {
		return nil, errors.New("не вдалося визначити локальну підмережу")
	}
	prefix := strings.Join(parts[:3], ".")
	jobs := make(chan string)
	results := make(chan DeviceInfo, 16)
	var wg sync.WaitGroup
	workers := 42
	for i := 0; i < workers; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for ip := range jobs {
				if info, err := probe(ip); err == nil && info != nil {
					results <- *info
				}
			}
		}()
	}
	go func() {
		for host := 1; host <= 254; host++ {
			ip := fmt.Sprintf("%s.%d", prefix, host)
			if ip != local.String() {
				jobs <- ip
			}
		}
		close(jobs)
		wg.Wait()
		close(results)
	}()

	var devices []DeviceInfo
	seen := map[string]bool{}
	for info := range results {
		if !seen[info.IP] {
			seen[info.IP] = true
			devices = append(devices, info)
		}
	}
	sort.Slice(devices, func(i, j int) bool { return devices[i].IP < devices[j].IP })
	return devices, nil
}

func localPrivateIPv4() (net.IP, error) {
	interfaces, err := net.Interfaces()
	if err != nil {
		return nil, err
	}
	for _, iface := range interfaces {
		if iface.Flags&net.FlagUp == 0 || iface.Flags&net.FlagLoopback != 0 {
			continue
		}
		addrs, _ := iface.Addrs()
		for _, addr := range addrs {
			var ip net.IP
			switch value := addr.(type) {
			case *net.IPNet:
				ip = value.IP
			case *net.IPAddr:
				ip = value.IP
			}
			ip = ip.To4()
			if ip == nil {
				continue
			}
			if ip[0] == 10 || (ip[0] == 172 && ip[1] >= 16 && ip[1] <= 31) || (ip[0] == 192 && ip[1] == 168) {
				return ip, nil
			}
		}
	}
	return nil, errors.New("пристрій не підключений до приватної локальної мережі")
}
__SRT_018_EOF__
