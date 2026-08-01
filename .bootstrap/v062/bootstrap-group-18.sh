#!/usr/bin/env bash
set -euo pipefail
ROOT="${1:?missing output root}"

python3 - "$ROOT" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1])

# Bump the test build version.
replacements = {
    root / "remoteapp/app.go": [("appVersion      = \"0.6.2\"", "appVersion      = \"0.6.3\"")],
    root / "android/app/build.gradle": [
        ("versionCode 8", "versionCode 9"),
        ("versionName \"0.6.2\"", "versionName \"0.6.3\""),
    ],
    root / "android/app/src/main/java/com/paul/smarttvremote/MainActivity.java": [
        ("SmartTVRemote/0.6.2", "SmartTVRemote/0.6.3")
    ],
    root / "README.md": [("# Smart TV Remote 0.6.2", "# Smart TV Remote 0.6.3")],
}
for path, pairs in replacements.items():
    source = path.read_text(encoding="utf-8")
    for old, new in pairs:
        if old not in source:
            raise SystemExit(f"missing version marker in {path}: {old!r}")
        source = source.replace(old, new, 1)
    path.write_text(source, encoding="utf-8")

readme_path = root / "README.md"
readme = readme_path.read_text(encoding="utf-8")
marker = "## Fixes in 0.6.2\n"
section = """## Fixes in 0.6.3

- Fixed oversized inline Netflix and PlayStation logos in the mobile layout.
- Reworked the Google TV Remote Service v2 startup sequence to wait for the TV configuration, negotiate only supported features, answer the active-feature request, and report a connection only after `remote_start`.
- Removed the premature client configuration packet that could make Thomson / Google TV accept the pairing code and then immediately close port 6466.
- Added protocol regression tests for feature negotiation, configuration identity and readiness.

"""
if marker not in readme:
    raise SystemExit("README fixes marker missing")
readme = readme.replace(marker, section + marker, 1)
readme_path.write_text(readme, encoding="utf-8")

# Inline SVGs have browser defaults of 300x150 unless explicitly sized.
html_path = root / "remoteapp/web/index.html"
html = html_path.read_text(encoding="utf-8")
old = """    .icon-button {
      position: relative;
      display: grid;
      place-items: center;
      min-width: 0;
      height: 54px;
      padding: 0;
"""
new = """    .icon-button {
      position: relative;
      display: grid;
      place-items: center;
      min-width: 0;
      height: 54px;
      padding: 0;
      overflow: hidden;
"""
if old not in html:
    raise SystemExit("icon button CSS marker missing")
html = html.replace(old, new, 1)
old = """    .netflix-logo { width: 27px; height: 46px; }
    .playstation-logo { width: 53px; height: 42px; }
"""
new = """    .netflix-logo, .netflix-logo-inline {
      display: block;
      width: 27px;
      height: 46px;
      max-width: 34%;
      max-height: 72%;
      flex: 0 0 auto;
      pointer-events: none;
    }
    .playstation-logo, .playstation-logo-inline {
      display: block;
      width: 53px;
      height: 38px;
      max-width: 58%;
      max-height: 62%;
      flex: 0 0 auto;
      pointer-events: none;
    }
"""
if old not in html:
    raise SystemExit("logo CSS marker missing")
html = html.replace(old, new, 1)
html_path.write_text(html, encoding="utf-8")

# Match the established Android TV Remote Service v2 startup order.
google_path = root / "remoteapp/google.go"
google = google_path.read_text(encoding="utf-8")
old = """\tsupportedFeatures int32
\tlastMove          time.Time
"""
new = """\tsupportedFeatures int32
\tactiveFeatures    int32
\tlastMove          time.Time
"""
if old not in google:
    raise SystemExit("GoogleTVClient feature fields marker missing")
google = google.replace(old, new, 1)

old = """\tc.connectErr = connectErr
\tc.stopCh = stopCh
\tc.mu.Unlock()
\tgo c.readLoop()
\tif err := c.sendConfiguration(); err != nil {
\t\tc.Close()
\t\treturn err
\t}
\tselect {
"""
new = """\tc.connectErr = connectErr
\tc.stopCh = stopCh
\tc.supportedFeatures = 0
\tc.activeFeatures = googleFeatures
\tc.mu.Unlock()
\t// Android TV Remote Service sends RemoteConfigure first. Sending our own
\t// configuration before that server message is rejected by stricter Thomson
\t// firmware and can make port 6466 close immediately after pairing.
\tgo c.readLoop()
\tselect {
"""
if old not in google:
    raise SystemExit("Connect startup marker missing")
google = google.replace(old, new, 1)
google = google.replace("case <-time.After(6 * time.Second):", "case <-time.After(10 * time.Second):", 1)
google = google.replace(
    "return errors.New(\"Google TV не підтвердив сполучення. Потрібно ввести код з екрана TV\")",
    "return errors.New(\"Google TV не завершив запуск Remote Service після сполучення\")",
    1,
)

old = """func (c *GoogleTVClient) handleMessage(msg *gp.RemoteMessage) {
\tswitch {
\tcase msg.RemoteConfigure != nil:
\t\tinfo := msg.RemoteConfigure.DeviceInfo
\t\tc.mu.Lock()
\t\tc.supportedFeatures = msg.RemoteConfigure.Code1
\t\tif info != nil {
\t\t\tc.modelName = info.Model
\t\t\tc.vendor = info.Vendor
\t\t}
\t\tmodel, vendor, app := c.modelName, c.vendor, c.currentApp
\t\tc.mu.Unlock()
\t\tif c.OnDevice != nil {
\t\t\tc.OnDevice(model, vendor, app)
\t\t}
\t\t_ = c.sendConfiguration()
\t\tc.markReady()
\tcase msg.RemoteSetActive != nil:
\t\t_ = c.writeMessage(&gp.RemoteMessage{RemoteSetActive: &gp.RemoteSetActive{Active: googleFeatures}})
\t\tc.markReady()
\tcase msg.RemotePingRequest != nil:
"""
new = """func negotiatedGoogleFeatures(supported int32) int32 {
\treturn googleFeatures & supported
}

func googleConfigurationMessage(features int32) *gp.RemoteMessage {
\treturn &gp.RemoteMessage{RemoteConfigure: &gp.RemoteConfigure{
\t\tCode1: features,
\t\tDeviceInfo: &gp.RemoteDeviceInfo{
\t\t\tUnknown1:    1,
\t\t\tUnknown2:    \"1\",
\t\t\tPackageName: \"atvremote\",
\t\t\tAppVersion:  \"1.0.0\",
\t\t},
\t}}
}

func (c *GoogleTVClient) handleMessage(msg *gp.RemoteMessage) {
\tswitch {
\tcase msg.RemoteConfigure != nil:
\t\tinfo := msg.RemoteConfigure.DeviceInfo
\t\tsupported := msg.RemoteConfigure.Code1
\t\tactive := negotiatedGoogleFeatures(supported)
\t\tc.mu.Lock()
\t\tc.supportedFeatures = supported
\t\tc.activeFeatures = active
\t\tif info != nil {
\t\t\tc.modelName = info.Model
\t\t\tc.vendor = info.Vendor
\t\t}
\t\tmodel, vendor, app := c.modelName, c.vendor, c.currentApp
\t\tc.mu.Unlock()
\t\tif c.OnDevice != nil {
\t\t\tc.OnDevice(model, vendor, app)
\t\t}
\t\tc.log(fmt.Sprintf(\"Google TV підтримує features=%d; активую features=%d.\", supported, active))
\t\tif err := c.sendConfiguration(active); err != nil {
\t\t\tc.notifyConnectError(err)
\t\t}
\tcase msg.RemoteSetActive != nil:
\t\tc.mu.RLock()
\t\tactive := c.activeFeatures
\t\tc.mu.RUnlock()
\t\tif err := c.writeMessage(&gp.RemoteMessage{RemoteSetActive: &gp.RemoteSetActive{Active: active}}); err != nil {
\t\t\tc.notifyConnectError(err)
\t\t}
\tcase msg.RemotePingRequest != nil:
"""
if old not in google:
    raise SystemExit("handleMessage prefix marker missing")
google = google.replace(old, new, 1)

old = """\tcase msg.RemoteStart != nil:
\t\tc.markReady()
\tcase msg.RemoteSetVolumeLevel != nil:
\t\tc.markReady()
\t}
}

func (c *GoogleTVClient) sendConfiguration() error {
\treturn c.writeMessage(&gp.RemoteMessage{RemoteConfigure: &gp.RemoteConfigure{
\t\tCode1: googleFeatures,
\t\tDeviceInfo: &gp.RemoteDeviceInfo{
\t\t\tModel:       \"SmartTVRemote\",
\t\t\tVendor:      \"Smart TV Remote\",
\t\t\tUnknown1:    1,
\t\t\tUnknown2:    \"1\",
\t\t\tPackageName: \"com.paul.smarttvremote\",
\t\t\tAppVersion:  appVersion,
\t\t},
\t}})
}
"""
new = """\tcase msg.RemoteStart != nil:
\t\t// RemoteStart is the first packet that proves the service is ready for
\t\t// commands. Configuration and volume packets can arrive earlier.
\t\tc.markReady()
\tcase msg.RemoteSetVolumeLevel != nil:
\t\t// Keep the connection open; volume information alone is not readiness.
\t}
}

func (c *GoogleTVClient) sendConfiguration(features int32) error {
\treturn c.writeMessage(googleConfigurationMessage(features))
}
"""
if old not in google:
    raise SystemExit("handleMessage suffix / sendConfiguration marker missing")
google = google.replace(old, new, 1)
google_path.write_text(google, encoding="utf-8")

# Regression tests do not require a real TV or network socket.
test_path = root / "remoteapp/google_protocol_test.go"
test_path.write_text(
    '''package remoteapp

import (
\t"testing"

\tgp "smarttvremote/remoteapp/internal/googleproto"
)

func TestNegotiatedGoogleFeaturesUseOnlyTVSupportedBits(t *testing.T) {
\tt.Parallel()
\tsupported := int32(1 | 2 | 32 | 64)
\tif got := negotiatedGoogleFeatures(supported); got != supported {
\t\tt.Fatalf("negotiated features = %d, want %d", got, supported)
\t}
\tif got := negotiatedGoogleFeatures(2); got != 2 {
\t\tt.Fatalf("key-only negotiation = %d, want 2", got)
\t}
}

func TestGoogleConfigurationUsesCompatibleRemoteIdentity(t *testing.T) {
\tt.Parallel()
\tmessage := googleConfigurationMessage(3)
\tconfigure := message.RemoteConfigure
\tif configure == nil || configure.Code1 != 3 || configure.DeviceInfo == nil {
\t\tt.Fatalf("unexpected configuration: %#v", message)
\t}
\tif configure.DeviceInfo.PackageName != "atvremote" || configure.DeviceInfo.AppVersion != "1.0.0" {
\t\tt.Fatalf("unexpected remote identity: %#v", configure.DeviceInfo)
\t}
}

func TestGoogleReadinessRequiresRemoteStart(t *testing.T) {
\tt.Parallel()
\tclient := NewGoogleTVClient(t.TempDir())
\tclient.handleMessage(&gp.RemoteMessage{RemoteConfigure: &gp.RemoteConfigure{Code1: googleFeatures}})
\tif client.connected {
\t\tt.Fatal("RemoteConfigure must not mark the TV ready")
\t}
\tclient.handleMessage(&gp.RemoteMessage{RemoteSetActive: &gp.RemoteSetActive{Active: googleFeatures}})
\tif client.connected {
\t\tt.Fatal("RemoteSetActive must not mark the TV ready")
\t}
\tclient.handleMessage(&gp.RemoteMessage{RemoteStart: &gp.RemoteStart{Started: true}})
\tif !client.connected {
\t\tt.Fatal("RemoteStart should mark the TV ready")
\t}
}
''',
    encoding="utf-8",
)
PY

gofmt -w "$ROOT/remoteapp/google.go" "$ROOT/remoteapp/google_protocol_test.go"

grep -F 'appVersion      = "0.6.3"' "$ROOT/remoteapp/app.go"
grep -F '.netflix-logo, .netflix-logo-inline' "$ROOT/remoteapp/web/index.html"
grep -F 'PackageName: "atvremote"' "$ROOT/remoteapp/google.go"
grep -F 'case msg.RemoteStart != nil:' "$ROOT/remoteapp/google.go"
