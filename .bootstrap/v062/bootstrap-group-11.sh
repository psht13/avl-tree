#!/usr/bin/env bash
set -euo pipefail
ROOT="${1:-smart-tv-remote}"
mkdir -p "$ROOT"

# From bootstrap-036.sh
mkdir -p "$ROOT/remoteapp/web"
cat > "$ROOT/remoteapp/web/index.html" <<'__SRT_036_EOF__'
<!doctype html>
<html lang="uk">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
  <meta name="color-scheme" content="dark">
  <title>Smart TV Remote</title>
  <style>
    :root {
      --bg: #050b13;
      --panel: #0b1624;
      --panel-2: #101f31;
      --panel-3: #172a40;
      --border: #263d58;
      --border-soft: #192b40;
      --text: #f3f7fc;
      --muted: #8da2bb;
      --blue: #57b7ff;
      --blue-soft: #153e63;
      --yellow: #e7bc2b;
      --red: #ff5f6d;
      --green: #35d58a;
      --shadow: 0 20px 55px rgba(0, 0, 0, .32);
    }

    * { box-sizing: border-box; }
    html { min-height: 100%; background: var(--bg); }
    body {
      min-height: 100vh;
      margin: 0;
      color: var(--text);
      background:
        radial-gradient(circle at 20% -10%, rgba(51, 145, 219, .14), transparent 34rem),
        radial-gradient(circle at 100% 15%, rgba(229, 185, 40, .06), transparent 25rem),
        var(--bg);
      font-family: Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    }

    button, input, textarea, select { font: inherit; }
    button { -webkit-tap-highlight-color: transparent; }
    .hidden { display: none !important; }
    .svg-defs { position: absolute; width: 0; height: 0; overflow: hidden; }

    .shell {
      width: min(1120px, calc(100% - 24px));
      margin: 0 auto;
      padding: 22px 0 48px;
    }

    .header {
      display: flex;
      align-items: center;
      gap: 14px;
      margin-bottom: 16px;
      padding: 0 4px;
    }

    .brand-mark {
      display: grid;
      place-items: center;
      width: 48px;
      height: 48px;
      border: 1px solid #32648c;
      border-radius: 16px;
      background: linear-gradient(145deg, #174a74, #0c2741);
      box-shadow: 0 12px 30px rgba(33, 150, 243, .16);
      font-size: 12px;
      font-weight: 900;
      letter-spacing: .08em;
    }

    .header-copy { min-width: 0; flex: 1; }
    h1 { margin: 0; font-size: clamp(20px, 3vw, 28px); line-height: 1.1; }
    .subtitle { margin: 6px 0 0; color: var(--muted); font-size: 13px; }

    .status-pill {
      display: inline-flex;
      align-items: center;
      gap: 8px;
      max-width: 44%;
      padding: 9px 12px;
      border: 1px solid var(--border);
      border-radius: 999px;
      background: rgba(11, 22, 36, .82);
      color: var(--muted);
      font-size: 12px;
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
    }

    .status-dot {
      flex: 0 0 auto;
      width: 8px;
      height: 8px;
      border-radius: 50%;
      background: #64748b;
      box-shadow: 0 0 0 5px rgba(100, 116, 139, .12);
    }
    .status-pill.connected .status-dot { background: var(--green); box-shadow: 0 0 0 5px rgba(53, 213, 138, .12); }
    .status-pill.error .status-dot { background: var(--red); box-shadow: 0 0 0 5px rgba(255, 95, 109, .12); }
    .status-pill.connecting .status-dot,
    .status-pill.discovering .status-dot,
    .status-pill.awaiting-approval .status-dot { background: var(--yellow); box-shadow: 0 0 0 5px rgba(231, 188, 43, .12); }

    .layout {
      display: grid;
      grid-template-columns: minmax(0, 1.42fr) minmax(280px, .78fr);
      gap: 16px;
      align-items: start;
    }

    .stack { display: grid; gap: 16px; }
    .card {
      border: 1px solid var(--border-soft);
      border-radius: 24px;
      background: linear-gradient(160deg, rgba(16, 31, 49, .96), rgba(7, 17, 29, .98));
      box-shadow: var(--shadow);
      overflow: hidden;
    }
    .card-body { padding: 18px; }
    .card-title { margin: 0; font-size: 16px; font-weight: 800; }
    .card-copy { margin: 5px 0 0; color: var(--muted); font-size: 12px; line-height: 1.55; }

    .provider-grid {
      display: grid;
      grid-template-columns: minmax(180px, .62fr) minmax(0, 1.38fr) auto auto;
      gap: 9px;
      margin-top: 14px;
    }
    .pairing-grid {
      display: grid;
      grid-template-columns: minmax(0, 1fr) auto;
      gap: 9px;
      margin-top: 10px;
      padding: 12px;
      border: 1px solid #715a18;
      border-radius: 16px;
      background: rgba(91, 70, 10, .22);
    }
    .pairing-help { grid-column: 1 / -1; color: #e6c85d; font-size: 12px; line-height: 1.45; }

    input, textarea, select {
      width: 100%;
      border: 1px solid var(--border);
      border-radius: 14px;
      outline: none;
      background: #081422;
      color: var(--text);
    }
    input { min-height: 46px; padding: 0 13px; }
    textarea { min-height: 122px; padding: 13px; resize: vertical; line-height: 1.5; }
    select { min-height: 42px; padding: 0 11px; }
    input:focus, textarea:focus, select:focus { border-color: var(--blue); box-shadow: 0 0 0 3px rgba(87, 183, 255, .12); }

    .text-button {
      min-height: 44px;
      padding: 0 15px;
      border: 1px solid var(--border);
      border-radius: 14px;
      background: var(--panel-2);
      color: var(--text);
      font-weight: 750;
      cursor: pointer;
      transition: transform .14s ease, border-color .14s ease, background .14s ease, opacity .14s ease;
    }
    .text-button:hover:not(:disabled) { border-color: #3f6083; background: var(--panel-3); }
    .text-button:active:not(:disabled) { transform: scale(.97); }
    .text-button.accent { border-color: #2c75a8; background: linear-gradient(145deg, #1f6597, #16476d); }
    .text-button.danger { border-color: #74404a; background: #3d1d25; }
    button:disabled { opacity: .35; cursor: default; }

    .remote-card .card-body { padding: 16px; }
    .remote-top {
      display: grid;
      grid-template-columns: repeat(4, 1fr);
      gap: 8px;
      margin-bottom: 15px;
    }

    .icon-button {
      position: relative;
      display: grid;
      place-items: center;
      min-width: 0;
      height: 54px;
      padding: 0;
      border: 1px solid var(--border);
      border-radius: 17px;
      background: linear-gradient(145deg, #14253a, #0d1a2a);
      color: #eaf2fb;
      cursor: pointer;
      transition: transform .14s ease, border-color .14s ease, background .14s ease, box-shadow .14s ease, opacity .14s ease;
    }
    .icon-button:hover:not(:disabled) { border-color: #45678b; background: linear-gradient(145deg, #1a304a, #112237); }
    .icon-button:active:not(:disabled) { transform: scale(.95); }
    .icon-button.accent { border-color: #2d75a6; background: linear-gradient(145deg, #1b5b88, #123d5f); }
    .icon-button.danger { border-color: #7b3b47; background: linear-gradient(145deg, #4c2029, #2a141a); color: #ff8490; }
    .icon-button.selected { border-color: var(--yellow); box-shadow: 0 0 0 2px rgba(231, 188, 43, .12), 0 0 24px rgba(231, 188, 43, .08); }
    .icon-button.large { height: 68px; border-radius: 20px; }
    .icon-button .icon { width: 27px; height: 27px; }
    .icon-button.large .icon { width: 36px; height: 36px; }
    .icon { display: block; overflow: visible; fill: none; stroke: currentColor; stroke-width: 1.9; stroke-linecap: round; stroke-linejoin: round; }
    .icon.fill { fill: currentColor; stroke: none; }
    .brand-youtube { color: #ff0033; }
__SRT_036_EOF__
