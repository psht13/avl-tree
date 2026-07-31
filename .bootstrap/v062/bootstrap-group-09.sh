#!/usr/bin/env bash
set -euo pipefail
ROOT="${1:-smart-tv-remote}"
mkdir -p "$ROOT"

# From bootstrap-030.sh
mkdir -p "$ROOT/remoteapp"
cat >> "$ROOT/remoteapp/samsung_apps.go" <<'__SRT_030_EOF__'
func (c *SamsungClient) launchAppREST(candidate samsungAppCandidate) error {
	c.mu.RLock()
	ip := c.ip
	c.mu.RUnlock()
	if ip == "" {
		return errors.New("Samsung TV IP невідомий")
	}
	payload, _ := json.Marshal(map[string]string{
		"action_type": candidate.ActionType,
		"metaTag":     candidate.MetaTag,
	})
	endpoint := "http://" + net.JoinHostPort(ip, "8001") + "/api/v2/applications/" + url.PathEscape(candidate.AppID)
	request, err := http.NewRequest(http.MethodPost, endpoint, bytes.NewReader(payload))
	if err != nil {
		return err
	}
	request.Header.Set("Content-Type", "application/json")
	client := &http.Client{Timeout: 1400 * time.Millisecond, Transport: &http.Transport{DisableKeepAlives: true}}
	response, err := client.Do(request)
	if err != nil {
		return err
	}
	defer response.Body.Close()
	_, _ = io.Copy(io.Discard, io.LimitReader(response.Body, 64<<10))
	if response.StatusCode < 200 || response.StatusCode >= 300 {
		return fmt.Errorf("REST launch повернув %s", response.Status)
	}
	return nil
}

func (c *SamsungClient) waitForSamsungApp(ids []string, timeout time.Duration) (string, bool, bool) {
	c.mu.RLock()
	ip := c.ip
	c.mu.RUnlock()
	deadline := time.Now().Add(timeout)
	supported := false
	for time.Now().Before(deadline) {
		for _, id := range ids {
			active, appSupported := fetchSamsungAppState(ip, id, 450*time.Millisecond)
			if appSupported {
				supported = true
			}
			if active {
				return id, true, true
			}
		}
		time.Sleep(160 * time.Millisecond)
	}
	return "", false, supported
}

func samsungFallbackKeys(kind string) []string {
	switch kind {
	case "youtube":
		return []string{"KEY_YOUTUBE"}
	case "netflix":
		return []string{"KEY_NETFLIX"}
	case "browser":
		return []string{"KEY_WEBBROWSER", "KEY_INTERNET"}
	default:
		return nil
	}
}

func displaySamsungKind(kind string) string {
	switch kind {
	case "youtube":
		return "YouTube"
	case "netflix":
		return "Netflix"
	case "browser":
		return "браузер"
	default:
		return kind
	}
}

func (c *SamsungClient) LaunchKnownApp(kind string) (LaunchResult, error) {
	if !c.IsConnected() {
		return LaunchResult{}, errors.New("Samsung TV не підключено")
	}
	name := displaySamsungKind(kind)
	apps, listErr := c.GetInstalledApps(1500 * time.Millisecond)
	if listErr != nil {
		c.log("Список застосунків Samsung недоступний: " + listErr.Error() + ". Використовую перевірені резервні ID.")
	}
	candidates := samsungCandidates(kind, apps)
	if len(candidates) == 0 {
		return LaunchResult{}, errors.New("не знайдено кандидатів для запуску " + name)
	}
	ids := make([]string, 0, len(candidates))
	for _, candidate := range candidates {
		ids = append(ids, candidate.AppID)
	}
	attempts := make([]string, 0, len(candidates)*2+4)
	commandSent := false
	stateSupported := false
	var lastErr error

	// YouTube and Netflix implement DIAL on many Samsung models. A 2xx DIAL
	// response is an explicit launch acknowledgement and avoids Tizen firmware
	// versions that silently ignore ed.apps.launch.
	if samsungDIALAppName(kind) != "" {
		attempts = append(attempts, "DIAL "+samsungDIALAppName(kind))
		c.log("Samsung: пробую DIAL запуск для " + name + ".")
		if endpoint, err := c.launchDIAL(kind); err == nil {
			commandSent = true
			if id, active, supported := c.waitForSamsungApp(ids, 1600*time.Millisecond); active {
				c.log(name + " підтверджено після DIAL: " + id + ".")
				return LaunchResult{Confirmed: true, Message: name + " відкрито", AppID: id, Attempts: attempts}, nil
			} else if supported {
				stateSupported = true
			}
			c.log(name + " прийняв DIAL launch через " + endpoint + ".")
			return LaunchResult{Confirmed: true, Message: name + " відкривається", AppID: endpoint, Attempts: attempts}, nil
		} else {
			lastErr = err
			c.log("DIAL запуск " + name + " недоступний: " + err.Error())
		}
	}

	for _, candidate := range candidates {
		attempt := fmt.Sprintf("WS %s %s", candidate.AppID, candidate.ActionType)
		attempts = append(attempts, attempt)
		c.log("Samsung: пробую " + attempt + " для " + name + ".")
		if err := c.LaunchApp(candidate.AppID, candidate.ActionType, candidate.MetaTag); err != nil {
			lastErr = err
		} else {
			commandSent = true
			if id, active, supported := c.waitForSamsungApp([]string{candidate.AppID}, 950*time.Millisecond); active {
				c.log(name + " підтверджено активним застосунком " + id + ".")
				return LaunchResult{Confirmed: true, Message: name + " відкрито", AppID: id, Attempts: attempts}, nil
			} else if supported {
				stateSupported = true
			}
		}

		attempt = "REST " + candidate.AppID
		attempts = append(attempts, attempt)
		if err := c.launchAppREST(candidate); err != nil {
			lastErr = err
			c.log(attempt + " не спрацював: " + err.Error())
		} else {
			commandSent = true
			if id, active, supported := c.waitForSamsungApp([]string{candidate.AppID}, 950*time.Millisecond); active {
				c.log(name + " підтверджено після REST launch: " + id + ".")
				return LaunchResult{Confirmed: true, Message: name + " відкрито", AppID: id, Attempts: attempts}, nil
			} else if supported {
				stateSupported = true
			}
		}
	}

	for _, key := range samsungFallbackKeys(kind) {
		attempts = append(attempts, key)
		c.log("Samsung: резервна кнопка " + key + " для " + name + ".")
		if err := c.SendKey(key); err != nil {
			lastErr = err
			continue
		}
		commandSent = true
		if id, active, supported := c.waitForSamsungApp(ids, 1100*time.Millisecond); active {
			return LaunchResult{Confirmed: true, Message: name + " відкрито", AppID: id, Attempts: attempts}, nil
		} else if supported {
			stateSupported = true
		}
	}

	if !commandSent {
		if lastErr == nil {
			lastErr = errors.New("TV не прийняв жодну команду запуску")
		}
		return LaunchResult{}, lastErr
	}
	if stateSupported {
		return LaunchResult{
			Confirmed: false,
			Message:   name + " не підтвердив запуск. Перевір, чи застосунок установлений та не заблокований на TV.",
			Attempts:  attempts,
		}, nil
	}
	return LaunchResult{
		Confirmed: false,
		Message:   "Команди запуску " + name + " надіслано, але прошивка TV не віддає стан застосунків.",
		Attempts:  attempts,
	}, nil
}
__SRT_030_EOF__

# From bootstrap-031.sh
mkdir -p "$ROOT/remoteapp"
cat > "$ROOT/remoteapp/samsung_apps_test.go" <<'__SRT_031_EOF__'
package remoteapp

import (
	"encoding/json"
	"testing"
)

func TestParseSamsungInstalledAppsHandlesQuotedPayload(t *testing.T) {
	t.Parallel()
	inner := `[{"appId":"111299001912","name":"YouTube","app_type":2},{"appId":"3201907018807","name":"Netflix","app_type":"2"},{"appId":"3202010022079","name":"Internet","app_type":2}]`
	raw, err := json.Marshal(inner)
	if err != nil {
		t.Fatal(err)
	}
	apps := parseSamsungInstalledApps(raw)
	if len(apps) != 3 {
		t.Fatalf("expected 3 apps, got %#v", apps)
	}
	if apps[0].AppID != "111299001912" || apps[0].AppType != 2 {
		t.Fatalf("unexpected YouTube app: %#v", apps[0])
	}
}

func TestSamsungCandidatesPreferInstalledAppType(t *testing.T) {
	t.Parallel()
	installed := []SamsungInstalledApp{{AppID: "custom-youtube-id", Name: "YouTube", AppType: 2}}
	candidates := samsungCandidates("youtube", installed)
	if len(candidates) == 0 {
		t.Fatal("expected candidates")
	}
	if candidates[0].AppID != "custom-youtube-id" || candidates[0].ActionType != "DEEP_LINK" {
		t.Fatalf("unexpected first candidate: %#v", candidates[0])
	}
}

func TestSamsungFallbackIDsCoverModernTV(t *testing.T) {
	t.Parallel()
	checks := map[string]string{
		"youtube": "111299001912",
		"netflix": "3201907018807",
		"browser": "3202010022079",
	}
	for kind, expectedID := range checks {
		found := false
		for _, candidate := range samsungCandidates(kind, nil) {
			if candidate.AppID == expectedID {
				found = true
				break
			}
		}
		if !found {
			t.Fatalf("%s candidates do not contain %s", kind, expectedID)
		}
	}
}
__SRT_031_EOF__

# From bootstrap-032.sh
mkdir -p "$ROOT/remoteapp"
cat > "$ROOT/remoteapp/samsung_dial.go" <<'__SRT_032_EOF__'
package remoteapp

import (
	"bytes"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"strings"
	"time"
)

const samsungDIALService = "urn:dial-multiscreen-org:service:dial:1"

func parseDIALApplicationURL(response string) string {
	for _, line := range strings.Split(strings.ReplaceAll(response, "\r\n", "\n"), "\n") {
		key, value, ok := strings.Cut(line, ":")
		if !ok || !strings.EqualFold(strings.TrimSpace(key), "Application-URL") {
			continue
		}
		return strings.TrimRight(strings.TrimSpace(value), "/")
	}
	return ""
}

func discoverDIALApplicationURL(ip string, timeout time.Duration) string {
	connection, err := net.ListenUDP("udp4", &net.UDPAddr{IP: net.IPv4zero, Port: 0})
	if err != nil {
		return ""
	}
	defer connection.Close()
	_ = connection.SetDeadline(time.Now().Add(timeout))
	request := strings.Join([]string{
		"M-SEARCH * HTTP/1.1",
		"HOST: 239.255.255.250:1900",
		"MAN: \"ssdp:discover\"",
		"MX: 1",
		"ST: " + samsungDIALService,
		"",
		"",
	}, "\r\n")
	_, _ = connection.WriteToUDP([]byte(request), &net.UDPAddr{IP: net.ParseIP("239.255.255.250"), Port: 1900})
	buffer := make([]byte, 8192)
	for {
		read, sender, err := connection.ReadFromUDP(buffer)
		if err != nil {
			return ""
		}
		if sender == nil || sender.IP.String() != ip {
			continue
		}
		if applicationURL := parseDIALApplicationURL(string(buffer[:read])); applicationURL != "" {
			return applicationURL
		}
	}
}

func samsungDIALAppName(kind string) string {
	switch kind {
	case "youtube":
		return "YouTube"
	case "netflix":
		return "Netflix"
	default:
		return ""
	}
}

func uniqueStrings(values []string) []string {
	seen := make(map[string]struct{}, len(values))
	result := make([]string, 0, len(values))
	for _, value := range values {
		value = strings.TrimRight(strings.TrimSpace(value), "/")
		if value == "" {
			continue
		}
		if _, exists := seen[value]; exists {
			continue
		}
		seen[value] = struct{}{}
		result = append(result, value)
	}
	return result
}

func (c *SamsungClient) launchDIAL(kind string) (string, error) {
	appName := samsungDIALAppName(kind)
	if appName == "" {
		return "", errors.New("DIAL is not available for this app")
	}
	c.mu.RLock()
	ip := c.ip
	c.mu.RUnlock()
	if ip == "" {
		return "", errors.New("Samsung TV IP невідомий")
	}

	baseURLs := []string{
		"http://" + net.JoinHostPort(ip, "8001") + "/ws/apps",
		"http://" + net.JoinHostPort(ip, "8001") + "/ws/app",
	}
	if discovered := discoverDIALApplicationURL(ip, 1200*time.Millisecond); discovered != "" {
		baseURLs = append([]string{discovered}, baseURLs...)
	}
	baseURLs = uniqueStrings(baseURLs)
	client := &http.Client{Timeout: 1600 * time.Millisecond, Transport: &http.Transport{DisableKeepAlives: true}}
	var lastErr error
	for _, baseURL := range baseURLs {
		endpoint := baseURL + "/" + appName
		request, err := http.NewRequest(http.MethodPost, endpoint, bytes.NewReader(nil))
		if err != nil {
			lastErr = err
			continue
		}
		request.Header.Set("Content-Type", "text/plain; charset=utf-8")
		response, err := client.Do(request)
		if err != nil {
			lastErr = err
			continue
		}
		_, _ = io.Copy(io.Discard, io.LimitReader(response.Body, 64<<10))
		_ = response.Body.Close()
		if response.StatusCode >= 200 && response.StatusCode < 300 {
			return endpoint, nil
		}
		lastErr = fmt.Errorf("%s повернув %s", endpoint, response.Status)
	}
	if lastErr == nil {
		lastErr = errors.New("DIAL endpoint не знайдено")
	}
	return "", lastErr
}
__SRT_032_EOF__

# From bootstrap-033.sh
mkdir -p "$ROOT/remoteapp"
cat > "$ROOT/remoteapp/samsung_dial_test.go" <<'__SRT_033_EOF__'
package remoteapp

import "testing"

func TestParseDIALApplicationURL(t *testing.T) {
	t.Parallel()
	response := "HTTP/1.1 200 OK\r\nAPPLICATION-URL: http://192.168.0.10:8001/ws/apps/\r\nST: urn:dial-multiscreen-org:service:dial:1\r\n\r\n"
	if got := parseDIALApplicationURL(response); got != "http://192.168.0.10:8001/ws/apps" {
		t.Fatalf("parseDIALApplicationURL = %q", got)
	}
}

func TestSamsungDIALAppName(t *testing.T) {
	t.Parallel()
	if samsungDIALAppName("youtube") != "YouTube" || samsungDIALAppName("netflix") != "Netflix" {
		t.Fatal("unexpected DIAL app names")
	}
	if samsungDIALAppName("browser") != "" {
		t.Fatal("browser must not use DIAL")
	}
}
__SRT_033_EOF__
