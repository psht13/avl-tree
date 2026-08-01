#!/usr/bin/env bash
set -euo pipefail
ROOT="${1:-smart-tv-remote}"
mkdir -p "$ROOT"

# From bootstrap-028.sh
mkdir -p "$ROOT/remoteapp"
cat >> "$ROOT/remoteapp/samsung.go" <<'__SRT_028_EOF__'
	payload = make([]byte, int(length))
	if _, err = io.ReadFull(reader, payload); err != nil {
		return
	}
	if masked {
		for i := range payload {
			payload[i] ^= mask[i%4]
		}
	}
	return
}

func (c *SamsungClient) writeFrame(opcode byte, payload []byte) error {
	c.mu.RLock()
	conn := c.conn
	c.mu.RUnlock()
	if conn == nil {
		return errors.New("TV не підключено")
	}

	c.writeMu.Lock()
	defer c.writeMu.Unlock()

	var header []byte
	length := len(payload)
	if length < 126 {
		header = []byte{0x80 | opcode, 0x80 | byte(length)}
	} else if length <= 65535 {
		header = make([]byte, 4)
		header[0] = 0x80 | opcode
		header[1] = 0x80 | 126
		binary.BigEndian.PutUint16(header[2:], uint16(length))
	} else {
		header = make([]byte, 10)
		header[0] = 0x80 | opcode
		header[1] = 0x80 | 127
		binary.BigEndian.PutUint64(header[2:], uint64(length))
	}
	mask := make([]byte, 4)
	if _, err := rand.Read(mask); err != nil {
		return err
	}
	masked := make([]byte, len(payload))
	for i := range payload {
		masked[i] = payload[i] ^ mask[i%4]
	}
	if _, err := conn.Write(header); err != nil {
		return err
	}
	if _, err := conn.Write(mask); err != nil {
		return err
	}
	_, err := conn.Write(masked)
	return err
}

func (c *SamsungClient) Send(command any) error {
	if !c.IsConnected() {
		return errors.New("TV не підключено")
	}
	payload, err := json.Marshal(command)
	if err != nil {
		return err
	}
	return c.writeFrame(0x1, payload)
}

func (c *SamsungClient) SendKey(key string) error {
	return c.Send(map[string]any{
		"method": "ms.remote.control",
		"params": map[string]any{
			"Cmd":          "Click",
			"DataOfCmd":    key,
			"Option":       "false",
			"TypeOfRemote": "SendRemoteKey",
		},
	})
}

func (c *SamsungClient) Move(x, y int) error {
	if x > 100 {
		x = 100
	}
	if x < -100 {
		x = -100
	}
	if y > 100 {
		y = 100
	}
	if y < -100 {
		y = -100
	}
	return c.Send(map[string]any{
		"method": "ms.remote.control",
		"params": map[string]any{
			"Cmd":          "Move",
			"Position":     map[string]any{"x": x, "y": y, "Time": "0"},
			"TypeOfRemote": "ProcessMouseDevice",
		},
	})
}

func (c *SamsungClient) Click() error {
	return c.Send(map[string]any{
		"method": "ms.remote.control",
		"params": map[string]any{
			"Cmd":          "LeftClick",
			"TypeOfRemote": "ProcessMouseDevice",
		},
	})
}

func (c *SamsungClient) SendText(text string) error {
	if strings.TrimSpace(text) == "" {
		return errors.New("текст порожній")
	}
	_ = c.Send(map[string]any{
		"method": "ms.channel.emit",
		"params": map[string]any{"event": "custom.remote.textReceived", "to": "broadcast"},
	})
	if err := c.Send(map[string]any{
		"method": "ms.remote.control",
		"params": map[string]any{
			"Cmd":          base64.StdEncoding.EncodeToString([]byte(text)),
			"DataOfCmd":    "base64",
			"TypeOfRemote": "SendInputString",
		},
	}); err != nil {
		return err
	}
	return c.Send(map[string]any{
		"method": "ms.remote.control",
		"params": map[string]any{"TypeOfRemote": "SendInputEnd"},
	})
}

func (c *SamsungClient) LaunchApp(appID, actionType, metaTag string) error {
	if strings.TrimSpace(appID) == "" {
		return errors.New("не задано app ID")
	}
	if actionType == "" {
		actionType = "NATIVE_LAUNCH"
	}
	return c.Send(map[string]any{
		"method": "ms.channel.emit",
		"params": map[string]any{
			"event": "ed.apps.launch",
			"to":    "host",
			"data": map[string]any{
				"appId":       appID,
				"action_type": actionType,
				"metaTag":     metaTag,
			},
		},
	})
}

func (c *SamsungClient) LaunchBrowser() (LaunchResult, error) {
	return c.LaunchKnownApp("browser")
}

func (c *SamsungClient) LaunchYouTube() (LaunchResult, error) {
	return c.LaunchKnownApp("youtube")
}

func (c *SamsungClient) LaunchNetflix() (LaunchResult, error) {
	return c.LaunchKnownApp("netflix")
}

func (c *SamsungClient) LaunchPlayStation() error {
	// Samsung does not expose the user's console name through this remote
	// channel. KEY_HDMI switches to the last active HDMI input, which is the
	// safest model-independent shortcut until a preferred HDMI port is saved.
	return c.SendKey("KEY_HDMI")
}

func (c *SamsungClient) isClosing() bool {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.closing
}

func (c *SamsungClient) Close() {
	c.mu.Lock()
	c.closing = true
	conn := c.conn
	c.conn = nil
	c.reader = nil
	c.connected = false
	c.port = 0
	c.mu.Unlock()
	if conn != nil {
		_ = conn.Close()
	}
}
__SRT_028_EOF__

# From bootstrap-029.sh
mkdir -p "$ROOT/remoteapp"
cat > "$ROOT/remoteapp/samsung_apps.go" <<'__SRT_029_EOF__'
package remoteapp

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"
)

type SamsungInstalledApp struct {
	AppID   string `json:"appId"`
	Name    string `json:"name"`
	AppType int    `json:"appType"`
}

type samsungAppCandidate struct {
	AppID      string
	Name       string
	ActionType string
	MetaTag    string
}

func rawSamsungApps(raw json.RawMessage) json.RawMessage {
	trimmed := bytes.TrimSpace(raw)
	if len(trimmed) == 0 || bytes.Equal(trimmed, []byte("null")) {
		return nil
	}
	if trimmed[0] == '"' {
		var text string
		if json.Unmarshal(trimmed, &text) == nil {
			return json.RawMessage(text)
		}
	}
	if trimmed[0] == '{' {
		var object map[string]json.RawMessage
		if json.Unmarshal(trimmed, &object) == nil {
			for _, key := range []string{"data", "apps", "applications"} {
				if nested := object[key]; len(nested) > 0 {
					return rawSamsungApps(nested)
				}
			}
		}
	}
	return trimmed
}

func flexibleInt(value any) int {
	switch typed := value.(type) {
	case float64:
		return int(typed)
	case json.Number:
		result, _ := strconv.Atoi(string(typed))
		return result
	case string:
		result, _ := strconv.Atoi(strings.TrimSpace(typed))
		return result
	}
	return 0
}

func firstMapString(values map[string]any, keys ...string) string {
	for _, key := range keys {
		if value, ok := values[key]; ok {
			if text, ok := value.(string); ok && strings.TrimSpace(text) != "" {
				return strings.TrimSpace(text)
			}
		}
	}
	return ""
}

func parseSamsungInstalledApps(raw json.RawMessage) []SamsungInstalledApp {
	raw = rawSamsungApps(raw)
	if len(raw) == 0 {
		return nil
	}
	decoder := json.NewDecoder(bytes.NewReader(raw))
	decoder.UseNumber()
	var entries []map[string]any
	if err := decoder.Decode(&entries); err != nil {
		return nil
	}
	apps := make([]SamsungInstalledApp, 0, len(entries))
	seen := map[string]bool{}
	for _, entry := range entries {
		id := firstMapString(entry, "appId", "app_id", "id")
		if id == "" || seen[id] {
			continue
		}
		seen[id] = true
		appType := 0
		for _, key := range []string{"app_type", "appType", "type"} {
			if value, ok := entry[key]; ok {
				appType = flexibleInt(value)
				if appType != 0 {
					break
				}
			}
		}
		apps = append(apps, SamsungInstalledApp{
			AppID:   id,
			Name:    firstMapString(entry, "name", "title", "appName"),
			AppType: appType,
		})
	}
	return apps
}

func (c *SamsungClient) deliverInstalledApps(apps []SamsungInstalledApp) {
	c.appListMu.Lock()
	ch := c.appListWait
	c.appListMu.Unlock()
	if ch == nil {
		return
	}
	select {
	case ch <- apps:
	default:
	}
}

func (c *SamsungClient) GetInstalledApps(timeout time.Duration) ([]SamsungInstalledApp, error) {
	if !c.IsConnected() {
		return nil, errors.New("Samsung TV не підключено")
	}
	ch := make(chan []SamsungInstalledApp, 1)
	c.appListMu.Lock()
	if c.appListWait != nil {
		c.appListMu.Unlock()
		return nil, errors.New("список застосунків Samsung уже запитується")
	}
	c.appListWait = ch
	c.appListMu.Unlock()
	defer func() {
		c.appListMu.Lock()
		if c.appListWait == ch {
			c.appListWait = nil
		}
		c.appListMu.Unlock()
	}()

	if err := c.Send(map[string]any{
		"method": "ms.channel.emit",
		"params": map[string]any{
			"event": "ed.installedApp.get",
			"to":    "host",
			"data":  map[string]any{},
		},
	}); err != nil {
		return nil, err
	}
	select {
	case apps := <-ch:
		c.log(fmt.Sprintf("Samsung TV повернув список застосунків: %d.", len(apps)))
		return apps, nil
	case <-time.After(timeout):
		return nil, errors.New("TV не повернув список установлених застосунків")
	}
}

func samsungActionType(appType int) string {
	if appType == 4 {
		return "NATIVE_LAUNCH"
	}
	// Modern Tizen models report app_type 2 and require DEEP_LINK even when
	// only opening the app's home screen.
	return "DEEP_LINK"
}

func appMatchScore(kind string, app SamsungInstalledApp) int {
	name := strings.ToLower(strings.TrimSpace(app.Name))
	id := strings.ToLower(strings.TrimSpace(app.AppID))
	score := 0
	switch kind {
	case "youtube":
		if name == "youtube" {
			score += 100
		}
		if strings.Contains(name, "youtube") {
			score += 55
		}
		if app.AppID == "111299001912" {
			score += 80
		}
		if strings.Contains(name, "kids") || strings.Contains(name, "music") || strings.Contains(name, "tv") {
			score -= 20
		}
	case "netflix":
		if name == "netflix" {
			score += 100
		}
		if strings.Contains(name, "netflix") || strings.Contains(id, "netflix") {
			score += 60
		}
		if app.AppID == "3201907018807" || app.AppID == "11101200001" {
			score += 80
		}
	case "browser":
		if name == "internet" || name == "web browser" || name == "browser" {
			score += 100
		}
		if strings.Contains(name, "browser") || strings.Contains(name, "internet") || strings.Contains(id, "browser") {
			score += 60
		}
		if app.AppID == "3202010022079" || app.AppID == "org.tizen.browser" || app.AppID == "com.tizen.browser" {
			score += 80
		}
	}
	return score
}

func bestSamsungInstalledApp(kind string, apps []SamsungInstalledApp) *SamsungInstalledApp {
	bestScore := 0
	var best *SamsungInstalledApp
	for index := range apps {
		score := appMatchScore(kind, apps[index])
		if score > bestScore {
			bestScore = score
			copy := apps[index]
			best = &copy
		}
	}
	return best
}

func samsungCandidates(kind string, installed []SamsungInstalledApp) []samsungAppCandidate {
	var candidates []samsungAppCandidate
	if app := bestSamsungInstalledApp(kind, installed); app != nil {
		meta := ""
		if kind == "browser" {
			meta = "https://www.google.com"
		}
		candidates = append(candidates, samsungAppCandidate{
			AppID:      app.AppID,
			Name:       firstNonEmpty(app.Name, kind),
			ActionType: samsungActionType(app.AppType),
			MetaTag:    meta,
		})
	}
	switch kind {
	case "youtube":
		candidates = append(candidates,
			samsungAppCandidate{AppID: "111299001912", Name: "YouTube", ActionType: "DEEP_LINK"},
			samsungAppCandidate{AppID: "111299001912", Name: "YouTube", ActionType: "NATIVE_LAUNCH"},
		)
	case "netflix":
		candidates = append(candidates,
			samsungAppCandidate{AppID: "3201907018807", Name: "Netflix", ActionType: "DEEP_LINK"},
			samsungAppCandidate{AppID: "11101200001", Name: "Netflix", ActionType: "DEEP_LINK"},
			samsungAppCandidate{AppID: "3201907018807", Name: "Netflix", ActionType: "NATIVE_LAUNCH"},
		)
	case "browser":
		candidates = append(candidates,
			samsungAppCandidate{AppID: "3202010022079", Name: "Internet", ActionType: "DEEP_LINK", MetaTag: "https://www.google.com"},
			samsungAppCandidate{AppID: "org.tizen.browser", Name: "Samsung Browser", ActionType: "NATIVE_LAUNCH", MetaTag: "https://www.google.com"},
			samsungAppCandidate{AppID: "com.tizen.browser", Name: "Samsung Browser", ActionType: "NATIVE_LAUNCH", MetaTag: "https://www.google.com"},
		)
	}
	seen := map[string]bool{}
	result := make([]samsungAppCandidate, 0, len(candidates))
	for _, candidate := range candidates {
		key := candidate.AppID + "|" + candidate.ActionType + "|" + candidate.MetaTag
		if candidate.AppID == "" || seen[key] {
			continue
		}
		seen[key] = true
		result = append(result, candidate)
	}
	return result
}
__SRT_029_EOF__
