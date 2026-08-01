#!/usr/bin/env bash
set -euo pipefail
ROOT="${1:-smart-tv-remote}"
mkdir -p "$ROOT"

# From bootstrap-040.sh
mkdir -p "$ROOT/remoteapp/web"
cat >> "$ROOT/remoteapp/web/index.html" <<'__SRT_040_EOF__'
                  <option value="en-US">English</option>
                </select>
                <button id="voice" class="icon-button brand-mic" data-requires-tv title="Почати або зупинити диктування" aria-label="Диктувати"><svg class="icon"><use href="#icon-mic"></use></svg></button>
                <div id="voiceStatus" class="voice-status">Натисни мікрофон і говори.</div>
              </div>
              <textarea id="text" placeholder="Пошуковий запит, адреса сайту або інший текст" aria-label="Текст для телевізора"></textarea>
              <div class="send-row">
                <button id="focusText" class="text-button">Показати клавіатуру</button>
                <button id="sendText" class="text-button accent" data-requires-tv>Надіслати на TV</button>
              </div>
            </div>
          </div>
        </article>

        <article class="card">
          <div class="card-body">
            <h2 class="card-title">Телевізор</h2>
            <dl class="device-meta">
              <dt>Платформа</dt><dd id="devicePlatform">-</dd>
              <dt>Назва</dt><dd id="deviceName">-</dd>
              <dt>Модель</dt><dd id="deviceModel">-</dd>
              <dt>IP</dt><dd id="deviceIp">-</dd>
              <dt>Порт</dt><dd id="devicePort">-</dd>
              <dt>Дозвіл</dt><dd id="tokenState">-</dd>
              <dt>Авто-режим</dt><dd id="autoState">-</dd>
            </dl>
            <div class="secondary-actions">
              <button id="disconnect" class="text-button" data-requires-tv>Відключити</button>
              <button id="forget" class="text-button danger">Забути TV</button>
            </div>
          </div>
        </article>

        <article class="card">
          <div class="card-body">
            <h2 class="card-title">Діагностика</h2>
            <p class="card-copy">Тут видно підключення, повторний пошук IP, сполучення Google TV і визначення активного Samsung Browser.</p>
            <div id="logs" class="logs">Журнал поки порожній.</div>
          </div>
        </article>
      </aside>
    </div>
  </main>

  <div id="toast" class="toast" role="status" aria-live="polite"></div>

  <script>
    (() => {
      const $ = (id) => document.getElementById(id);
      const elements = {
        provider: $('provider'), ip: $('ip'), connect: $('connect'), discover: $('discover'),
        pairingRow: $('pairingRow'), pairCode: $('pairCode'), pairButton: $('pairButton'),
        statusPill: $('statusPill'), statusText: $('statusText'),
        devicePlatform: $('devicePlatform'), deviceName: $('deviceName'), deviceModel: $('deviceModel'), deviceIp: $('deviceIp'),
        devicePort: $('devicePort'), tokenState: $('tokenState'), autoState: $('autoState'), logs: $('logs'),
        autoMode: $('autoMode'), dpadMode: $('dpadMode'), pointerMode: $('pointerMode'),
        modeTitle: $('modeTitle'), modeHint: $('modeHint'), dpad: $('dpad'), joystick: $('joystick'), stick: $('stick'), speedRow: $('speedRow'),
        browser: $('browser'), youtube: $('youtube'), netflix: $('netflix'), playstation: $('playstation'),
        openKeyboard: $('openKeyboard'), openVoice: $('openVoice'), voiceCard: $('voiceCard'),
        text: $('text'), focusText: $('focusText'), sendText: $('sendText'), voice: $('voice'), voiceStatus: $('voiceStatus'), speechLanguage: $('speechLanguage'),
        playPause: $('playPause'), playPauseUse: $('playPauseUse'),
        disconnect: $('disconnect'), forget: $('forget'), pointerNote: $('pointerNote'), toast: $('toast')
      };

      let state = { provider: 'samsung', connected: false, controlModeHint: 'unknown', autoModeSupported: false, pairingRequired: false, logs: [] };
      let lastRenderedProvider = null;
      let modePreference = localStorage.getItem('controlModePreference') || 'auto';
      if (!['auto', 'dpad', 'pointer'].includes(modePreference)) modePreference = 'auto';
      let effectiveMode = 'dpad';
      let speed = localStorage.getItem('cursorSpeed') || 'normal';
      if (!['slow', 'normal', 'fast'].includes(speed)) speed = 'normal';
      let mediaPlaying = true;
      let refreshPending = false;
      let toastTimer = null;
      let recognition = null;
      let listening = false;
      let joystickPointerId = null;
      let joystickStartedAt = 0;
      let joystickMoved = false;
      let vector = { x: 0, y: 0, magnitude: 0 };
      let moveTimer = null;
      let movePending = false;

      const speedMultiplier = { slow: .44, normal: .76, fast: 1.18 };

      async function api(path, body) {
        const options = body === undefined
          ? { cache: 'no-store' }
          : { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) };
        const response = await fetch(path, options);
        const payload = await response.json().catch(() => ({}));
        if (!response.ok || payload.ok === false) throw new Error(payload.error || `HTTP ${response.status}`);
        return payload;
      }

      function showToast(message, error = false) {
        if (!message) return;
        elements.toast.textContent = message;
        elements.toast.classList.toggle('error', error);
        elements.toast.classList.add('visible');
        clearTimeout(toastTimer);
        toastTimer = setTimeout(() => elements.toast.classList.remove('visible'), 2600);
      }

      async function command(path, body, announce = false) {
        try {
          await api(path, body);
          if (announce) showToast('Команду надіслано');
          return true;
        } catch (error) {
          showToast(error.message, true);
          return false;
        }
      }

      function setEffectiveMode(mode) {
        if (!['dpad', 'pointer'].includes(mode)) return;
        effectiveMode = mode;
        const pointer = mode === 'pointer';
        elements.dpad.classList.toggle('hidden', pointer);
        elements.joystick.classList.toggle('hidden', !pointer);
        elements.speedRow.classList.toggle('hidden', !pointer);
        elements.modeTitle.textContent = pointer ? 'Керування курсором' : 'Навігація TV';
        const google = state.provider === 'google';
        elements.modeHint.textContent = modePreference === 'auto'
          ? pointer
            ? google ? 'Google TV: джойстик перетворюється на швидкі напрямки' : 'Автоматично визначено браузер'
            : 'Автоматичний режим активний'
          : pointer
            ? google ? 'Центр = OK, рух = D-pad напрямки' : 'Центр працює як звичайний клік'
            : 'Стрілки та OK';
      }

      function applyModePreference(preference, persist = true) {
        if (!['auto', 'dpad', 'pointer'].includes(preference)) return;
        modePreference = preference;
        if (persist) localStorage.setItem('controlModePreference', preference);
        document.querySelectorAll('[data-mode-preference]').forEach((button) => {
          button.classList.toggle('active', button.dataset.modePreference === preference);
        });
        if (preference === 'auto') {
          if (state.controlModeHint === 'pointer' || state.controlModeHint === 'dpad') setEffectiveMode(state.controlModeHint);
__SRT_040_EOF__

# From bootstrap-041.sh
mkdir -p "$ROOT/remoteapp/web"
cat >> "$ROOT/remoteapp/web/index.html" <<'__SRT_041_EOF__'
          else setEffectiveMode(effectiveMode);
        } else {
          setEffectiveMode(preference);
        }
      }

      function setSpeed(next) {
        speed = next;
        localStorage.setItem('cursorSpeed', next);
        document.querySelectorAll('.speed-btn').forEach((button) => button.classList.toggle('active', button.dataset.speed === next));
      }

      function resetPlayPause(nextPlaying = true) {
        mediaPlaying = nextPlaying;
        const icon = mediaPlaying ? '#icon-pause' : '#icon-play';
        const label = mediaPlaying ? 'Пауза' : 'Відтворити';
        elements.playPauseUse.setAttribute('href', icon);
        elements.playPause.setAttribute('title', label);
        elements.playPause.setAttribute('aria-label', label);
        elements.playPause.classList.toggle('selected', !mediaPlaying);
      }

      function renderState() {
        const status = state.status || 'idle';
        elements.statusPill.className = `status-pill ${status}`;
        elements.statusText.textContent = state.message || status;
        if (lastRenderedProvider !== state.provider) {
          lastRenderedProvider = state.provider;
          elements.provider.value = state.provider || 'samsung';
          elements.ip.value = state.ip || '';
        } else if (state.ip && !elements.ip.value) {
          elements.ip.value = state.ip;
        }
        elements.pairingRow.classList.toggle('hidden', !state.pairingRequired);
        elements.devicePlatform.textContent = state.providerLabel || (state.provider === 'google' ? 'Thomson / Google TV' : 'Samsung Tizen');
        elements.deviceName.textContent = state.displayName || (state.provider === 'google' ? 'Thomson Google TV' : 'Samsung TV');
        elements.deviceModel.textContent = state.modelName || '-';
        elements.deviceIp.textContent = state.ip || '-';
        elements.devicePort.textContent = state.port ? String(state.port) : '-';
        elements.tokenState.textContent = state.provider === 'google'
          ? state.hasToken
            ? 'Сполучення підтверджено'
            : state.pairingRequired
              ? 'Потрібен код з TV'
              : 'Не сполучено'
          : state.hasToken
            ? 'Токен збережено'
            : 'Ще немає';
        elements.autoState.textContent = state.provider === 'google'
          ? 'D-pad / свайп-імітація'
          : state.autoModeSupported
            ? state.controlModeHint === 'pointer' ? 'Браузер - курсор' : 'D-pad'
            : 'Резервний режим';
        elements.pointerNote.innerHTML = state.provider === 'google'
          ? '<strong>Thomson / Google TV:</strong> джойстик надсилає швидкі D-pad напрямки. Без встановлення TV Helper справжній системний курсор не гарантується.'
          : '<strong>Samsung:</strong> програма перевіряє, чи видимий Samsung Browser, і перемикає D-pad у вільний курсор.';
        elements.logs.textContent = state.logs && state.logs.length ? state.logs.join('\n') : 'Журнал поки порожній.';

        document.querySelectorAll('[data-requires-tv]').forEach((control) => { control.disabled = !state.connected; });
        elements.connect.disabled = state.connecting || state.discovering;
        elements.discover.disabled = state.connecting || state.discovering;
        elements.connect.textContent = state.connecting ? 'Підключення…' : 'Підключити';
        elements.discover.textContent = state.discovering ? 'Пошук…' : 'Знайти TV';
        elements.pairButton.disabled = state.connecting;

        if (modePreference === 'auto' && (state.controlModeHint === 'pointer' || state.controlModeHint === 'dpad')) {
          setEffectiveMode(state.controlModeHint);
        }
      }

      async function refreshState() {
        if (refreshPending) return;
        refreshPending = true;
        try {
          state = await api('/api/state');
          renderState();
        } catch (error) {
          elements.statusText.textContent = 'Локальний сервіс не відповідає';
        } finally {
          refreshPending = false;
        }
      }

      elements.provider.addEventListener('change', async () => {
        try {
          await api('/api/provider', { provider: elements.provider.value });
          elements.ip.value = '';
          elements.pairCode.value = '';
          showToast(elements.provider.value === 'google' ? 'Обрано Thomson / Google TV' : 'Обрано Samsung Tizen');
          await refreshState();
        } catch (error) { showToast(error.message, true); }
      });

      elements.connect.addEventListener('click', async () => {
        const ip = elements.ip.value.trim();
        if (!ip) return showToast('Введи IP телевізора', true);
        try {
          await api('/api/connect', { provider: elements.provider.value, ip });
          showToast(elements.provider.value === 'google'
            ? 'Підключаюсь. Якщо TV ще не сполучений, на ньому з’явиться код.'
            : 'Підключення розпочато. Підтвердь запит на TV.');
          refreshState();
        } catch (error) { showToast(error.message, true); }
      });

      elements.pairButton.addEventListener('click', async () => {
        const code = elements.pairCode.value.trim();
        if (code.replace(/[\s_-]/g, '').length !== 6) return showToast('Введи всі 6 символів коду з TV', true);
        try {
          await api('/api/pair', { code });
          elements.pairCode.value = '';
          showToast('Thomson сполучено. Надалі код зазвичай не потрібен.');
          refreshState();
        } catch (error) { showToast(error.message, true); }
      });
      elements.pairCode.addEventListener('keydown', (event) => { if (event.key === 'Enter') elements.pairButton.click(); });

      elements.ip.addEventListener('keydown', (event) => { if (event.key === 'Enter') elements.connect.click(); });

      elements.discover.addEventListener('click', async () => {
        showToast(`Шукаю ${elements.provider.value === 'google' ? 'Google TV' : 'Samsung TV'} у локальній мережі…`);
        try {
          const result = await api('/api/discover', {});
          showToast(result.message || `Знайдено: ${result.devices?.length || 0}`, !result.selected);
        } catch (error) { showToast(error.message, true); }
        refreshState();
      });

      document.querySelectorAll('.remote-command').forEach((button) => {
        button.addEventListener('click', async () => {
          const sent = await command('/api/key', { key: button.dataset.key });
          if (sent && button.classList.contains('dpad-return') && modePreference === 'auto') {
            state.controlModeHint = 'dpad';
            setEffectiveMode('dpad');
          }
        });
      });

      document.querySelectorAll('[data-mode-preference]').forEach((button) => {
        button.addEventListener('click', () => applyModePreference(button.dataset.modePreference));
      });
      document.querySelectorAll('.speed-btn').forEach((button) => button.addEventListener('click', () => setSpeed(button.dataset.speed)));

      async function launchApp(app) {
        try {
          const result = await api('/api/launch', { app });
__SRT_041_EOF__
