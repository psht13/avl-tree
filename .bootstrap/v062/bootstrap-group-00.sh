#!/usr/bin/env bash
set -euo pipefail
ROOT="${1:-smart-tv-remote}"
mkdir -p "$ROOT"

# From bootstrap-000.sh
cat > "$ROOT/LICENSE" <<'__SRT_000_EOF__'
MIT License

Copyright (c) 2026 Pavlo Yurchenko

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
__SRT_000_EOF__

# From bootstrap-001.sh
cat > "$ROOT/README.md" <<'__SRT_001_EOF__'
# Smart TV Remote 0.6.2

Local Wi-Fi remote for:

- Samsung Smart TV / Tizen, including Samsung browser pointer commands when supported.
- Thomson and other Google TV / Android TV devices through Android TV Remote Service v2.

The Android app and Windows tester use the same local controller and responsive interface. No companion app is installed on the television.

## Fixes in 0.6.2

- Google TV controls are enabled only after the TV accepts the client certificate on remote port 6466. A generated PEM file is no longer treated as a completed pairing.
- Certificates created by 0.6.0 and 0.6.1 are automatically replaced with a certificate compatible with the current Google TV pairing flow. The TV code must be entered once after upgrading.
- Pairing state is stored only after a real remote session succeeds, which prevents the false `Certificate saved` state shown by previous builds.
- Samsung YouTube, Netflix and Internet launch buttons now request the installed application list, choose the TV-specific app ID and launch type, try WebSocket and REST launch paths, use known fallback IDs and verify the active app when the firmware exposes its state.
- Google TV application launch uses package names, app links and browser fallbacks.
- The UI reports `opened` only after confirmation. Otherwise it shows that launch attempts were sent instead of claiming success.
- Android builds now use a stable test signing key so future 0.6.x test updates can be installed over 0.6.2.

## Google TV first connection after upgrading

1. Uninstall an older test APK if Android reports a signature conflict.
2. Install 0.6.2.
3. Choose `Thomson / Google TV`.
4. Enter the TV IP or use network discovery.
5. Press Connect.
6. Enter the 6-character hexadecimal pairing code displayed by the TV.
7. Wait until the status says that port 6466 is connected. Only then do the remote buttons become active.

The code is normally needed only once. Google TV Remote Service uses port 6467 for pairing and port 6466 for remote commands.

## Cursor limitation

Samsung Browser can accept pointer messages on compatible Tizen firmware. Google TV does not expose a guaranteed free system pointer through the remote protocol, so its joystick sends throttled D-pad directions and the center sends OK.

## Build

The CI workflow generates Google TV protobuf bindings, runs Go tests and vet, builds a Windows x64 executable, creates an Android AAR through gomobile, assembles a signed debug APK, validates both outputs and packages SHA-256 checksums.
__SRT_001_EOF__

# From bootstrap-002.sh
cat > "$ROOT/THIRD_PARTY_NOTICES.md" <<'__SRT_002_EOF__'
# Third-party notices

This project interoperates with the Android TV Remote Service v2 protocol and uses:

- `github.com/drosocode/atvremote` (MIT License) for Google TV pairing and certificate utilities.
- `google.golang.org/protobuf` (BSD-style license) for protocol messages.
- The `remotemessage.proto` schema from `tronikos/androidtvremote2` (Apache License 2.0), itself based on earlier reverse-engineering work.
- `golang.org/x/mobile` (BSD-style license) at build time for Android bindings.

The Samsung, Thomson, Google TV, YouTube, Netflix and PlayStation names and marks belong to their respective owners. This is an unofficial test application and is not endorsed by those companies.
__SRT_002_EOF__

# From bootstrap-003.sh
mkdir -p "$ROOT/android/app"
cat > "$ROOT/android/app/build.gradle" <<'__SRT_003_EOF__'
plugins {
    id "com.android.application"
}

android {
    namespace "com.paul.smarttvremote"
    compileSdk 35

    defaultConfig {
        applicationId "com.paul.smarttvremote"
        minSdk 23
        targetSdk 35
        versionCode 8
        versionName "0.6.2"
    }

    buildTypes {
        debug {
            minifyEnabled false
        }
        release {
            minifyEnabled false
        }
    }

    compileOptions {
        sourceCompatibility JavaVersion.VERSION_17
        targetCompatibility JavaVersion.VERSION_17
    }
}

dependencies {
    implementation files("libs/mobilebridge.aar")
}
__SRT_003_EOF__

# From bootstrap-004.sh
mkdir -p "$ROOT/android/app/src/main"
cat > "$ROOT/android/app/src/main/AndroidManifest.xml" <<'__SRT_004_EOF__'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
    <uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />
    <uses-permission android:name="android.permission.RECORD_AUDIO" />

    <application
        android:allowBackup="true"
        android:icon="@drawable/ic_launcher"
        android:label="Smart TV Remote"
        android:networkSecurityConfig="@xml/network_security_config"
        android:supportsRtl="true"
        android:theme="@style/AppTheme"
        android:usesCleartextTraffic="true">
        <activity
            android:name=".MainActivity"
            android:configChanges="keyboard|keyboardHidden|orientation|screenSize|smallestScreenSize|uiMode"
            android:exported="true"
            android:screenOrientation="unspecified">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
    </application>
</manifest>
__SRT_004_EOF__

# From bootstrap-005.sh
mkdir -p "$ROOT/android/app/src/main/java/com/paul/smarttvremote"
cat > "$ROOT/android/app/src/main/java/com/paul/smarttvremote/MainActivity.java" <<'__SRT_005_EOF__'
package com.paul.smarttvremote;

import android.Manifest;
import android.app.Activity;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.os.Bundle;
import android.speech.RecognizerIntent;
import android.view.View;
import android.webkit.JavascriptInterface;
import android.webkit.WebChromeClient;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.Toast;

import com.paul.remote.mobilebridge.Mobilebridge;

import java.util.ArrayList;
import java.util.Locale;

public final class MainActivity extends Activity {
    private static final int VOICE_REQUEST = 4106;
    private static final int AUDIO_PERMISSION_REQUEST = 4107;

    private WebView webView;
    private String pendingVoiceLanguage = "uk-UA";

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        getWindow().setStatusBarColor(Color.rgb(5, 11, 19));
        getWindow().setNavigationBarColor(Color.rgb(5, 11, 19));

        webView = new WebView(this);
        webView.setBackgroundColor(Color.rgb(5, 11, 19));
        webView.setSystemUiVisibility(View.SYSTEM_UI_FLAG_LAYOUT_STABLE);
        setContentView(webView);

        WebSettings settings = webView.getSettings();
        settings.setJavaScriptEnabled(true);
        settings.setDomStorageEnabled(true);
        settings.setDatabaseEnabled(true);
        settings.setAllowFileAccess(false);
        settings.setAllowContentAccess(false);
        settings.setMediaPlaybackRequiresUserGesture(false);
        settings.setMixedContentMode(WebSettings.MIXED_CONTENT_ALWAYS_ALLOW);
        settings.setUserAgentString(settings.getUserAgentString() + " SmartTVRemote/0.6.2");

        webView.setWebViewClient(new WebViewClient());
        webView.setWebChromeClient(new WebChromeClient());
        webView.addJavascriptInterface(new VoiceBridge(), "NativeVoice");

        try {
            String url = Mobilebridge.start(getFilesDir().getAbsolutePath());
            webView.loadUrl(url);
        } catch (Exception error) {
            Toast.makeText(this, "Не вдалося запустити Smart TV Remote: " + error.getMessage(), Toast.LENGTH_LONG).show();
        }
    }

    private final class VoiceBridge {
        @JavascriptInterface
        public void start(String language) {
            pendingVoiceLanguage = language == null || language.isEmpty() ? "uk-UA" : language;
            runOnUiThread(() -> {
                if (android.os.Build.VERSION.SDK_INT >= 23 && checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
                    requestPermissions(new String[]{Manifest.permission.RECORD_AUDIO}, AUDIO_PERMISSION_REQUEST);
                    return;
                }
                launchVoiceRecognition();
            });
        }
    }

    private void launchVoiceRecognition() {
        Intent intent = new Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH);
        intent.putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM);
        intent.putExtra(RecognizerIntent.EXTRA_LANGUAGE, pendingVoiceLanguage);
        intent.putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, false);
        intent.putExtra(RecognizerIntent.EXTRA_PROMPT, "Говори текст для телевізора");
        try {
            startActivityForResult(intent, VOICE_REQUEST);
        } catch (Exception error) {
            sendVoiceError("На телефоні немає доступного сервісу розпізнавання мовлення.");
        }
    }

    @Override
    public void onRequestPermissionsResult(int requestCode, String[] permissions, int[] grantResults) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        if (requestCode == AUDIO_PERMISSION_REQUEST) {
            if (grantResults.length > 0 && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                launchVoiceRecognition();
            } else {
                sendVoiceError("Дозвіл на мікрофон не надано.");
            }
        }
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode != VOICE_REQUEST) {
            return;
        }
        if (resultCode == RESULT_OK && data != null) {
            ArrayList<String> results = data.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS);
            if (results != null && !results.isEmpty()) {
                sendVoiceResult(results.get(0));
                return;
            }
        }
        sendVoiceError("Голосове введення скасовано або текст не розпізнано.");
    }

    private static String quoteForJavaScript(String value) {
        if (value == null) return "\"\"";
        return "\"" + value
            .replace("\\", "\\\\")
            .replace("\"", "\\\"")
            .replace("\n", "\\n")
            .replace("\r", "\\r") + "\"";
    }

    private void sendVoiceResult(String text) {
        webView.evaluateJavascript("window.__nativeVoiceResult(" + quoteForJavaScript(text) + ")", null);
    }

    private void sendVoiceError(String message) {
        webView.evaluateJavascript("window.__nativeVoiceError(" + quoteForJavaScript(message) + ")", null);
    }

    @Override
    public void onBackPressed() {
        if (webView != null && webView.canGoBack()) {
            webView.goBack();
        } else {
            super.onBackPressed();
        }
    }

    @Override
    protected void onDestroy() {
        if (webView != null) {
            webView.destroy();
        }
        if (isFinishing()) {
            try {
                Mobilebridge.stop();
            } catch (Exception ignored) {
            }
        }
        super.onDestroy();
    }
}
__SRT_005_EOF__

# From bootstrap-006.sh
mkdir -p "$ROOT/android/app/src/main/res/drawable"
cat > "$ROOT/android/app/src/main/res/drawable/ic_launcher.xml" <<'__SRT_006_EOF__'
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp" android:height="108dp"
    android:viewportWidth="108" android:viewportHeight="108">
    <path android:fillColor="#081422" android:pathData="M0,0h108v108h-108z" />
    <path android:fillColor="#57B7FF" android:pathData="M18,24h72a8,8 0,0 1,8 8v46a8,8 0,0 1,-8 8h-72a8,8 0,0 1,-8 -8v-46a8,8 0,0 1,8 -8z" />
    <path android:fillColor="#081422" android:pathData="M25,32h58a5,5 0,0 1,5 5v34a5,5 0,0 1,-5 5h-58a5,5 0,0 1,-5 -5v-34a5,5 0,0 1,5 -5z" />
    <path android:fillColor="#E7BC2B" android:pathData="M54,40a14,14 0,1 0,0 28a14,14 0,1 0,0 -28z" />
    <path android:fillColor="#081422" android:pathData="M54,47a7,7 0,1 0,0 14a7,7 0,1 0,0 -14z" />
    <path android:strokeColor="#57B7FF" android:strokeWidth="5" android:strokeLineCap="round" android:fillColor="@android:color/transparent" android:pathData="M39,92h30" />
</vector>
__SRT_006_EOF__

# From bootstrap-007.sh
mkdir -p "$ROOT/android/app/src/main/res/values"
cat > "$ROOT/android/app/src/main/res/values/styles.xml" <<'__SRT_007_EOF__'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <style name="AppTheme" parent="android:style/Theme.Material.Light.NoActionBar">
        <item name="android:fontFamily">sans</item>
        <item name="android:windowActionModeOverlay">true</item>
        <item name="android:colorAccent">#57B7FF</item>
        <item name="android:navigationBarColor">#050B13</item>
        <item name="android:statusBarColor">#050B13</item>
        <item name="android:windowLightStatusBar">false</item>
        <item name="android:windowBackground">#050B13</item>
    </style>
</resources>
__SRT_007_EOF__
