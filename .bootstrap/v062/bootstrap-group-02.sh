#!/usr/bin/env bash
set -euo pipefail
ROOT="${1:-smart-tv-remote}"
mkdir -p "$ROOT"

# From bootstrap-016.sh
mkdir -p "$ROOT/remoteapp"
cat >> "$ROOT/remoteapp/app.go" <<'__SRT_016_EOF__'
	a.mu.RUnlock()
	if err := os.MkdirAll(filepath.Dir(a.configPath), 0o700); err != nil {
		return err
	}
	data, err := json.MarshalIndent(cfg, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(a.configPath, data, 0o600)
}

func (a *App) SetProvider(provider string) error {
	if provider != ProviderSamsung && provider != ProviderGoogle {
		return errors.New("невідома платформа TV")
	}
	a.closeActive()
	a.stopControlModeMonitor()
	a.mu.Lock()
	a.cfg.Provider = provider
	cfg := *a.activeConfigLocked()
	a.status = "idle"
	a.message = "Обрано " + providerLabel(provider)
	if cfg.IP != "" {
		a.message = "Збережено " + providerLabel(provider) + ": " + cfg.IP
	}
	a.connecting = false
	a.discovering = false
	a.pairingRequired = false
	a.controlModeHint = "unknown"
	a.autoModeSupported = false
	a.mu.Unlock()
	return a.saveConfig()
}

func (a *App) closeActive() {
	a.samsung.Close()
	a.google.Close()
}

func normalizeIP(value string) string {
	value = strings.TrimSpace(value)
	value = strings.TrimPrefix(value, "http://")
	value = strings.TrimPrefix(value, "https://")
	if host, _, err := net.SplitHostPort(value); err == nil {
		return host
	}
	if i := strings.IndexByte(value, '/'); i >= 0 {
		value = value[:i]
	}
	return strings.TrimSpace(value)
}

func firstNonEmpty(values ...string) string {
	for _, value := range values {
		if strings.TrimSpace(value) != "" {
			return strings.TrimSpace(value)
		}
	}
	return ""
}

func (a *App) connectAsync(provider, ip string) {
	if provider != "" {
		if err := a.SetProvider(provider); err != nil {
			a.setError(err.Error())
			return
		}
	}
	a.stopControlModeMonitor()
	ip = normalizeIP(ip)
	if net.ParseIP(ip) == nil {
		a.setError("Некоректна IP-адреса.")
		return
	}

	a.mu.Lock()
	if a.connecting {
		a.mu.Unlock()
		return
	}
	a.connecting = true
	a.status = "connecting"
	a.message = "Підключення до " + ip + "…"
	a.pairingRequired = false
	provider = a.cfg.Provider
	active := a.activeConfigLocked()
	old := *active
	active.IP = ip
	a.mu.Unlock()
	_ = a.saveConfig()

	go func() {
		if provider == ProviderGoogle {
			a.connectGoogle(ip, old)
			return
		}
		a.connectSamsung(ip, old)
	}()
}

func (a *App) connectSamsung(ip string, old DeviceConfig) {
	info, _ := fetchSamsungDeviceInfo(ip, 1300*time.Millisecond)
	a.mu.Lock()
	cfg := &a.cfg.Samsung
	if info != nil {
		sameDevice := old.IP == ip || old.DeviceID == "" || old.DeviceID == info.ID || old.DeviceID == info.DUID
		if sameDevice {
			cfg.Token = old.Token
		}
		cfg.DeviceID = firstNonEmpty(info.ID, info.DUID, old.DeviceID)
		cfg.DisplayName = firstNonEmpty(info.DisplayName, old.DisplayName, "Samsung TV")
		cfg.ModelName = firstNonEmpty(info.ModelName, info.Model, old.ModelName)
	} else if old.IP != ip {
		cfg.Token = ""
		cfg.DeviceID = ""
		cfg.DisplayName = "Samsung TV"
		cfg.ModelName = ""
	}
	local := *cfg
	a.mu.Unlock()

	ports := []int{8002, 8001}
	if local.LastPort == 8001 {
		ports = []int{8001, 8002}
	}
	if err := a.samsung.Connect(ip, local.Token, ports); err != nil {
		a.setError(err.Error())
		return
	}
	a.mu.Lock()
	a.cfg.Samsung.IP = ip
	a.cfg.Samsung.LastPort = a.samsung.Port()
	a.connecting = false
	a.status = "connected"
	a.message = fmt.Sprintf("Підключено до Samsung TV через порт %d", a.samsung.Port())
	a.controlModeHint = "dpad"
	a.mu.Unlock()
	_ = a.saveConfig()
	a.startControlModeMonitor(ip)
}

func (a *App) connectGoogle(ip string, old DeviceConfig) {
	a.mu.Lock()
	cfg := &a.cfg.Google
	cfg.IP = ip
	cfg.DisplayName = firstNonEmpty(cfg.DisplayName, old.DisplayName, "Thomson Google TV")
	cfg.ModelName = firstNonEmpty(cfg.ModelName, old.ModelName, "GoogleTV2900")
	a.mu.Unlock()
	_ = a.saveConfig()

	// A PEM file alone does not mean that the TV accepted it. v0.6.0 and
	// v0.6.1 incorrectly treated any generated certificate as a successful
	// pairing, which left the UI looking connected while every control was
	// disabled. Only attempt port 6466 when a verified local pairing marker
	// exists for the current certificate.
	if a.google.HasPairedCertificate() {
		if err := a.google.Connect(ip); err == nil {
			a.mu.Lock()
			a.connecting = false
			a.pairingRequired = false
			a.status = "connected"
			a.message = "Підключено до Thomson / Google TV"
			a.controlModeHint = "dpad"
			a.cfg.Google.LastPort = 6466
			a.mu.Unlock()
			_ = a.saveConfig()
			return
		} else {
			a.addLog("Збережене сполучення Google TV не спрацювало: " + err.Error())
			a.google.clearPairingMarker()
		}
	} else {
		a.addLog("Підтвердженого сполучення Google TV ще немає. Запитую новий код на екрані TV.")
	}

	if err := a.google.BeginPairing(ip); err != nil {
		a.setError(err.Error())
		return
	}
	a.mu.Lock()
	a.connecting = false
	a.pairingRequired = true
	a.status = "awaiting-code"
	a.message = "Введи 6-символьний код з екрана Thomson"
	a.mu.Unlock()
}

func (a *App) completeGooglePairing(code string) error {
	a.mu.RLock()
	provider := a.cfg.Provider
	a.mu.RUnlock()
	if provider != ProviderGoogle {
		return errors.New("спочатку обери Thomson / Google TV")
	}
	a.mu.Lock()
	a.status = "connecting"
	a.message = "Перевіряю код та підключаю TV…"
	a.connecting = true
	a.mu.Unlock()
	if err := a.google.CompletePairing(code); err != nil {
		a.setError(err.Error())
		return err
	}
	a.mu.Lock()
	a.connecting = false
	a.pairingRequired = false
	a.status = "connected"
	a.message = "Thomson / Google TV сполучено і підключено"
	a.controlModeHint = "dpad"
	a.cfg.Google.LastPort = 6466
	a.mu.Unlock()
	_ = a.saveConfig()
	return nil
}

func (a *App) setError(message string) {
	a.mu.Lock()
	a.connecting = false
	a.discovering = false
	a.status = "error"
	a.message = message
	a.mu.Unlock()
	a.addLog(message)
}

func (a *App) autoConnect() {
	a.mu.RLock()
	provider := a.cfg.Provider
	cfg := *a.activeConfigLocked()
	a.mu.RUnlock()
	if cfg.IP == "" {
		return
	}
	go func() {
		a.addLog("Пробую збережену адресу " + cfg.IP + ".")
		reachable := canReachSamsung(cfg.IP, 900*time.Millisecond)
		if provider == ProviderGoogle {
			reachable = canReachGoogleTV(cfg.IP, 900*time.Millisecond)
		}
		if reachable {
			a.connectAsync(provider, cfg.IP)
			return
		}
		a.addLog("Стара IP-адреса не відповідає. Шукаю TV у мережі.")
		devices, err := a.discover()
		if err != nil {
			a.setError(err.Error())
			return
		}
		selected := selectDevice(devices, cfg)
		if selected == nil {
			a.setError("Збережений TV не знайдено. Перевір Wi-Fi або введи IP вручну.")
			return
		}
		a.connectAsync(provider, selected.IP)
	}()
}

func (a *App) discover() ([]DeviceInfo, error) {
	a.mu.Lock()
	if a.discovering {
		a.mu.Unlock()
		return nil, errors.New("пошук уже виконується")
	}
	a.discovering = true
	a.status = "discovering"
	provider := a.cfg.Provider
	a.message = "Шукаю " + providerLabel(provider) + " у локальній мережі…"
	a.mu.Unlock()
	defer func() {
		a.mu.Lock()
		a.discovering = false
		a.mu.Unlock()
	}()

	var devices []DeviceInfo
	var err error
	if provider == ProviderGoogle {
		devices, err = discoverGoogleTVs()
	} else {
		devices, err = discoverSamsungTVs()
	}
	if err != nil {
		return nil, err
	}
	a.addLog(fmt.Sprintf("Автопошук завершено. Знайдено TV: %d.", len(devices)))
	return devices, nil
}
__SRT_016_EOF__
