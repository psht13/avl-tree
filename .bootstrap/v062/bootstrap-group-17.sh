#!/usr/bin/env bash
set -euo pipefail
ROOT="${1:?missing output root}"
mkdir -p "$ROOT/internal/tools"
cat > "$ROOT/internal/tools/tools.go" <<'EOF'
//go:build tools

// Package tools keeps the gomobile toolchain in the module graph so Go 1.26
// can build the Android bridge reproducibly.
package tools

import (
	_ "golang.org/x/mobile/cmd/gobind"
	_ "golang.org/x/mobile/cmd/gomobile"
)
EOF
