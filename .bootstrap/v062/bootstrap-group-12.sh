#!/usr/bin/env bash
set -euo pipefail
ROOT="${1:-smart-tv-remote}"
mkdir -p "$ROOT"

# From bootstrap-037.sh
mkdir -p "$ROOT/remoteapp/web"
cat >> "$ROOT/remoteapp/web/index.html" <<'__SRT_037_EOF__'
    .brand-browser { color: #10b9dc; }
    .brand-keyboard, .brand-mic { color: #65caed; }
    .brand-netflix { color: #e50914; }
    .brand-playstation { color: #dcecff; }
    .brand-image {
      display: block;
      max-width: 100%;
      max-height: 100%;
      object-fit: contain;
      pointer-events: none;
      user-select: none;
    }
    .netflix-logo { width: 27px; height: 46px; }
    .playstation-logo { width: 53px; height: 42px; }

    .mode-row {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 14px;
      margin-bottom: 15px;
    }
    .mode-copy { min-width: 0; }
    .mode-title { font-weight: 850; font-size: 16px; }
    .mode-hint { margin-top: 3px; color: var(--muted); font-size: 11px; }
    .segments {
      display: grid;
      grid-template-columns: repeat(3, 1fr);
      min-width: 242px;
      padding: 3px;
      border: 1px solid var(--border);
      border-radius: 14px;
      background: #081422;
    }
    .segment {
      min-height: 36px;
      padding: 0 9px;
      border: 0;
      border-radius: 10px;
      background: transparent;
      color: var(--muted);
      font-size: 11px;
      font-weight: 800;
      cursor: pointer;
    }
    .segment.active { background: var(--blue-soft); color: var(--text); box-shadow: inset 0 0 0 1px #2a6a99; }

    .control-cluster {
      display: grid;
      grid-template-columns: 60px minmax(188px, 1fr) 60px;
      align-items: center;
      justify-items: center;
      gap: 9px;
      width: 100%;
    }

    .rocker {
      position: relative;
      width: 60px;
      height: 196px;
      padding: 6px 3px;
      border: 1px solid #34383f;
      border-radius: 13px;
      background: #101318;
      box-shadow: inset 0 0 0 1px rgba(255,255,255,.015);
    }
    .rocker button {
      position: absolute;
      left: 50%;
      width: 52px;
      height: 64px;
      border: 0;
      border-radius: 10px;
      background: transparent;
      color: var(--yellow);
      font-size: 25px;
      font-weight: 900;
      cursor: pointer;
      transform: translateX(-50%);
    }
    .rocker button:first-child { top: 6px; }
    .rocker button:last-child { bottom: 6px; }
    .rocker button:hover:not(:disabled) { background: #20242a; }
    .rocker button:active:not(:disabled) { transform: translateX(-50%) scale(.94); }
    .rocker-label {
      position: absolute;
      left: 0;
      right: 0;
      top: 50%;
      color: var(--yellow);
      font-size: 12px;
      line-height: 1;
      font-weight: 850;
      letter-spacing: .04em;
      text-align: center;
      transform: translateY(-50%);
      pointer-events: none;
    }

    .center-control { position: relative; width: 196px; height: 196px; }
    .dpad, .joystick {
      position: absolute;
      inset: 0;
      border: 1px solid #3a3d43;
      border-radius: 50%;
      background: radial-gradient(circle at 50% 42%, #171a1f, #0e1014 72%);
      box-shadow: inset 0 0 0 1px rgba(255,255,255,.018), 0 16px 30px rgba(0,0,0,.28);
      user-select: none;
      touch-action: none;
    }
    .dpad::before, .joystick::before {
      content: "";
      position: absolute;
      inset: 30px;
      border: 1px solid #272b31;
      border-radius: 50%;
    }
    .dpad-button {
      position: absolute;
      display: grid;
      place-items: center;
      width: 67px;
      height: 67px;
      border: 0;
      background: transparent;
      color: var(--yellow);
      font-size: 27px;
      font-weight: 900;
      cursor: pointer;
      z-index: 2;
    }
    .dpad-button:hover:not(:disabled) { color: #ffdc5b; }
    .dpad-button:active:not(:disabled) { transform: scale(.88); }
    .dpad-up { top: 0; left: 64px; }
    .dpad-right { right: 0; top: 64px; }
    .dpad-down { bottom: 0; left: 64px; }
    .dpad-left { left: 0; top: 64px; }
    .dpad-ok {
      position: absolute;
      left: 68px;
      top: 68px;
      width: 60px;
      height: 60px;
      z-index: 3;
      border: 1px solid #42464e;
      border-radius: 50%;
      background: #15181d;
      color: var(--yellow);
      font-size: 11px;
      font-weight: 900;
      cursor: pointer;
    }
    .dpad-ok:active:not(:disabled) { transform: scale(.92); }

    .joystick { cursor: grab; }
    .joystick.dragging { cursor: grabbing; }
    .joystick-direction {
      position: absolute;
      color: var(--yellow);
      font-size: 25px;
      font-weight: 900;
      pointer-events: none;
    }
    .j-up { top: 12px; left: 88px; }
    .j-right { right: 15px; top: 82px; }
    .j-down { bottom: 10px; left: 88px; }
    .j-left { left: 15px; top: 82px; }
    .stick {
      position: absolute;
      left: 67px;
      top: 67px;
      display: grid;
      place-items: center;
      width: 62px;
      height: 62px;
      border: 2px solid var(--yellow);
      border-radius: 50%;
      background: radial-gradient(circle at 42% 34%, #30343b, #15181d 67%);
      color: var(--yellow);
      font-size: 10px;
      font-weight: 900;
      box-shadow: 0 0 20px rgba(231, 188, 43, .16), 0 8px 18px rgba(0,0,0,.42);
      pointer-events: none;
      will-change: transform;
    }

    .speed-row { display: flex; align-items: center; justify-content: space-between; gap: 12px; margin-top: 14px; }
    .speed-label { color: var(--muted); font-size: 11px; }
    .speed-buttons { display: flex; gap: 6px; }
    .speed-btn {
      min-height: 32px;
      padding: 0 11px;
      border: 1px solid var(--border);
      border-radius: 10px;
      background: #0b1726;
      color: var(--muted);
      font-size: 10px;
      font-weight: 800;
      cursor: pointer;
    }
    .speed-btn.active { border-color: #2e7eb5; background: var(--blue-soft); color: var(--text); }

    .utility-row, .media-row {
      display: grid;
      grid-template-columns: repeat(3, 1fr);
      gap: 9px;
      margin-top: 15px;
    }

    .quick-grid {
      display: grid;
      grid-template-columns: repeat(6, minmax(0, 1fr));
      gap: 9px;
      margin-top: 15px;
    }

    .mode-note {
      margin-top: 14px;
      padding: 12px 13px;
      border: 1px solid var(--border-soft);
      border-radius: 15px;
      background: rgba(7, 17, 29, .7);
      color: var(--muted);
      font-size: 11px;
      line-height: 1.55;
    }
    .mode-note strong { color: var(--yellow); }

    .voice-layout { display: grid; gap: 11px; margin-top: 14px; }
    .voice-toolbar { display: grid; grid-template-columns: 112px 54px 1fr; gap: 8px; align-items: center; }
    .voice-status { color: var(--muted); font-size: 11px; line-height: 1.4; }
    .send-row { display: grid; grid-template-columns: 1fr auto; gap: 8px; }

    .device-meta {
      display: grid;
      grid-template-columns: auto 1fr;
      gap: 7px 12px;
      margin-top: 14px;
      font-size: 12px;
    }
    .device-meta dt { color: var(--muted); }
    .device-meta dd { margin: 0; min-width: 0; overflow-wrap: anywhere; }
    .secondary-actions { display: grid; grid-template-columns: 1fr 1fr; gap: 8px; margin-top: 14px; }

    .logs {
      max-height: 310px;
      overflow: auto;
      margin-top: 13px;
      padding: 11px;
      border: 1px solid var(--border-soft);
      border-radius: 15px;
__SRT_037_EOF__
