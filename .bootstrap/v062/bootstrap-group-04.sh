#!/usr/bin/env bash
set -euo pipefail
ROOT="${1:-smart-tv-remote}"
mkdir -p "$ROOT"

# From bootstrap-019.sh
mkdir -p "$ROOT/remoteapp"
cat > "$ROOT/remoteapp/google.go" <<'__SRT_019_EOF__'
package remoteapp

import (
	"bufio"
	"crypto/tls"
	"encoding/binary"
	"errors"
	"fmt"
	"io"
	"net"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"google.golang.org/protobuf/proto"
	gp "smarttvremote/remoteapp/internal/googleproto"
)

const googleFeatures int32 = 1 | 2 | 4 | 32 | 64 | 512 // ping, key, IME, power, volume, app link

type GoogleTVClient struct {
	mu          sync.RWMutex
	writeMu     sync.Mutex
	conn        *tls.Conn
	reader      *bufio.Reader
	connected   bool
	sessionOpen bool
	closing     bool
	ip          string
	storageDir  string
	cert        *tls.Certificate
	pair        *googlePairSession
	pairing     bool
	readyCh     chan struct{}
	readyOnce   *sync.Once
	connectErr  chan error
	stopCh      chan struct{}

	imeCounter        int32
	fieldCounter      int32
	currentApp        string
	modelName         string
	vendor            string
	supportedFeatures int32
	lastMove          time.Time
	lastMoveKey       int32

	OnLog    func(string)
	OnStatus func(string, string)
	OnDevice func(model, vendor, currentApp string)
}

func NewGoogleTVClient(storageDir string) *GoogleTVClient {
	return &GoogleTVClient{storageDir: storageDir}
}

func (c *GoogleTVClient) log(message string) {
	if c.OnLog != nil {
		c.OnLog(message)
	}
}

func (c *GoogleTVClient) status(status, message string) {
	if c.OnStatus != nil {
		c.OnStatus(status, message)
	}
}

func (c *GoogleTVClient) IsConnected() bool {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.connected && c.sessionOpen && c.conn != nil
}

func (c *GoogleTVClient) IsPairing() bool {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.pairing && c.pair != nil
}

func (c *GoogleTVClient) Port() int {
	c.mu.RLock()
	defer c.mu.RUnlock()
	if c.sessionOpen && c.conn != nil {
		return 6466
	}
	if c.pairing && c.pair != nil {
		return 6467
	}
	return 0
}

func (c *GoogleTVClient) certificatePaths() (string, string) {
	return filepath.Join(c.storageDir, "google-tv-client-cert.pem"), filepath.Join(c.storageDir, "google-tv-client-key.pem")
}

// HasCertificate only reports whether key material exists. Use
// HasPairedCertificate when deciding whether the TV should accept it.
func (c *GoogleTVClient) HasCertificate() bool {
	certPath, keyPath := c.certificatePaths()
	if _, err := os.Stat(certPath); err != nil {
		return false
	}
	if _, err := os.Stat(keyPath); err != nil {
		return false
	}
	return true
}

func (c *GoogleTVClient) BeginPairing(ip string) error {
	c.Close()
	cert, err := c.ensureCertificate()
	if err != nil {
		return err
	}
	c.clearPairingMarker()
	c.status("pairing", "На Thomson з'явиться 6-символьний код. Введи його в програмі.")
	c.log("Починаю сполучення Google TV через порт 6467.")
	session, err := dialGooglePairing(ip, cert)
	if err != nil {
		return fmt.Errorf("Google TV не відкрив сполучення: %w", err)
	}
	if err := session.start(); err != nil {
		session.close()
		return fmt.Errorf("Google TV не почав сполучення: %w", err)
	}
	c.mu.Lock()
	c.ip = ip
	c.pair = session
	c.pairing = true
	c.closing = false
	c.mu.Unlock()
	c.status("awaiting-code", "Введи код, який зараз показано на екрані Thomson.")
	c.log("TV очікує код сполучення.")
	return nil
}

func normalizePairCode(code string) string {
	code = strings.ToUpper(strings.TrimSpace(code))
	replacer := strings.NewReplacer(" ", "", "-", "", "_", "")
	return replacer.Replace(code)
}

func retryableGooglePairingConnectError(err error) bool {
	if err == nil {
		return false
	}
	text := strings.ToLower(err.Error())
	return strings.Contains(text, "unknown certificate") ||
		strings.Contains(text, "certificate") ||
		strings.Contains(text, "handshake") ||
		strings.Contains(text, "connection reset") ||
		strings.Contains(text, "eof") ||
		strings.Contains(text, "refused") ||
		strings.Contains(text, "timeout")
}

func (c *GoogleTVClient) CompletePairing(code string) error {
	code = normalizePairCode(code)
	if len(code) != 6 {
		return errors.New("код Google TV має містити 6 символів")
	}
	c.mu.RLock()
	session := c.pair
	ip := c.ip
	c.mu.RUnlock()
	if session == nil {
		return errors.New("сполучення не розпочато")
	}
	if err := session.finish(code); err != nil {
		return fmt.Errorf("код не прийнято телевізором: %w", err)
	}
	session.close()
	c.mu.Lock()
	c.pair = nil
	c.pairing = false
	c.mu.Unlock()
	c.log("Код Google TV прийнято. Чекаю, поки TV збереже сертифікат…")

	var lastErr error
	for attempt := 1; attempt <= 6; attempt++ {
		delay := time.Duration(350+attempt*250) * time.Millisecond
		time.Sleep(delay)
		if err := c.Connect(ip); err == nil {
			if err := c.markPaired(ip); err != nil {
				c.log("TV підключено, але не вдалося зберегти локальну позначку сполучення: " + err.Error())
			}
			c.log("Google TV успішно сполучено. Наступного разу код зазвичай не потрібен.")
			return nil
		} else {
			lastErr = err
			c.log(fmt.Sprintf("Перевірка сполучення %d/6: %v", attempt, err))
			if !retryableGooglePairingConnectError(err) {
				break
			}
		}
	}
	c.clearPairingMarker()
	return fmt.Errorf("TV прийняв код, але не активував сертифікат. Натисни «Підключити» ще раз і введи новий код: %w", lastErr)
}

func (c *GoogleTVClient) Connect(ip string) error {
	c.Close()
	cert, err := c.ensureCertificate()
	if err != nil {
		return err
	}
	c.status("connecting", fmt.Sprintf("Підключення до Google TV %s:6466…", ip))
	dialer := &net.Dialer{Timeout: 7 * time.Second}
	conn, err := tls.DialWithDialer(dialer, "tcp", net.JoinHostPort(ip, "6466"), &tls.Config{
		Certificates:       []tls.Certificate{*cert},
		InsecureSkipVerify: true,
		MinVersion:         tls.VersionTLS12,
	})
	if err != nil {
		return fmt.Errorf("Google TV не прийняв збережене сполучення: %w", err)
	}
	readyCh := make(chan struct{})
	connectErr := make(chan error, 1)
	stopCh := make(chan struct{})
	c.mu.Lock()
	c.conn = conn
	c.reader = bufio.NewReaderSize(conn, 16*1024)
	c.connected = false
	c.sessionOpen = true
	c.closing = false
	c.ip = ip
	c.readyCh = readyCh
	c.readyOnce = &sync.Once{}
	c.connectErr = connectErr
	c.stopCh = stopCh
	c.mu.Unlock()
	go c.readLoop()
	if err := c.sendConfiguration(); err != nil {
		c.Close()
		return err
	}
	select {
	case <-readyCh:
		if err := c.markPaired(ip); err != nil {
			c.log("Не вдалося оновити локальну позначку сполучення: " + err.Error())
		}
		c.status("connected", "Підключено до Thomson / Google TV")
		c.log("Google TV Remote Service підключено через порт 6466.")
		return nil
	case err := <-connectErr:
		c.Close()
		return fmt.Errorf("Google TV закрив підключення: %w", err)
	case <-time.After(6 * time.Second):
		c.Close()
		return errors.New("Google TV не підтвердив сполучення. Потрібно ввести код з екрана TV")
	}
}

func (c *GoogleTVClient) markReady() {
	c.mu.Lock()
	c.connected = true
	once := c.readyOnce
	ch := c.readyCh
	c.mu.Unlock()
	if once != nil && ch != nil {
		once.Do(func() { close(ch) })
	}
}

func (c *GoogleTVClient) notifyConnectError(err error) {
	c.mu.RLock()
	ch := c.connectErr
	ready := c.connected
	c.mu.RUnlock()
	if ready || ch == nil || err == nil {
		return
	}
	select {
	case ch <- err:
	default:
	}
}

func (c *GoogleTVClient) readLoop() {
	for {
		c.mu.RLock()
		reader := c.reader
		stopCh := c.stopCh
		c.mu.RUnlock()
__SRT_019_EOF__
