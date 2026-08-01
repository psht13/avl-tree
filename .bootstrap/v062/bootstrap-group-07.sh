#!/usr/bin/env bash
set -euo pipefail
ROOT="${1:-smart-tv-remote}"
mkdir -p "$ROOT"

# From bootstrap-025.sh
mkdir -p "$ROOT/remoteapp"
cat > "$ROOT/remoteapp/google_pairing.go" <<'__SRT_025_EOF__'
package remoteapp

import (
	"bufio"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/tls"
	"crypto/x509"
	"encoding/binary"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"net"
	"strings"
	"time"

	apb "github.com/drosocode/atvremote/pkg/v2/proto"
	"google.golang.org/protobuf/proto"
)

type googlePairSession struct {
	conn   *tls.Conn
	reader *bufio.Reader
	cert   *tls.Certificate
}

func newPairingMessage() *apb.PairingMessage {
	return &apb.PairingMessage{
		Status:          apb.PairingMessage_STATUS_OK,
		ProtocolVersion: 2,
	}
}

func dialGooglePairing(ip string, cert *tls.Certificate) (*googlePairSession, error) {
	dialer := &net.Dialer{Timeout: 8 * time.Second}
	conn, err := tls.DialWithDialer(dialer, "tcp", net.JoinHostPort(ip, "6467"), &tls.Config{
		Certificates:       []tls.Certificate{*cert},
		InsecureSkipVerify: true,
		MinVersion:         tls.VersionTLS12,
	})
	if err != nil {
		return nil, fmt.Errorf("pairing TLS: %w", err)
	}
	_ = conn.SetDeadline(time.Now().Add(15 * time.Second))
	return &googlePairSession{conn: conn, reader: bufio.NewReaderSize(conn, 4096), cert: cert}, nil
}

func (p *googlePairSession) close() {
	if p != nil && p.conn != nil {
		_ = p.conn.Close()
	}
}

func (p *googlePairSession) writeMessage(message *apb.PairingMessage) error {
	raw, err := proto.Marshal(message)
	if err != nil {
		return err
	}
	var prefix [binary.MaxVarintLen64]byte
	n := binary.PutUvarint(prefix[:], uint64(len(raw)))
	if _, err := p.conn.Write(prefix[:n]); err != nil {
		return err
	}
	_, err = p.conn.Write(raw)
	return err
}

func (p *googlePairSession) readMessage() (*apb.PairingMessage, error) {
	length, err := binary.ReadUvarint(p.reader)
	if err != nil {
		return nil, err
	}
	if length == 0 || length > 1<<20 {
		return nil, errors.New("Google TV повернув некоректний pairing-пакет")
	}
	raw := make([]byte, int(length))
	if _, err := io.ReadFull(p.reader, raw); err != nil {
		return nil, err
	}
	var message apb.PairingMessage
	if err := proto.Unmarshal(raw, &message); err != nil {
		return nil, err
	}
	if message.Status != apb.PairingMessage_STATUS_OK {
		return nil, fmt.Errorf("Google TV відхилив pairing-повідомлення: status=%s", message.Status.String())
	}
	return &message, nil
}

func (p *googlePairSession) start() error {
	request := newPairingMessage()
	request.PairingRequest = &apb.PairingRequest{
		ServiceName: "atvremote",
		ClientName:  googleCertificateCommonName,
	}
	if err := p.writeMessage(request); err != nil {
		return fmt.Errorf("pairing request: %w", err)
	}
	if _, err := p.readMessage(); err != nil {
		return fmt.Errorf("pairing request acknowledgement: %w", err)
	}

	options := newPairingMessage()
	options.PairingOption = &apb.PairingOption{
		PreferredRole: apb.RoleType_ROLE_TYPE_INPUT,
		InputEncodings: []*apb.PairingEncoding{{
			Type:         apb.PairingEncoding_ENCODING_TYPE_HEXADECIMAL,
			SymbolLength: 6,
		}},
	}
	if err := p.writeMessage(options); err != nil {
		return fmt.Errorf("pairing options: %w", err)
	}
	if _, err := p.readMessage(); err != nil {
		return fmt.Errorf("pairing options acknowledgement: %w", err)
	}

	configuration := newPairingMessage()
	configuration.PairingConfiguration = &apb.PairingConfiguration{
		ClientRole: apb.RoleType_ROLE_TYPE_INPUT,
		Encoding: &apb.PairingEncoding{
			Type:         apb.PairingEncoding_ENCODING_TYPE_HEXADECIMAL,
			SymbolLength: 6,
		},
	}
	if err := p.writeMessage(configuration); err != nil {
		return fmt.Errorf("pairing configuration: %w", err)
	}
	if _, err := p.readMessage(); err != nil {
		return fmt.Errorf("pairing configuration acknowledgement: %w", err)
	}
	_ = p.conn.SetDeadline(time.Time{})
	return nil
}

func publicKeyParts(cert *x509.Certificate) (*rsa.PublicKey, error) {
	key, ok := cert.PublicKey.(*rsa.PublicKey)
	if !ok {
		return nil, errors.New("Google TV pairing expects an RSA certificate")
	}
	return key, nil
}

func pairingSecret(clientCert, serverCert *x509.Certificate, code string) ([]byte, error) {
	code = normalizePairCode(code)
	if len(code) != 6 {
		return nil, errors.New("код Google TV має містити рівно 6 символів")
	}
	if _, err := hex.DecodeString(code); err != nil {
		return nil, errors.New("код Google TV має містити лише цифри 0-9 та літери A-F")
	}
	clientKey, err := publicKeyParts(clientCert)
	if err != nil {
		return nil, err
	}
	serverKey, err := publicKeyParts(serverCert)
	if err != nil {
		return nil, err
	}
	hash := sha256.New()
	hash.Write(clientKey.N.Bytes())
	hash.Write([]byte{1, 0, 1})
	hash.Write(serverKey.N.Bytes())
	hash.Write([]byte{1, 0, 1})
	lastFour, _ := hex.DecodeString(code[2:])
	hash.Write(lastFour)
	secret := hash.Sum(nil)
	prefix, _ := hex.DecodeString(code[:2])
	if len(prefix) != 1 || secret[0] != prefix[0] {
		return nil, errors.New("код не збігається з цим телевізором; перевір усі 6 символів")
	}
	return secret, nil
}

func (p *googlePairSession) finish(code string) error {
	if p == nil || p.conn == nil {
		return errors.New("сполучення Google TV не розпочато")
	}
	clientCert := p.cert.Leaf
	if clientCert == nil {
		parsed, err := x509.ParseCertificate(p.cert.Certificate[0])
		if err != nil {
			return err
		}
		clientCert = parsed
	}
	state := p.conn.ConnectionState()
	if len(state.PeerCertificates) == 0 {
		return errors.New("Google TV не надіслав pairing-сертифікат")
	}
	secret, err := pairingSecret(clientCert, state.PeerCertificates[0], strings.ToUpper(code))
	if err != nil {
		return err
	}
	message := newPairingMessage()
	message.PairingSecret = &apb.PairingSecret{Secret: secret}
	_ = p.conn.SetDeadline(time.Now().Add(12 * time.Second))
	if err := p.writeMessage(message); err != nil {
		return fmt.Errorf("надсилання pairing secret: %w", err)
	}
	if _, err := p.readMessage(); err != nil {
		return fmt.Errorf("TV не підтвердив код: %w", err)
	}
	return nil
}
__SRT_025_EOF__

# From bootstrap-026.sh
mkdir -p "$ROOT/remoteapp"
cat > "$ROOT/remoteapp/launch.go" <<'__SRT_026_EOF__'
package remoteapp

// LaunchResult describes whether the launch command was only sent or was also
// confirmed by the television. Some firmware versions do not expose active-app
// state, so a successful command can legitimately be unconfirmed.
type LaunchResult struct {
	Confirmed bool     `json:"confirmed"`
	Message   string   `json:"message"`
	AppID     string   `json:"appId,omitempty"`
	Attempts  []string `json:"attempts,omitempty"`
}
__SRT_026_EOF__

# From bootstrap-027.sh
mkdir -p "$ROOT/remoteapp"
cat > "$ROOT/remoteapp/samsung.go" <<'__SRT_027_EOF__'
package remoteapp

import (
	"bufio"
	"crypto/rand"
	"crypto/sha1"
	"crypto/tls"
	"encoding/base64"
	"encoding/binary"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"time"
)

type SamsungClient struct {
	mu          sync.RWMutex
	writeMu     sync.Mutex
	appListMu   sync.Mutex
	conn        net.Conn
	reader      *bufio.Reader
	ip          string
	port        int
	connected   bool
	closing     bool
	OnLog       func(string)
	OnStatus    func(string, string)
	OnToken     func(string, int)
	appListWait chan []SamsungInstalledApp
}

func NewSamsungClient() *SamsungClient { return &SamsungClient{} }

func (c *SamsungClient) log(message string) {
	if c.OnLog != nil {
		c.OnLog(message)
	}
}

func (c *SamsungClient) status(status, message string) {
	if c.OnStatus != nil {
		c.OnStatus(status, message)
	}
}

func (c *SamsungClient) IsConnected() bool {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.connected && c.conn != nil
}

func (c *SamsungClient) Port() int {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.port
}

func (c *SamsungClient) Connect(ip, token string, ports []int) error {
	c.Close()
	var lastErr error
	for _, port := range ports {
		if err := c.connectPort(ip, token, port); err != nil {
			lastErr = err
			c.log(fmt.Sprintf("Порт %d: %v", port, err))
			c.Close()
			continue
		}
		return nil
	}
	if lastErr == nil {
		lastErr = errors.New("не задано порт підключення")
	}
	return lastErr
}

func (c *SamsungClient) connectPort(ip, token string, port int) error {
	c.status("connecting", fmt.Sprintf("Підключення до %s:%d…", ip, port))
	c.log(fmt.Sprintf("Пробую %s на порту %d.", map[bool]string{true: "WSS", false: "WS"}[port == 8002], port))

	dialer := &net.Dialer{Timeout: 8 * time.Second}
	var conn net.Conn
	var err error
	if port == 8002 {
		conn, err = tls.DialWithDialer(dialer, "tcp", net.JoinHostPort(ip, fmt.Sprint(port)), &tls.Config{
			InsecureSkipVerify: true, // TV uses a local self-signed certificate.
			MinVersion:         tls.VersionTLS12,
			ServerName:         ip,
		})
	} else {
		conn, err = dialer.Dial("tcp", net.JoinHostPort(ip, fmt.Sprint(port)))
	}
	if err != nil {
		return fmt.Errorf("TV не відповів: %w", err)
	}

	reader, err := performWebSocketHandshake(conn, ip, port, token)
	if err != nil {
		_ = conn.Close()
		return err
	}

	c.mu.Lock()
	c.conn = conn
	c.reader = reader
	c.ip = ip
	c.port = port
	c.connected = false
	c.closing = false
	c.mu.Unlock()

	auth := make(chan error, 1)
	go c.readLoop(auth)
	c.status("awaiting-approval", "Підтвердь доступ на екрані телевізора, якщо з’явився запит.")

	select {
	case err := <-auth:
		if err != nil {
			return err
		}
		c.mu.Lock()
		c.connected = true
		c.mu.Unlock()
		c.status("connected", fmt.Sprintf("Підключено через порт %d", port))
		c.log("Підключення успішне.")
		return nil
	case <-time.After(45 * time.Second):
		return errors.New("час очікування дозволу на TV вичерпано")
	}
}

func performWebSocketHandshake(conn net.Conn, ip string, port int, token string) (*bufio.Reader, error) {
	keyBytes := make([]byte, 16)
	if _, err := rand.Read(keyBytes); err != nil {
		return nil, err
	}
	key := base64.StdEncoding.EncodeToString(keyBytes)
	app := base64.StdEncoding.EncodeToString([]byte(appName))
	query := url.Values{}
	query.Set("name", app)
	if token != "" {
		query.Set("token", token)
	}
	path := "/api/v2/channels/samsung.remote.control?" + query.Encode()
	request := fmt.Sprintf(
		"GET %s HTTP/1.1\r\nHost: %s:%d\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: %s\r\nSec-WebSocket-Version: 13\r\n\r\n",
		path, ip, port, key,
	)
	if _, err := io.WriteString(conn, request); err != nil {
		return nil, err
	}

	reader := bufio.NewReader(conn)
	response, err := http.ReadResponse(reader, &http.Request{Method: http.MethodGet})
	if err != nil {
		return nil, fmt.Errorf("помилка WebSocket handshake: %w", err)
	}
	if response.StatusCode != http.StatusSwitchingProtocols {
		_ = response.Body.Close()
		return nil, fmt.Errorf("TV не прийняв WebSocket handshake: %s", response.Status)
	}
	// Do not close response.Body after HTTP 101. On some Go versions it owns
	// the upgraded socket and closing it would terminate the WebSocket.

	accept := response.Header.Get("Sec-WebSocket-Accept")
	h := sha1.Sum([]byte(key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"))
	expected := base64.StdEncoding.EncodeToString(h[:])
	if accept != "" && accept != expected {
		return nil, errors.New("TV повернув некоректний WebSocket accept")
	}
	return reader, nil
}

func (c *SamsungClient) readLoop(auth chan<- error) {
	var fragmented []byte
	var fragmentedOpcode byte
	for {
		opcode, fin, payload, err := c.readFrame()
		if err != nil {
			if !c.isClosing() {
				c.log("З'єднання закрито: " + err.Error())
				c.status("disconnected", "З'єднання з TV втрачено")
			}
			c.mu.Lock()
			c.connected = false
			c.mu.Unlock()
			select {
			case auth <- err:
			default:
			}
			return
		}

		switch opcode {
		case 0x0:
			fragmented = append(fragmented, payload...)
			if fin {
				if fragmentedOpcode == 0x1 {
					c.handleMessage(fragmented, auth)
				}
				fragmented = nil
				fragmentedOpcode = 0
			}
		case 0x1:
			if fin {
				c.handleMessage(payload, auth)
			} else {
				fragmentedOpcode = opcode
				fragmented = append(fragmented[:0], payload...)
			}
		case 0x8:
			select {
			case auth <- errors.New("TV закрив WebSocket"):
			default:
			}
			return
		case 0x9:
			_ = c.writeFrame(0xA, payload)
		}
	}
}

func (c *SamsungClient) handleMessage(payload []byte, auth chan<- error) {
	var envelope struct {
		Event string          `json:"event"`
		Data  json.RawMessage `json:"data"`
	}
	if err := json.Unmarshal(payload, &envelope); err != nil {
		return
	}
	switch envelope.Event {
	case "ms.channel.connect":
		var data struct {
			Token string `json:"token"`
		}
		_ = json.Unmarshal(envelope.Data, &data)
		if data.Token != "" && c.OnToken != nil {
			c.OnToken(data.Token, c.Port())
		}
		select {
		case auth <- nil:
		default:
		}
	case "ms.channel.unauthorized":
		select {
		case auth <- errors.New("телевізор відхилив доступ"):
		default:
		}
	case "ed.installedApp.get":
		apps := parseSamsungInstalledApps(envelope.Data)
		c.deliverInstalledApps(apps)
	}
}

func (c *SamsungClient) readFrame() (opcode byte, fin bool, payload []byte, err error) {
	c.mu.RLock()
	reader := c.reader
	c.mu.RUnlock()
	if reader == nil {
		return 0, false, nil, io.EOF
	}
	header := make([]byte, 2)
	if _, err = io.ReadFull(reader, header); err != nil {
		return
	}
	fin = header[0]&0x80 != 0
	opcode = header[0] & 0x0F
	masked := header[1]&0x80 != 0
	length := uint64(header[1] & 0x7F)
	if length == 126 {
		var ext [2]byte
		if _, err = io.ReadFull(reader, ext[:]); err != nil {
			return
		}
		length = uint64(binary.BigEndian.Uint16(ext[:]))
	} else if length == 127 {
		var ext [8]byte
		if _, err = io.ReadFull(reader, ext[:]); err != nil {
			return
		}
		length = binary.BigEndian.Uint64(ext[:])
	}
	if length > 16*1024*1024 {
		err = errors.New("WebSocket frame занадто великий")
		return
	}
	var mask [4]byte
	if masked {
		if _, err = io.ReadFull(reader, mask[:]); err != nil {
			return
		}
	}
__SRT_027_EOF__
