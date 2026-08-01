#!/usr/bin/env bash
set -euo pipefail
ROOT="${1:-smart-tv-remote}"
mkdir -p "$ROOT"

# From bootstrap-022.sh
mkdir -p "$ROOT/remoteapp"
cat > "$ROOT/remoteapp/google_certificate.go" <<'__SRT_022_EOF__'
package remoteapp

import (
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/hex"
	"encoding/json"
	"encoding/pem"
	"errors"
	"fmt"
	"math/big"
	"os"
	"path/filepath"
	"strings"
	"time"
)

const (
	googleCertificateCommonName = "Smart TV Remote"
	googlePairingMarkerVersion  = 2
)

type googlePairingMarker struct {
	Version     int    `json:"version"`
	Fingerprint string `json:"fingerprint"`
	LastIP      string `json:"lastIp,omitempty"`
	PairedAt    string `json:"pairedAt"`
}

func (c *GoogleTVClient) pairingMarkerPath() string {
	return filepath.Join(c.storageDir, "google-tv-paired-v2.json")
}

func parsePEMCertificate(path string) (*x509.Certificate, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	block, _ := pem.Decode(data)
	if block == nil || block.Type != "CERTIFICATE" {
		return nil, errors.New("certificate PEM block not found")
	}
	return x509.ParseCertificate(block.Bytes)
}

func googleCertificateFingerprint(cert *x509.Certificate) string {
	sum := sha256.Sum256(cert.Raw)
	return strings.ToLower(hex.EncodeToString(sum[:]))
}

func isCurrentGoogleCertificate(cert *x509.Certificate) bool {
	if cert == nil || !cert.BasicConstraintsValid || !cert.IsCA {
		return false
	}
	if cert.Subject.CommonName != googleCertificateCommonName {
		return false
	}
	if time.Now().After(cert.NotAfter) || time.Now().Add(180*24*time.Hour).After(cert.NotAfter) {
		return false
	}
	for _, name := range cert.DNSNames {
		if name == googleCertificateCommonName {
			return true
		}
	}
	return false
}

func createGoogleTVCertificate(certPath, keyPath string) error {
	privateKey, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		return fmt.Errorf("generate RSA key: %w", err)
	}
	serialLimit := new(big.Int).Lsh(big.NewInt(1), 128)
	serial, err := rand.Int(rand.Reader, serialLimit)
	if err != nil {
		return fmt.Errorf("generate certificate serial: %w", err)
	}
	now := time.Now().UTC()
	name := pkix.Name{CommonName: googleCertificateCommonName}
	template := &x509.Certificate{
		SerialNumber:          serial,
		Subject:               name,
		Issuer:                name,
		NotBefore:             now.Add(-24 * time.Hour),
		NotAfter:              now.AddDate(10, 0, 0),
		DNSNames:              []string{googleCertificateCommonName},
		BasicConstraintsValid: true,
		IsCA:                  true,
		MaxPathLen:            0,
		MaxPathLenZero:        true,
	}
	der, err := x509.CreateCertificate(rand.Reader, template, template, &privateKey.PublicKey, privateKey)
	if err != nil {
		return fmt.Errorf("create certificate: %w", err)
	}
	if err := os.MkdirAll(filepath.Dir(certPath), 0o700); err != nil {
		return err
	}
	certPEM := pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: der})
	keyPEM := pem.EncodeToMemory(&pem.Block{Type: "RSA PRIVATE KEY", Bytes: x509.MarshalPKCS1PrivateKey(privateKey)})
	if err := os.WriteFile(certPath, certPEM, 0o600); err != nil {
		return err
	}
	if err := os.WriteFile(keyPath, keyPEM, 0o600); err != nil {
		_ = os.Remove(certPath)
		return err
	}
	return nil
}

func (c *GoogleTVClient) clearPairingMarker() {
	_ = os.Remove(c.pairingMarkerPath())
}

func (c *GoogleTVClient) resetCertificateFiles() {
	certPath, keyPath := c.certificatePaths()
	_ = os.Remove(certPath)
	_ = os.Remove(keyPath)
	c.clearPairingMarker()
	c.mu.Lock()
	c.cert = nil
	c.mu.Unlock()
}

func (c *GoogleTVClient) ensureCertificate() (*tls.Certificate, error) {
	c.mu.RLock()
	loaded := c.cert
	c.mu.RUnlock()
	if loaded != nil {
		return loaded, nil
	}
	if err := os.MkdirAll(c.storageDir, 0o700); err != nil {
		return nil, err
	}
	certPath, keyPath := c.certificatePaths()
	regenerated := false
	if cert, err := parsePEMCertificate(certPath); err == nil {
		if !isCurrentGoogleCertificate(cert) {
			c.log("Старий сертифікат Google TV несумісний з актуальним протоколом. Створюю новий сертифікат; код з TV потрібно буде ввести один раз.")
			c.resetCertificateFiles()
			regenerated = true
		}
	} else if !errors.Is(err, os.ErrNotExist) {
		c.log("Пошкоджений сертифікат Google TV замінено новим.")
		c.resetCertificateFiles()
		regenerated = true
	}
	if _, err := os.Stat(certPath); errors.Is(err, os.ErrNotExist) {
		if err := createGoogleTVCertificate(certPath, keyPath); err != nil {
			return nil, fmt.Errorf("не вдалося створити сертифікат Google TV: %w", err)
		}
		if !regenerated {
			c.log("Створено локальний сертифікат для сполучення з Google TV.")
		}
	}
	cert, err := tls.LoadX509KeyPair(certPath, keyPath)
	if err != nil {
		return nil, fmt.Errorf("не вдалося прочитати сертифікат Google TV: %w", err)
	}
	leaf, err := parsePEMCertificate(certPath)
	if err != nil {
		return nil, fmt.Errorf("не вдалося перевірити сертифікат Google TV: %w", err)
	}
	cert.Leaf = leaf
	c.mu.Lock()
	c.cert = &cert
	c.mu.Unlock()
	return &cert, nil
}

func (c *GoogleTVClient) markPaired(ip string) error {
	cert, err := c.ensureCertificate()
	if err != nil {
		return err
	}
	leaf := cert.Leaf
	if leaf == nil {
		certPath, _ := c.certificatePaths()
		leaf, err = parsePEMCertificate(certPath)
		if err != nil {
			return err
		}
	}
	marker := googlePairingMarker{
		Version:     googlePairingMarkerVersion,
		Fingerprint: googleCertificateFingerprint(leaf),
		LastIP:      ip,
		PairedAt:    time.Now().UTC().Format(time.RFC3339),
	}
	data, err := json.MarshalIndent(marker, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(c.pairingMarkerPath(), data, 0o600)
}

func (c *GoogleTVClient) HasPairedCertificate() bool {
	certPath, keyPath := c.certificatePaths()
	cert, err := parsePEMCertificate(certPath)
	if err != nil || !isCurrentGoogleCertificate(cert) {
		return false
	}
	if _, err := os.Stat(keyPath); err != nil {
		return false
	}
	data, err := os.ReadFile(c.pairingMarkerPath())
	if err != nil {
		return false
	}
	var marker googlePairingMarker
	if json.Unmarshal(data, &marker) != nil || marker.Version != googlePairingMarkerVersion {
		return false
	}
	return strings.EqualFold(marker.Fingerprint, googleCertificateFingerprint(cert))
}
__SRT_022_EOF__

# From bootstrap-023.sh
mkdir -p "$ROOT/remoteapp"
cat > "$ROOT/remoteapp/google_certificate_test.go" <<'__SRT_023_EOF__'
package remoteapp

import (
	"os"
	"path/filepath"
	"testing"
)

func TestGoogleCertificateRequiresSuccessfulPairingMarker(t *testing.T) {
	t.Parallel()
	client := NewGoogleTVClient(t.TempDir())
	cert, err := client.ensureCertificate()
	if err != nil {
		t.Fatalf("ensureCertificate: %v", err)
	}
	if cert.Leaf == nil || !isCurrentGoogleCertificate(cert.Leaf) {
		t.Fatal("generated certificate is not compatible with current Google TV pairing")
	}
	if client.HasPairedCertificate() {
		t.Fatal("certificate must not be considered paired before a real remote connection succeeds")
	}
	if err := client.markPaired("192.168.0.147"); err != nil {
		t.Fatalf("markPaired: %v", err)
	}
	if !client.HasPairedCertificate() {
		t.Fatal("paired certificate marker was not recognized")
	}
}

func TestResetGoogleCertificateRemovesKeyAndPairingMarker(t *testing.T) {
	t.Parallel()
	client := NewGoogleTVClient(t.TempDir())
	if _, err := client.ensureCertificate(); err != nil {
		t.Fatalf("ensureCertificate: %v", err)
	}
	if err := client.markPaired("192.168.0.147"); err != nil {
		t.Fatalf("markPaired: %v", err)
	}
	certPath, keyPath := client.certificatePaths()
	client.resetCertificateFiles()
	for _, path := range []string{certPath, keyPath, client.pairingMarkerPath()} {
		if _, err := os.Stat(path); !os.IsNotExist(err) {
			t.Fatalf("expected %s to be removed, got %v", filepath.Base(path), err)
		}
	}
}
__SRT_023_EOF__

# From bootstrap-024.sh
mkdir -p "$ROOT/remoteapp"
cat > "$ROOT/remoteapp/google_launch_test.go" <<'__SRT_024_EOF__'
package remoteapp

import (
	"slices"
	"testing"
)

func TestGoogleLaunchPlansContainNativePackagesAndFallbacks(t *testing.T) {
	t.Parallel()
	tests := []struct {
		app      string
		required []string
	}{
		{app: "youtube", required: []string{"com.google.android.youtube.tv", "https://www.youtube.com"}},
		{app: "netflix", required: []string{"com.netflix.ninja", "nflx://www.netflix.com/browse"}},
		{app: "browser", required: []string{"com.internet.tvbrowser", "https://www.google.com"}},
	}
	for _, test := range tests {
		t.Run(test.app, func(t *testing.T) {
			plan, err := googlePlan(test.app)
			if err != nil {
				t.Fatalf("googlePlan: %v", err)
			}
			for _, value := range test.required {
				if !slices.Contains(plan.Links, value) {
					t.Fatalf("launch plan for %s does not contain %q: %#v", test.app, value, plan.Links)
				}
			}
		})
	}
}

func TestNormalizeGooglePairCode(t *testing.T) {
	t.Parallel()
	if got := normalizePairCode(" a1-b2 c3 "); got != "A1B2C3" {
		t.Fatalf("normalizePairCode = %q", got)
	}
}
__SRT_024_EOF__
