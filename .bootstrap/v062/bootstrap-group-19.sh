#!/usr/bin/env bash
set -euo pipefail
ROOT="${1:?missing output root}"

mkdir -p "$ROOT/android"
base64 -d > "$ROOT/android/test-debug.keystore" <<'EOF'
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
EOF
chmod 600 "$ROOT/android/test-debug.keystore"

python3 - "$ROOT/android/app/build.gradle" "$ROOT/README.md" <<'PY'
from pathlib import Path
import sys

build_path = Path(sys.argv[1])
source = build_path.read_text(encoding="utf-8")
old = '''    buildTypes {
        debug {
            minifyEnabled false
        }
        release {
            minifyEnabled false
        }
    }
'''
new = '''    signingConfigs {
        testBuild {
            storeFile rootProject.file("test-debug.keystore")
            storePassword "smarttvremote-test"
            keyAlias "smarttvremote-test"
            keyPassword "smarttvremote-test"
        }
    }

    buildTypes {
        debug {
            signingConfig signingConfigs.testBuild
            minifyEnabled false
        }
        release {
            signingConfig signingConfigs.testBuild
            minifyEnabled false
        }
    }
'''
if old not in source:
    raise SystemExit("Android buildTypes marker missing")
source = source.replace(old, new, 1)
build_path.write_text(source, encoding="utf-8")

readme_path = Path(sys.argv[2])
readme = readme_path.read_text(encoding="utf-8")
marker = "- Added protocol regression tests for feature negotiation, configuration identity and readiness.\n"
addition = marker + "- Added a dedicated test-only signing key, so later test builds can update 0.6.3 without another uninstall.\n"
if marker not in readme:
    raise SystemExit("README 0.6.3 marker missing")
readme = readme.replace(marker, addition, 1)
readme_path.write_text(readme, encoding="utf-8")
PY

test -s "$ROOT/android/test-debug.keystore"
grep -F 'signingConfig signingConfigs.testBuild' "$ROOT/android/app/build.gradle"
