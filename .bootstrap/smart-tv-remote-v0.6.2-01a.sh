#!/usr/bin/env bash
set -euo pipefail
ROOT="${1:-smart-tv-remote}"
mkdir -p "$ROOT"

# From bootstrap-008.sh
mkdir -p "$ROOT/android/app/src/main/res/xml"
cat > "$ROOT/android/app/src/main/res/xml/network_security_config.xml" <<'__SRT_008_EOF__'
<?xml version="1.0" encoding="utf-8"?>
<network-security-config>
    <base-config cleartextTrafficPermitted="true" />
</network-security-config>
__SRT_008_EOF__

# From bootstrap-009.sh
mkdir -p "$ROOT/android"
cat > "$ROOT/android/build.gradle" <<'__SRT_009_EOF__'
plugins {
    id "com.android.application" version "8.7.3" apply false
}
__SRT_009_EOF__

# From bootstrap-010.sh
mkdir -p "$ROOT/android"
cat > "$ROOT/android/gradle.properties" <<'__SRT_010_EOF__'
org.gradle.jvmargs=-Xmx3072m -Dfile.encoding=UTF-8
android.useAndroidX=true
android.nonTransitiveRClass=true
__SRT_010_EOF__

# From bootstrap-011.sh
mkdir -p "$ROOT/android"
cat > "$ROOT/android/settings.gradle" <<'__SRT_011_EOF__'
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}
rootProject.name = "SmartTVRemote"
include(":app")
__SRT_011_EOF__

# From bootstrap-012.sh
mkdir -p "$ROOT/cmd/windows"
cat > "$ROOT/cmd/windows/main.go" <<'__SRT_012_EOF__'
package main

import (
	"log"
	"os"
	"os/exec"
	"os/signal"
	"runtime"
	"syscall"
	"time"

	"smarttvremote/remoteapp"
)

func openBrowser(address string) error {
	switch runtime.GOOS {
	case "windows":
		return exec.Command("rundll32", "url.dll,FileProtocolHandler", address).Start()
	case "darwin":
		return exec.Command("open", address).Start()
	default:
		return exec.Command("xdg-open", address).Start()
	}
}

func main() {
	server, err := remoteapp.StartServer("")
	if err != nil {
		log.Fatal(err)
	}
	defer server.Close()
	time.Sleep(250 * time.Millisecond)
	_ = openBrowser(server.URL)

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, os.Interrupt, syscall.SIGTERM)
	<-stop
}
__SRT_012_EOF__

# From bootstrap-013.sh
cat > "$ROOT/go.mod" <<'__SRT_013_EOF__'
module smarttvremote

go 1.23.0

require (
	github.com/drosocode/atvremote v0.0.0-20220206183504-967d9ff8e74c
	google.golang.org/protobuf v1.36.10
)
__SRT_013_EOF__

# From bootstrap-014.sh
mkdir -p "$ROOT/mobilebridge"
cat > "$ROOT/mobilebridge/mobilebridge.go" <<'__SRT_014_EOF__'
package mobilebridge

import (
	"errors"
	"sync"

	"smarttvremote/remoteapp"
)

var (
	mu     sync.Mutex
	server *remoteapp.Server
)

// Start launches the local controller service and returns the loopback URL for the Android WebView.
func Start(storageDir string) (string, error) {
	mu.Lock()
	defer mu.Unlock()
	if server != nil {
		return server.URL, nil
	}
	started, err := remoteapp.StartServer(storageDir)
	if err != nil {
		return "", err
	}
	server = started
	return server.URL, nil
}

// Stop shuts down the local controller service.
func Stop() error {
	mu.Lock()
	defer mu.Unlock()
	if server == nil {
		return nil
	}
	err := server.Close()
	server = nil
	return err
}

// URL returns the current loopback URL.
func URL() (string, error) {
	mu.Lock()
	defer mu.Unlock()
	if server == nil {
		return "", errors.New("service is not running")
	}
	return server.URL, nil
}
__SRT_014_EOF__
