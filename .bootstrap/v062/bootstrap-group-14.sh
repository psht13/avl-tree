#!/usr/bin/env bash
set -euo pipefail
ROOT="${1:-smart-tv-remote}"
mkdir -p "$ROOT"

# From bootstrap-039.sh
mkdir -p "$ROOT/remoteapp/web"
cat >> "$ROOT/remoteapp/web/index.html" <<'__SRT_039_EOF__'
                <div id="modeTitle" class="mode-title">Навігація TV</div>
                <div id="modeHint" class="mode-hint">Автоматичний режим активний</div>
              </div>
              <div class="segments" role="tablist" aria-label="Режим керування">
                <button id="autoMode" class="segment" data-mode-preference="auto">Авто</button>
                <button id="dpadMode" class="segment" data-mode-preference="dpad">Кнопки</button>
                <button id="pointerMode" class="segment" data-mode-preference="pointer">Курсор</button>
              </div>
            </div>

            <div class="control-cluster">
              <div class="rocker" aria-label="Гучність">
                <button class="remote-command" data-key="KEY_VOLUP" data-requires-tv title="Гучність вище">⌃</button>
                <span class="rocker-label">VOL</span>
                <button class="remote-command" data-key="KEY_VOLDOWN" data-requires-tv title="Гучність нижче">⌄</button>
              </div>

              <div class="center-control">
                <div id="dpad" class="dpad">
                  <button class="dpad-button dpad-up remote-command" data-key="KEY_UP" data-requires-tv aria-label="Вгору">⌃</button>
                  <button class="dpad-button dpad-right remote-command" data-key="KEY_RIGHT" data-requires-tv aria-label="Праворуч">›</button>
                  <button class="dpad-button dpad-down remote-command" data-key="KEY_DOWN" data-requires-tv aria-label="Вниз">⌄</button>
                  <button class="dpad-button dpad-left remote-command" data-key="KEY_LEFT" data-requires-tv aria-label="Ліворуч">‹</button>
                  <button class="dpad-ok remote-command" data-key="KEY_ENTER" data-requires-tv aria-label="OK">OK</button>
                </div>

                <div id="joystick" class="joystick hidden" aria-label="Джойстик курсора. Перетягуй центр, коротко натисни для кліку.">
                  <span class="joystick-direction j-up">⌃</span>
                  <span class="joystick-direction j-right">›</span>
                  <span class="joystick-direction j-down">⌄</span>
                  <span class="joystick-direction j-left">‹</span>
                  <div id="stick" class="stick">OK</div>
                </div>
              </div>

              <div class="rocker" aria-label="Канали">
                <button class="remote-command" data-key="KEY_CHUP" data-requires-tv title="Наступний канал">⌃</button>
                <span class="rocker-label">CH</span>
                <button class="remote-command" data-key="KEY_CHDOWN" data-requires-tv title="Попередній канал">⌄</button>
              </div>
            </div>

            <div id="speedRow" class="speed-row hidden">
              <span class="speed-label">Швидкість курсора</span>
              <div class="speed-buttons">
                <button class="speed-btn" data-speed="slow">Повільно</button>
                <button class="speed-btn" data-speed="normal">Звичайно</button>
                <button class="speed-btn" data-speed="fast">Швидко</button>
              </div>
            </div>

            <div class="utility-row">
              <button class="icon-button accent remote-command dpad-return" data-key="KEY_RETURN" data-requires-tv title="Назад" aria-label="Назад"><svg class="icon"><use href="#icon-back"></use></svg></button>
              <button class="icon-button remote-command" data-key="KEY_MUTE" data-requires-tv title="Вимкнути або повернути звук" aria-label="Mute"><svg class="icon"><use href="#icon-mute"></use></svg></button>
              <button class="icon-button remote-command dpad-return" data-key="KEY_EXIT" data-requires-tv title="Вийти" aria-label="Вийти"><svg class="icon"><use href="#icon-exit"></use></svg></button>
            </div>

            <div class="quick-grid" aria-label="Швидкі дії">
              <button id="youtube" class="icon-button large brand-youtube" data-requires-tv title="YouTube" aria-label="Відкрити YouTube"><svg class="icon fill"><use href="#icon-youtube"></use></svg></button>
              <button id="browser" class="icon-button large brand-browser" data-requires-tv title="Браузер TV" aria-label="Відкрити браузер"><svg class="icon"><use href="#icon-browser"></use></svg></button>
              <button id="openKeyboard" class="icon-button large brand-keyboard" data-requires-tv title="Клавіатура" aria-label="Відкрити клавіатуру"><svg class="icon"><use href="#icon-keyboard"></use></svg></button>
              <button id="openVoice" class="icon-button large brand-mic" data-requires-tv title="Голосове введення" aria-label="Почати голосове введення"><svg class="icon"><use href="#icon-mic"></use></svg></button>
              <button id="netflix" class="icon-button large brand-netflix" data-requires-tv title="Netflix" aria-label="Відкрити Netflix"><svg class="netflix-logo-inline" viewBox="0 0 32 52" aria-hidden="true"><path fill="#b20710" d="M2 1h8v50H2zM22 1h8v50h-8z"/><path fill="#e50914" d="M9 1h8l13 50h-8z"/></svg></button>
              <button id="playstation" class="icon-button large brand-playstation" data-requires-tv title="PlayStation - останній HDMI" aria-label="Перемкнутися на PlayStation через HDMI"><svg class="playstation-logo-inline" viewBox="0 0 72 52" aria-hidden="true"><path fill="#e8f1ff" d="M28 3c13 2 22 7 22 14 0 6-5 9-13 9V12c0-3-2-5-5-6v37l-9 3V8c0-4 1-6 5-5z"/><path fill="#e8f1ff" d="M6 38c6-5 15-8 23-10v6c-7 2-11 4-13 6-2 2 0 3 4 2l9-3v6l-14 4C5 52-2 47 6 38zm32-8c11-2 22-1 27 3 5 4 2 8-7 11l-20 6v-6l17-5c4-1 5-3 2-4-3-1-10 0-19 2z"/></svg></button>
            </div>

            <div class="media-row">
              <button class="icon-button remote-command" data-key="KEY_REWIND" data-requires-tv title="Перемотати назад" aria-label="Перемотати назад"><svg class="icon fill"><use href="#icon-rewind"></use></svg></button>
              <button id="playPause" class="icon-button accent" data-requires-tv title="Пауза" aria-label="Пауза"><svg class="icon fill"><use id="playPauseUse" href="#icon-pause"></use></svg></button>
              <button class="icon-button remote-command" data-key="KEY_FF" data-requires-tv title="Перемотати вперед" aria-label="Перемотати вперед"><svg class="icon fill"><use href="#icon-forward"></use></svg></button>
            </div>

            <div id="pointerNote" class="mode-note"><strong>Samsung:</strong> програма може автоматично визначати браузер. <strong>Google TV:</strong> без додаткової програми на TV джойстик працює як швидка D-pad навігація, а не як системна миша.</div>
          </div>
        </article>
      </section>

      <aside class="stack">
        <article id="voiceCard" class="card">
          <div class="card-body">
            <h2 class="card-title">Клавіатура і голос</h2>
            <p class="card-copy">Спочатку активуй поле на TV курсором або OK. Потім введи чи продиктуй текст тут.</p>
            <div class="voice-layout">
              <div class="voice-toolbar">
                <select id="speechLanguage" aria-label="Мова диктування">
                  <option value="uk-UA">Українська</option>
                  <option value="ru-RU">Російська</option>
__SRT_039_EOF__
