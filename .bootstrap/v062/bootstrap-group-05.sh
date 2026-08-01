#!/usr/bin/env bash
set -euo pipefail
ROOT="${1:-smart-tv-remote}"
mkdir -p "$ROOT"

# From bootstrap-020.sh
mkdir -p "$ROOT/remoteapp"
cat >> "$ROOT/remoteapp/google.go" <<'__SRT_020_EOF__'
		if reader == nil {
			return
		}
		select {
		case <-stopCh:
			return
		default:
		}
		length, err := binary.ReadUvarint(reader)
		if err != nil {
			if !c.isClosing() {
				c.log("З'єднання Google TV завершено: " + err.Error())
				c.notifyConnectError(err)
				if c.IsConnected() {
					c.status("disconnected", "Google TV відключено")
				}
			}
			c.setDisconnected()
			return
		}
		if length == 0 || length > 4<<20 {
			c.log("Google TV надіслав некоректний пакет.")
			continue
		}
		raw := make([]byte, int(length))
		if _, err := io.ReadFull(reader, raw); err != nil {
			if !c.isClosing() {
				c.log("Помилка читання Google TV: " + err.Error())
				c.notifyConnectError(err)
			}
			c.setDisconnected()
			return
		}
		var msg gp.RemoteMessage
		if err := proto.Unmarshal(raw, &msg); err != nil {
			c.log("Ігнорую невідоме повідомлення Google TV.")
			continue
		}
		c.handleMessage(&msg)
	}
}

func (c *GoogleTVClient) handleMessage(msg *gp.RemoteMessage) {
	switch {
	case msg.RemoteConfigure != nil:
		info := msg.RemoteConfigure.DeviceInfo
		c.mu.Lock()
		c.supportedFeatures = msg.RemoteConfigure.Code1
		if info != nil {
			c.modelName = info.Model
			c.vendor = info.Vendor
		}
		model, vendor, app := c.modelName, c.vendor, c.currentApp
		c.mu.Unlock()
		if c.OnDevice != nil {
			c.OnDevice(model, vendor, app)
		}
		_ = c.sendConfiguration()
		c.markReady()
	case msg.RemoteSetActive != nil:
		_ = c.writeMessage(&gp.RemoteMessage{RemoteSetActive: &gp.RemoteSetActive{Active: googleFeatures}})
		c.markReady()
	case msg.RemotePingRequest != nil:
		_ = c.writeMessage(&gp.RemoteMessage{RemotePingResponse: &gp.RemotePingResponse{Val1: msg.RemotePingRequest.Val1}})
	case msg.RemoteImeKeyInject != nil:
		if msg.RemoteImeKeyInject.AppInfo != nil {
			c.mu.Lock()
			c.currentApp = msg.RemoteImeKeyInject.AppInfo.AppPackage
			model, vendor, app := c.modelName, c.vendor, c.currentApp
			c.mu.Unlock()
			if c.OnDevice != nil {
				c.OnDevice(model, vendor, app)
			}
		}
	case msg.RemoteImeBatchEdit != nil:
		c.mu.Lock()
		c.imeCounter = msg.RemoteImeBatchEdit.ImeCounter
		c.fieldCounter = msg.RemoteImeBatchEdit.FieldCounter
		c.mu.Unlock()
	case msg.RemoteStart != nil:
		c.markReady()
	case msg.RemoteSetVolumeLevel != nil:
		c.markReady()
	}
}

func (c *GoogleTVClient) sendConfiguration() error {
	return c.writeMessage(&gp.RemoteMessage{RemoteConfigure: &gp.RemoteConfigure{
		Code1: googleFeatures,
		DeviceInfo: &gp.RemoteDeviceInfo{
			Model:       "SmartTVRemote",
			Vendor:      "Smart TV Remote",
			Unknown1:    1,
			Unknown2:    "1",
			PackageName: "com.paul.smarttvremote",
			AppVersion:  appVersion,
		},
	}})
}

func (c *GoogleTVClient) writeMessage(msg *gp.RemoteMessage) error {
	c.mu.RLock()
	conn := c.conn
	open := c.sessionOpen
	c.mu.RUnlock()
	if conn == nil || !open {
		return errors.New("Google TV не підключено")
	}
	raw, err := proto.Marshal(msg)
	if err != nil {
		return err
	}
	var prefix [binary.MaxVarintLen64]byte
	n := binary.PutUvarint(prefix[:], uint64(len(raw)))
	c.writeMu.Lock()
	defer c.writeMu.Unlock()
	if _, err := conn.Write(prefix[:n]); err != nil {
		return err
	}
	_, err = conn.Write(raw)
	return err
}

func googleKeyCode(key string) (gp.RemoteKeyCode, bool) {
	codes := map[string]gp.RemoteKeyCode{
		"KEY_POWER":    gp.RemoteKeyCode_KEYCODE_POWER,
		"KEY_HOME":     gp.RemoteKeyCode_KEYCODE_HOME,
		"KEY_SOURCE":   gp.RemoteKeyCode_KEYCODE_TV_INPUT,
		"KEY_MENU":     gp.RemoteKeyCode_KEYCODE_SETTINGS,
		"KEY_RETURN":   gp.RemoteKeyCode_KEYCODE_BACK,
		"KEY_EXIT":     gp.RemoteKeyCode_KEYCODE_BACK,
		"KEY_UP":       gp.RemoteKeyCode_KEYCODE_DPAD_UP,
		"KEY_DOWN":     gp.RemoteKeyCode_KEYCODE_DPAD_DOWN,
		"KEY_LEFT":     gp.RemoteKeyCode_KEYCODE_DPAD_LEFT,
		"KEY_RIGHT":    gp.RemoteKeyCode_KEYCODE_DPAD_RIGHT,
		"KEY_ENTER":    gp.RemoteKeyCode_KEYCODE_DPAD_CENTER,
		"KEY_VOLUP":    gp.RemoteKeyCode_KEYCODE_VOLUME_UP,
		"KEY_VOLDOWN":  gp.RemoteKeyCode_KEYCODE_VOLUME_DOWN,
		"KEY_CHUP":     gp.RemoteKeyCode_KEYCODE_CHANNEL_UP,
		"KEY_CHDOWN":   gp.RemoteKeyCode_KEYCODE_CHANNEL_DOWN,
		"KEY_MUTE":     gp.RemoteKeyCode_KEYCODE_VOLUME_MUTE,
		"KEY_REWIND":   gp.RemoteKeyCode_KEYCODE_MEDIA_REWIND,
		"KEY_FF":       gp.RemoteKeyCode_KEYCODE_MEDIA_FAST_FORWARD,
		"KEY_PLAY":     gp.RemoteKeyCode_KEYCODE_MEDIA_PLAY,
		"KEY_PAUSE":    gp.RemoteKeyCode_KEYCODE_MEDIA_PAUSE,
		"KEY_HDMI":     gp.RemoteKeyCode_KEYCODE_TV_INPUT,
		"KEY_DEL":      gp.RemoteKeyCode_KEYCODE_DEL,
		"KEY_SEARCH":   gp.RemoteKeyCode_KEYCODE_SEARCH,
		"KEY_EXPLORER": gp.RemoteKeyCode_KEYCODE_EXPLORER,
	}
	code, ok := codes[key]
	return code, ok
}

func (c *GoogleTVClient) SendKey(key string) error {
	if !c.IsConnected() {
		return errors.New("Google TV ще не підключено. Заверши сполучення кодом з екрана TV")
	}
	code, ok := googleKeyCode(key)
	if !ok {
		return fmt.Errorf("Google TV не знає команду %s", key)
	}
	return c.writeMessage(&gp.RemoteMessage{RemoteKeyInject: &gp.RemoteKeyInject{
		KeyCode:   code,
		Direction: gp.RemoteDirection_SHORT,
	}})
}

func (c *GoogleTVClient) Move(x, y int) error {
	if x == 0 && y == 0 {
		return nil
	}
	var code gp.RemoteKeyCode
	if absInt(x) >= absInt(y) {
		if x > 0 {
			code = gp.RemoteKeyCode_KEYCODE_DPAD_RIGHT
		} else {
			code = gp.RemoteKeyCode_KEYCODE_DPAD_LEFT
		}
	} else if y > 0 {
		code = gp.RemoteKeyCode_KEYCODE_DPAD_DOWN
	} else {
		code = gp.RemoteKeyCode_KEYCODE_DPAD_UP
	}
	now := time.Now()
	c.mu.Lock()
	if c.lastMoveKey == int32(code) && now.Sub(c.lastMove) < 105*time.Millisecond {
		c.mu.Unlock()
		return nil
	}
	c.lastMove = now
	c.lastMoveKey = int32(code)
	c.mu.Unlock()
	if !c.IsConnected() {
		return errors.New("Google TV ще не підключено")
	}
	return c.writeMessage(&gp.RemoteMessage{RemoteKeyInject: &gp.RemoteKeyInject{KeyCode: code, Direction: gp.RemoteDirection_SHORT}})
}

func absInt(value int) int {
	if value < 0 {
		return -value
	}
	return value
}

func (c *GoogleTVClient) Click() error { return c.SendKey("KEY_ENTER") }

func (c *GoogleTVClient) SendText(text string) error {
	text = strings.TrimSpace(text)
	if text == "" {
		return errors.New("текст порожній")
	}
	if !c.IsConnected() {
		return errors.New("Google TV ще не підключено")
	}
	c.mu.RLock()
	counter, field := c.imeCounter, c.fieldCounter
	c.mu.RUnlock()
	position := int32(len([]rune(text)) - 1)
	return c.writeMessage(&gp.RemoteMessage{RemoteImeBatchEdit: &gp.RemoteImeBatchEdit{
		ImeCounter:   counter,
		FieldCounter: field,
		EditInfo: []*gp.RemoteEditInfo{{
			Insert: 1,
			TextFieldStatus: &gp.RemoteImeObject{
				Start: position,
				End:   position,
				Value: text,
			},
		}},
	}})
}

func (c *GoogleTVClient) CurrentApp() string {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.currentApp
}

func packageMatches(current string, targets []string) bool {
	current = strings.ToLower(strings.TrimSpace(current))
	if current == "" {
		return false
	}
	for _, target := range targets {
		target = strings.ToLower(strings.TrimSpace(target))
		if target != "" && (current == target || strings.Contains(current, target)) {
			return true
		}
	}
	return false
}

func (c *GoogleTVClient) waitForCurrentApp(targets []string, timeout time.Duration) (string, bool) {
__SRT_020_EOF__

# From bootstrap-021.sh
mkdir -p "$ROOT/remoteapp"
cat >> "$ROOT/remoteapp/google.go" <<'__SRT_021_EOF__'
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		current := c.CurrentApp()
		if packageMatches(current, targets) {
			return current, true
		}
		time.Sleep(140 * time.Millisecond)
	}
	return c.CurrentApp(), false
}

func (c *GoogleTVClient) sendAppLink(link string) error {
	return c.writeMessage(&gp.RemoteMessage{RemoteAppLinkLaunchRequest: &gp.RemoteAppLinkLaunchRequest{AppLink: link}})
}

type googleLaunchPlan struct {
	Name       string
	Targets    []string
	Links      []string
	InitialKey string
}

func googlePlan(app string) (googleLaunchPlan, error) {
	switch app {
	case "browser":
		return googleLaunchPlan{
			Name:       "браузер",
			Targets:    []string{"browser", "browse", "tvweb", "internet"},
			InitialKey: "KEY_EXPLORER",
			Links: []string{
				"com.internet.tvbrowser",
				"com.phlox.tvwebbrowser",
				"market://launch?id=com.internet.tvbrowser",
				"market://launch?id=com.phlox.tvwebbrowser",
				"https://www.google.com",
			},
		}, nil
	case "youtube":
		return googleLaunchPlan{
			Name:    "YouTube",
			Targets: []string{"com.google.android.youtube.tv", "youtube"},
			Links: []string{
				"https://www.youtube.com",
				"com.google.android.youtube.tv",
				"market://launch?id=com.google.android.youtube.tv",
				"vnd.youtube://",
				"https://www.youtube.com/tv",
			},
		}, nil
	case "netflix":
		return googleLaunchPlan{
			Name:    "Netflix",
			Targets: []string{"com.netflix.ninja", "netflix"},
			Links: []string{
				"com.netflix.ninja",
				"market://launch?id=com.netflix.ninja",
				"nflx://www.netflix.com/browse",
				"https://www.netflix.com",
			},
		}, nil
	default:
		return googleLaunchPlan{}, errors.New("невідомий застосунок")
	}
}

func (c *GoogleTVClient) LaunchApp(app string) (LaunchResult, error) {
	if !c.IsConnected() {
		return LaunchResult{}, errors.New("Google TV ще не підключено. Введи код сполучення, після чого кнопки стануть активними")
	}
	if app == "playstation" {
		if err := c.SendKey("KEY_HDMI"); err != nil {
			return LaunchResult{}, err
		}
		return LaunchResult{Confirmed: true, Message: "Відкриваю вибір входу / HDMI", Attempts: []string{"KEYCODE_TV_INPUT"}}, nil
	}
	plan, err := googlePlan(app)
	if err != nil {
		return LaunchResult{}, err
	}
	attempts := make([]string, 0, len(plan.Links)+1)
	if packageMatches(c.CurrentApp(), plan.Targets) {
		return LaunchResult{Confirmed: true, Message: plan.Name + " уже відкрито", AppID: c.CurrentApp()}, nil
	}
	if plan.InitialKey != "" {
		attempts = append(attempts, plan.InitialKey)
		if err := c.SendKey(plan.InitialKey); err == nil {
			if current, ok := c.waitForCurrentApp(plan.Targets, 900*time.Millisecond); ok {
				c.log(plan.Name + " відкрито системною кнопкою Google TV.")
				return LaunchResult{Confirmed: true, Message: plan.Name + " відкрито", AppID: current, Attempts: attempts}, nil
			}
		} else {
			c.log("Системна команда запуску " + plan.Name + " не спрацювала: " + err.Error())
		}
	}
	var lastErr error
	for _, link := range plan.Links {
		attempts = append(attempts, link)
		c.log("Google TV: пробую запустити " + plan.Name + " через " + link)
		if err := c.sendAppLink(link); err != nil {
			lastErr = err
			continue
		}
		if current, ok := c.waitForCurrentApp(plan.Targets, 1100*time.Millisecond); ok {
			c.log(plan.Name + " підтверджено активним застосунком: " + current)
			return LaunchResult{Confirmed: true, Message: plan.Name + " відкрито", AppID: current, Attempts: attempts}, nil
		}
	}
	if lastErr != nil && len(attempts) == 0 {
		return LaunchResult{}, lastErr
	}
	c.log("Google TV прийняв команди запуску " + plan.Name + ", але не повідомив активний пакет.")
	return LaunchResult{
		Confirmed: false,
		Message:   "Команди запуску " + plan.Name + " надіслано. Якщо нічого не змінилося, застосунок або браузер не встановлений на TV.",
		Attempts:  attempts,
	}, nil
}

func (c *GoogleTVClient) isClosing() bool {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.closing
}

func (c *GoogleTVClient) setDisconnected() {
	c.mu.Lock()
	c.connected = false
	c.sessionOpen = false
	c.conn = nil
	c.reader = nil
	c.mu.Unlock()
}

func (c *GoogleTVClient) Close() {
	c.mu.Lock()
	c.closing = true
	conn := c.conn
	stopCh := c.stopCh
	pair := c.pair
	c.conn = nil
	c.reader = nil
	c.connected = false
	c.sessionOpen = false
	c.pair = nil
	c.pairing = false
	c.stopCh = nil
	c.readyCh = nil
	c.readyOnce = nil
	c.connectErr = nil
	c.mu.Unlock()
	if stopCh != nil {
		select {
		case <-stopCh:
		default:
			close(stopCh)
		}
	}
	if conn != nil {
		_ = conn.Close()
	}
	if pair != nil {
		pair.close()
	}
}
__SRT_021_EOF__
