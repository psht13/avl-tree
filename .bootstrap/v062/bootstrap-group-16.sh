#!/usr/bin/env bash
set -euo pipefail
ROOT="${1:-smart-tv-remote}"
mkdir -p "$ROOT"

# From bootstrap-042.sh
mkdir -p "$ROOT/remoteapp/web"
cat >> "$ROOT/remoteapp/web/index.html" <<'__SRT_042_EOF__'
          showToast(result.message || (result.confirmed ? 'Застосунок відкрито' : 'Команду запуску надіслано'), !result.confirmed);
          if (result.confirmed) {
            const mode = state.provider === 'samsung' && app === 'browser' ? 'pointer' : 'dpad';
            state.controlModeHint = mode;
            if (modePreference === 'auto') setEffectiveMode(mode);
            if (app === 'youtube' || app === 'netflix') resetPlayPause(true);
          }
          await refreshState();
        } catch (error) {
          showToast(error.message, true);
        }
      }

      elements.browser.addEventListener('click', () => launchApp('browser'));
      elements.youtube.addEventListener('click', () => launchApp('youtube'));
      elements.netflix.addEventListener('click', () => launchApp('netflix'));
      elements.playstation.addEventListener('click', () => launchApp('playstation'));

      function openKeyboard() {
        elements.voiceCard.scrollIntoView({ behavior: 'smooth', block: 'center' });
        setTimeout(() => elements.text.focus(), 380);
      }
      elements.openKeyboard.addEventListener('click', openKeyboard);
      elements.focusText.addEventListener('click', () => elements.text.focus());

      elements.playPause.addEventListener('click', async () => {
        const key = mediaPlaying ? 'KEY_PAUSE' : 'KEY_PLAY';
        const sent = await command('/api/key', { key });
        if (sent) resetPlayPause(!mediaPlaying);
      });

      elements.sendText.addEventListener('click', async () => {
        const text = elements.text.value.trim();
        if (!text) return showToast('Спочатку введи або надиктуй текст', true);
        const sent = await command('/api/text', { text });
        if (sent) showToast('Текст надіслано в активне поле TV.');
      });
      elements.text.addEventListener('keydown', (event) => {
        if ((event.ctrlKey || event.metaKey) && event.key === 'Enter') elements.sendText.click();
      });

      function speechConstructor() { return window.SpeechRecognition || window.webkitSpeechRecognition || null; }
      function stopRecognition() { if (recognition) recognition.stop(); }
      function startRecognition() {
        if (listening) return stopRecognition();
        const Recognition = speechConstructor();
        if (!Recognition) {
          if (window.NativeVoice && typeof window.NativeVoice.start === 'function') {
            elements.voiceStatus.textContent = 'Відкриваю системне голосове введення…';
            window.NativeVoice.start(elements.speechLanguage.value);
            return;
          }
          elements.voiceStatus.textContent = 'Голосове розпізнавання недоступне на цьому пристрої.';
          return;
        }
        recognition = new Recognition();
        recognition.lang = elements.speechLanguage.value;
        recognition.interimResults = true;
        recognition.continuous = false;
        recognition.maxAlternatives = 1;
        let baseText = elements.text.value.trim();
        let finalText = '';
        recognition.onstart = () => {
          listening = true;
          elements.voice.classList.add('danger', 'selected');
          elements.voiceStatus.textContent = 'Слухаю…';
        };
        recognition.onresult = (event) => {
          let interim = '';
          for (let i = event.resultIndex; i < event.results.length; i++) {
            const transcript = event.results[i][0].transcript;
            if (event.results[i].isFinal) finalText += transcript;
            else interim += transcript;
          }
          const recognized = (finalText || interim).trim();
          if (recognized) elements.text.value = [baseText, recognized].filter(Boolean).join(baseText ? ' ' : '');
          elements.voiceStatus.textContent = interim || 'Розпізнаю…';
        };
        recognition.onerror = (event) => { elements.voiceStatus.textContent = `Помилка: ${event.error || 'невідома'}`; };
        recognition.onend = () => {
          listening = false;
          elements.voice.classList.remove('danger', 'selected');
          if (!elements.voiceStatus.textContent.startsWith('Помилка')) elements.voiceStatus.textContent = 'Готово. Перевір текст і надішли на TV.';
        };
        try { recognition.start(); } catch (error) { showToast(error.message, true); }
      }
      elements.voice.addEventListener('click', startRecognition);
      elements.openVoice.addEventListener('click', () => {
        elements.voiceCard.scrollIntoView({ behavior: 'smooth', block: 'center' });
        setTimeout(startRecognition, 380);
      });

      elements.disconnect.addEventListener('click', async () => {
        await command('/api/disconnect', {});
        refreshState();
      });
      elements.forget.addEventListener('click', async () => {
        if (!confirm('Забути збережений телевізор, IP і токен дозволу?')) return;
        try {
          await api('/api/forget', {});
          elements.ip.value = '';
          showToast('Збережене підключення видалено.');
          refreshState();
        } catch (error) { showToast(error.message, true); }
      });

      function updateJoystick(event) {
        const rect = elements.joystick.getBoundingClientRect();
        const centerX = rect.left + rect.width / 2;
        const centerY = rect.top + rect.height / 2;
        const maxRadius = rect.width * .32;
        let dx = event.clientX - centerX;
        let dy = event.clientY - centerY;
        const distance = Math.hypot(dx, dy);
        if (distance > maxRadius) {
          dx = dx / distance * maxRadius;
          dy = dy / distance * maxRadius;
        }
        const magnitude = Math.min(1, Math.hypot(dx, dy) / maxRadius);
        vector = { x: dx / maxRadius, y: dy / maxRadius, magnitude };
        if (magnitude > .14) joystickMoved = true;
        elements.stick.style.transform = `translate(${dx}px, ${dy}px)`;
      }

      function resetJoystick() {
        joystickPointerId = null;
        vector = { x: 0, y: 0, magnitude: 0 };
        elements.joystick.classList.remove('dragging');
        elements.stick.style.transform = 'translate(0, 0)';
        if (moveTimer) clearInterval(moveTimer);
        moveTimer = null;
      }

      async function sendMoveTick() {
        if (movePending || vector.magnitude < .12 || !state.connected) return;
        const multiplier = speedMultiplier[speed] || speedMultiplier.normal;
        const curve = Math.pow(vector.magnitude, 1.55);
        const x = Math.round(vector.x * curve * multiplier * 68);
        const y = Math.round(vector.y * curve * multiplier * 68);
        if (!x && !y) return;
        movePending = true;
        try { await api('/api/move', { x, y }); }
        catch (error) { showToast(error.message, true); resetJoystick(); }
        finally { movePending = false; }
      }

      elements.joystick.addEventListener('pointerdown', (event) => {
        if (!state.connected) return;
        joystickPointerId = event.pointerId;
        joystickStartedAt = performance.now();
        joystickMoved = false;
        elements.joystick.setPointerCapture(event.pointerId);
        elements.joystick.classList.add('dragging');
        updateJoystick(event);
__SRT_042_EOF__

# From bootstrap-043.sh
mkdir -p "$ROOT/remoteapp/web"
cat >> "$ROOT/remoteapp/web/index.html" <<'__SRT_043_EOF__'
        moveTimer = setInterval(sendMoveTick, 52);
        sendMoveTick();
      });
      elements.joystick.addEventListener('pointermove', (event) => {
        if (event.pointerId === joystickPointerId) updateJoystick(event);
      });
      function finishJoystick(event) {
        if (event.pointerId !== joystickPointerId) return;
        const click = !joystickMoved && performance.now() - joystickStartedAt < 420;
        resetJoystick();
        if (click) command('/api/click', {});
      }
      elements.joystick.addEventListener('pointerup', finishJoystick);
      elements.joystick.addEventListener('pointercancel', resetJoystick);
      elements.joystick.addEventListener('contextmenu', (event) => event.preventDefault());

      window.__nativeVoiceResult = (text) => {
        if (text) {
          const base = elements.text.value.trim();
          elements.text.value = [base, text].filter(Boolean).join(base ? ' ' : '');
          elements.voiceStatus.textContent = 'Готово. Перевір текст і надішли на TV.';
          openKeyboard();
        }
      };
      window.__nativeVoiceError = (message) => {
        elements.voiceStatus.textContent = message || 'Голосове введення скасовано.';
      };

      applyModePreference(modePreference, false);
      setSpeed(speed);
      resetPlayPause(true);
      refreshState();
      setInterval(refreshState, 900);
    })();
  </script>
</body>
</html>
__SRT_043_EOF__
