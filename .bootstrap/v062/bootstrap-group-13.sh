#!/usr/bin/env bash
set -euo pipefail
ROOT="${1:-smart-tv-remote}"
mkdir -p "$ROOT"

# From bootstrap-038.sh
mkdir -p "$ROOT/remoteapp/web"
cat >> "$ROOT/remoteapp/web/index.html" <<'__SRT_038_EOF__'
      background: #050d17;
      color: #a9bbcf;
      font: 11px/1.55 ui-monospace, SFMono-Regular, Consolas, monospace;
      white-space: pre-wrap;
      overflow-wrap: anywhere;
    }

    .toast {
      position: fixed;
      left: 50%;
      bottom: 24px;
      z-index: 50;
      max-width: min(460px, calc(100% - 30px));
      padding: 11px 15px;
      border: 1px solid #315b7d;
      border-radius: 14px;
      background: #10263a;
      color: var(--text);
      box-shadow: 0 16px 48px rgba(0,0,0,.45);
      font-size: 12px;
      transform: translate(-50%, 20px);
      opacity: 0;
      pointer-events: none;
      transition: .2s ease;
    }
    .toast.visible { transform: translate(-50%, 0); opacity: 1; }
    .toast.error { border-color: #81404a; background: #351a21; }

    @media (max-width: 900px) {
      .layout { grid-template-columns: 1fr; }
      .status-pill { max-width: 52%; }
    }

    @media (max-width: 620px) {
      .shell { width: min(100% - 14px, 620px); padding-top: 10px; }
      .header { align-items: flex-start; }
      .status-pill { max-width: 42%; }
      .provider-grid { grid-template-columns: 1fr 1fr; }
      .provider-grid select, .provider-grid input { grid-column: 1 / -1; }
      .mode-row { align-items: stretch; flex-direction: column; }
      .segments { width: 100%; min-width: 0; }
      .control-cluster { grid-template-columns: 48px minmax(176px, 1fr) 48px; gap: 5px; }
      .rocker { width: 48px; }
      .rocker button { width: 42px; }
      .quick-grid { grid-template-columns: repeat(3, 1fr); }
      .voice-toolbar { grid-template-columns: 100px 54px 1fr; }
    }
  </style>
</head>
<body>
  <svg class="svg-defs" aria-hidden="true">
    <symbol id="icon-power" viewBox="0 0 24 24"><path d="M12 2.5v8"/><path d="M7.2 5.7a8 8 0 1 0 9.6 0"/></symbol>
    <symbol id="icon-home" viewBox="0 0 24 24"><path d="M3 11.2 12 3l9 8.2"/><path d="M5.7 9.8V21h12.6V9.8"/><path d="M10 21v-6h4v6"/></symbol>
    <symbol id="icon-source" viewBox="0 0 24 24"><rect x="3" y="4" width="18" height="12" rx="2"/><path d="M9 20h6M12 16v4"/></symbol>
    <symbol id="icon-apps" viewBox="0 0 24 24"><rect x="4" y="4" width="6" height="6" rx="1"/><rect x="14" y="4" width="6" height="6" rx="1"/><rect x="4" y="14" width="6" height="6" rx="1"/><rect x="14" y="14" width="6" height="6" rx="1"/></symbol>
    <symbol id="icon-back" viewBox="0 0 24 24"><path d="m9 6-6 6 6 6"/><path d="M4 12h10.5c3.8 0 5.5 2.1 5.5 5"/></symbol>
    <symbol id="icon-exit" viewBox="0 0 24 24"><path d="M10 4H4v16h6"/><path d="M13 8l5 4-5 4M8 12h10"/></symbol>
    <symbol id="icon-mute" viewBox="0 0 24 24"><path d="M4 9v6h4l5 4V5L8 9H4Z" fill="currentColor" stroke="none"/><path d="m17 8 5 8M22 8l-5 8"/></symbol>
    <symbol id="icon-rewind" viewBox="0 0 24 24"><path d="m11 6-7 6 7 6V6Z" fill="currentColor" stroke="none"/><path d="m20 6-7 6 7 6V6Z" fill="currentColor" stroke="none"/></symbol>
    <symbol id="icon-forward" viewBox="0 0 24 24"><path d="m13 6 7 6-7 6V6Z" fill="currentColor" stroke="none"/><path d="m4 6 7 6-7 6V6Z" fill="currentColor" stroke="none"/></symbol>
    <symbol id="icon-play" viewBox="0 0 24 24"><path d="m7 4 13 8-13 8V4Z" fill="currentColor" stroke="none"/></symbol>
    <symbol id="icon-pause" viewBox="0 0 24 24"><rect x="6" y="4" width="4.5" height="16" rx="1" fill="currentColor" stroke="none"/><rect x="13.5" y="4" width="4.5" height="16" rx="1" fill="currentColor" stroke="none"/></symbol>
    <symbol id="icon-youtube" viewBox="0 0 32 24"><rect x="1" y="2" width="30" height="20" rx="6" fill="currentColor" stroke="none"/><path d="m13 7 8 5-8 5V7Z" fill="#fff" stroke="none"/></symbol>
    <symbol id="icon-browser" viewBox="0 0 24 24"><circle cx="12" cy="12" r="9"/><path d="M3.5 12h17M12 3c2.5 2.7 3.7 5.7 3.7 9S14.5 18.3 12 21M12 3C9.5 5.7 8.3 8.7 8.3 12S9.5 18.3 12 21"/></symbol>
    <symbol id="icon-keyboard" viewBox="0 0 24 24"><rect x="2" y="6" width="20" height="13" rx="2"/><path d="M6 10h.01M10 10h.01M14 10h.01M18 10h.01M6 14h.01M10 14h.01M14 14h.01M18 14h.01M7 17h10M17 3h3v3"/></symbol>
    <symbol id="icon-mic" viewBox="0 0 24 24"><rect x="8" y="2.5" width="8" height="13" rx="4"/><path d="M5 11.5a7 7 0 0 0 14 0M12 18.5V22M8 22h8"/></symbol>
  </svg>

  <main class="shell">
    <header class="header">
      <div class="brand-mark">TV</div>
      <div class="header-copy">
        <h1>Smart TV Remote</h1>
        <p class="subtitle">Samsung Tizen + Thomson / Google TV · версія 0.6.2</p>
      </div>
      <div id="statusPill" class="status-pill idle" title="Стан підключення">
        <span class="status-dot"></span>
        <span id="statusText">TV ще не підключено</span>
      </div>
    </header>

    <div class="layout">
      <section class="stack">
        <article class="card">
          <div class="card-body">
            <h2 class="card-title">Підключення</h2>
            <p class="card-copy">Телефон/ПК і TV мають бути в одній локальній мережі. Samsung підтверджується дозволом на екрані, а Google TV - одноразовим 6-символьним кодом.</p>
            <div class="provider-grid">
              <select id="provider" aria-label="Платформа телевізора">
                <option value="samsung">Samsung Tizen</option>
                <option value="google">Thomson / Google TV</option>
              </select>
              <input id="ip" inputmode="decimal" autocomplete="off" placeholder="IP телевізора, наприклад 192.168.1.120" aria-label="IP телевізора">
              <button id="connect" class="text-button accent">Підключити</button>
              <button id="discover" class="text-button">Знайти TV</button>
            </div>
            <div id="pairingRow" class="pairing-grid hidden">
              <div class="pairing-help">На Thomson має з'явитися код. Введи всі 6 символів, після чого цей телефон/ПК запам'ятається.</div>
              <input id="pairCode" autocomplete="one-time-code" maxlength="6" placeholder="Код з TV, наприклад A1B2C3" aria-label="Код Google TV">
              <button id="pairButton" class="text-button accent">Підтвердити код</button>
            </div>
          </div>
        </article>

        <article class="card remote-card">
          <div class="card-body">
            <div class="remote-top">
              <button class="icon-button danger remote-command" data-key="KEY_POWER" data-requires-tv title="Живлення" aria-label="Живлення"><svg class="icon"><use href="#icon-power"></use></svg></button>
              <button class="icon-button remote-command dpad-return" data-key="KEY_HOME" data-requires-tv title="Дім" aria-label="Дім"><svg class="icon"><use href="#icon-home"></use></svg></button>
              <button class="icon-button remote-command dpad-return" data-key="KEY_SOURCE" data-requires-tv title="Джерело" aria-label="Джерело"><svg class="icon"><use href="#icon-source"></use></svg></button>
              <button class="icon-button remote-command dpad-return" data-key="KEY_HOME" data-requires-tv title="Застосунки" aria-label="Застосунки"><svg class="icon"><use href="#icon-apps"></use></svg></button>
            </div>

            <div class="mode-row">
              <div class="mode-copy">
__SRT_038_EOF__
