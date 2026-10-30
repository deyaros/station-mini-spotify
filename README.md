# Станция Мини: Spotify + Алиса + AirPlay

Яндекс Станция Мини 2 с root превращается в нормальную колонку для Spotify:

- **Spotify Connect через официальный [Spotify Soloist](https://developer.spotify.com/documentation/soloist/concepts/overview)** — без librespot и без обхода защиты, поэтому без риска для аккаунта.
- **Голосом через Алису:** «Алиса, включи мои лайки», «…плейлист <название>» (ищет среди ваших плейлистов), «…песню / группу / альбом …», «пауза», «дальше», «назад», «перемешай».
- **AirPlay 2** с iPhone и Mac.
- **AirPlay и Spotify уступают друг другу:** старт AirPlay ставит Spotify на паузу, запуск Spotify обрывает AirPlay-сессию.
- **Алиса работает как раньше** (свет, вопросы, таймеры) и может говорить поверх музыки.
- **Пока Алиса слушает, музыка приглушается** до 25 % — команда не тонет в Spotify или AirPlay.
- Всё стартует при включении, сторож раз в 30 секунд поднимает упавшее.

Проверено на Станции Мини 2 (`yandexmini_2`, прошивка 0.369.1.46, Quasar 3.21).

## Как это устроено

```
Spotify (телефон) ──Connect──▶ Soloist (arm64, официальный) ─▶ apulse ─▶ snd-aloop
                                                                              │
Алиса ──▶ soloist-bridge ──▶ search_and_play.sh ──▶ Web API (через VPN-прокси) │
              │                                                                ▼
              └──▶ soloist ctl (play/pause/...)          arecord | aplay (32-bit) ─▶ dmix ─▶ динамик
                                                                              ▲
iPhone/Mac ──AirPlay 2──▶ shairport-sync + nqptp + avahi (32-bit) ────────────┘
```

Неочевидные места:

- **32-битная система, 64-битный Soloist.** У Мини 2 ядро aarch64, а система armhf. Soloist запускается
  через загрузчик и библиотеки из официальных пакетов Debian 13 arm64 (`lib64/`), а `bin/soloist` —
  обёртка над `soloist.bin`.
- **Звук через виртуальную карту.** 64-битный libasound, подключившись к общему dmix, не пускает туда
  32-битных клиентов (Алису, AirPlay): `unable to create IPC shm instance`. Поэтому Soloist играет в
  `snd-aloop`, а в dmix звук переносит обычный 32-битный `arecord | aplay`. Через «пустое» устройство
  (`null` + труба) не работает: у него нет часов, Soloist сбивается.
- **apulse** не конвертирует формат, а Soloist отдаёт float32 — отсюда `plughw:Loopback,0,0`.
- **apulse пропатчен** (`patches/apulse-flush.patch`, сборка `tools/build-apulse.sh`): в оригинале
  сброс буфера — заглушка, поэтому при переключении трека сначала звучал хвост старого (до ~1 с), а
  после паузы ~1,5 с доигрывал буфер ALSA. Теперь сброс очищает оба буфера, пауза ставит на паузу и
  ALSA.
- **Память.** У колонки ~240 МБ без подкачки, а Soloist растёт на 2–3 МБ в минуту, пока играет. Кеш
  нельзя ограничить меньше 100 МБ, поэтому он в tmpfs на 4 МБ (Soloist переходит на потоковое
  воспроизведение), Soloist — первый кандидат для OOM killer, резерв ядра поднят до 8 МБ, а сторож
  перезапускает Soloist, когда свободно меньше 40 МБ и ничего не играет (меньше 25 МБ — в любом
  случае). Без этого колонка через ~50 минут музыки висела целиком, вместе с Алисой.
- **Web API Spotify отвечает 403 на российские IP** («unavailable in this country»), поэтому поиск и
  список плейлистов идут через SOCKS5 (`192.168.8.111:10808`) — свой VPN, см. `nas/`. Само
  воспроизведение Soloist работает и с российского IP.
- **AirPlay** — бинарники из дополнения [spotiya](https://github.com/klockky/spotiya) (MIT), запущенные
  отдельно от него. shairport-sync ждёт готовности NQPTP, сторож перезапускает AirPlay, если avahi
  перезапустился после shairport (иначе служба молча пропадает из сети).
- **Приглушение.** Spotify (32-битный `aplay`) и AirPlay играют в PCM `media` из
  `/data/opt/media/.asoundrc`: системный `default` плюс свой регулятор `Media Duck`. `duck.sh` читает
  состояния Алисы через `alice-text` (из вики hackalice, CC BY 4.0; `tools/build-alice-text.sh`) и
  опускает регулятор до 25 %, пока она слушает (`@state 1`), до освобождения (`@state 0`), но не
  дольше 15 с. Громкость самой Алисы не меняется.
- **«Лайки»** — это `spotify:user:<id>:collection`, id берётся из журнала Soloist. Для плейлистов нужен
  разовый вход с правами только на чтение плейлистов (`tools/spotify_oauth.py`).

## Чего здесь нет

- **Ключей.** `keys.env` создаётся по `keys.env.example` и в репозиторий не попадает.
- **Soloist.** Его каждый скачивает сам в кабинете Spotify for Developers (Linux ARM64).
- **Кода [Horohi/soloist-station-lite](https://github.com/Horohi/soloist-station-lite)** (голосовой
  мостик и скрипт поиска): у того репозитория нет лицензии. `tools/fetch-bridge.sh` скачивает его на
  закреплённом коммите, накладывает `speaker/soloist/search_and_play.patch` и собирает мостик из
  исходника. Патч убирает отправку запросов к API на чужой IP, переводит поиск на свой прокси и
  добавляет лайки и плейлисты.
- **Бинарников.** Библиотеки Debian и AirPlay-программы скачиваются и сверяются с контрольными суммами.

## Установка

Нужно заранее:

1. Root и SSH на колонке и отключённые обновления — по вики [hackalice.me](https://hackalice.me/start/root/).
2. [yse / Entware](https://hackalice.me/start/packages/) на колонке.
3. На компьютере: `adb`, `curl`, `python3`, `bsdtar`, `xz`, `git`, `docker` (для сборки мостика).
4. В [Spotify for Developers](https://developer.spotify.com/dashboard):
   - скачать Soloist для Linux ARM64 и получить ключ устройства `spak_…`;
   - создать приложение с **Web API** и Redirect URI `http://127.0.0.1:8888/callback`
     (именно `127.0.0.1`: адреса с `localhost` Spotify отклоняет как «Unsafe»).
5. SOCKS5-прокси с не российским выходом, доступный колонке (пример для NAS — `nas/`), и его адрес в
   `CURL_OPTS` в `search_and_play.patch`, если он не `192.168.8.111:10808`.

Затем:

```sh
cp keys.env.example keys.env          # вписать SPAK, CLIENT_ID, CLIENT_SECRET
python3 tools/spotify_oauth.py keys.env   # открыть ссылку, нажать «Согласен» -> REFRESH_TOKEN
./deploy.sh 192.168.1.50 ~/Downloads/soloist_release_arm64.tar.gz keys.env
```

После установки один раз выберите «Станция Мини» в приложении Spotify — колонка войдёт под вашим
аккаунтом и запомнит вход.

## Управление на колонке

```sh
/data/opt/soloist/soloist.sh start|stop|restart|status   # Soloist, мостик, звук, охранник AirPlay
/data/opt/airplay/airplay.sh start|stop|restart|kick|status
/data/opt/soloist/bin/soloist ctl -w 127.0.0.1:9090 now|play|pause|next|...
```

Журналы: `/tmp/soloist.log`, `/tmp/soloist-bridge.log`, `/tmp/soloist-search.log`, `/tmp/airplay.log`,
`/tmp/airplay-watchdog.log`, `/tmp/airplay-guard.log`.

Удаление: `soloist.sh stop`, `airplay.sh stop`, убрать `/etc/init.d/S99soloist`, `S99airplay`,
`S99zzairplaywd` (корень `mount -o remount,rw /`) и папки `/data/opt/soloist`, `/data/opt/airplay`.

## Подводные камни

- Мостик отправляет в Spotify любую фразу «Алиса, включи …», кроме света, розеток, таймеров и т. п.
  («включи радио» тоже уйдёт в Spotify).
- glibc 2.41 на ядре 4.9 пробует `rseq`/`clone3` и ядро пишет об этом в `dmesg`; `rseq` отключён через
  `GLIBC_TUNABLES`, остальное безвредно.
- Если колонка была в Spotify через librespot (spotiya и т. п.), уберите его: в чате hackalice
  сообщали о деактивации аккаунтов за librespot.

## Благодарности

- [hackalice.me](https://hackalice.me) и чат сообщества — root, yse, разбор прошивки.
- [Horohi/soloist-station-lite](https://github.com/Horohi/soloist-station-lite) — голосовой мостик.
- [klockky/spotiya](https://github.com/klockky/spotiya) — сборка AirPlay 2 под Мини.
- [i-rinat/apulse](https://github.com/i-rinat/apulse) (MIT) — PulseAudio API поверх ALSA.
- `alice-text` и идея приглушения — рецепт Spotify для Станции 2 в
  [вики hackalice](https://hackalice.me/recipes/spotify/) (CC BY 4.0).

Код этого репозитория — MIT (см. `LICENSE`); сторонние компоненты — под своими лицензиями.
