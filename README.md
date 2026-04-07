# Docker Compose: Synapse + Element + Element Call + LiveKit + PostgreSQL + Caddy

В репозитории **нет** **`.env`** и **сгенерированных конфигов** (`caddy/config/Caddyfile`, `element/config/*.json`, `synapse-admin/config/config.json`, `livekit/config/livekit.yaml`, `coturn/config/turnserver.conf` и т.д.) — они создаются на сервере. После **`git clone`** задайте **`.env`** (**`./scripts/bootstrap-env.sh`** или **`cp .env.example .env`**), затем профиль **`init`** и **`docker compose up -d`**. Лицензия: [MIT](LICENSE).

Поддерживается схема с **несколькими поддоменами**. Все перечисленные в `.env` имена должны иметь **DNS A/AAAA** на IP сервера; для Let’s Encrypt должны быть доступны **80/443** из интернета.

Ожидаемые имена (пример **chat.example.net**):

- `matrix.chat.example.net` — Synapse (`MATRIX_DOMAIN`)
- `element.chat.example.net` — Element Web (`ELEMENT_DOMAIN`)
- `admin.chat.example.net` — Synapse Admin (`ADMIN_DOMAIN`)
- `auth.chat.example.net` — `AUTH_DOMAIN` (заглушка; под MAS/OIDC позже)
- `call.chat.example.net` — Element Call (`CALL_DOMAIN`)
- `rtc.chat.example.net` — LiveKit + JWT (`RTC_DOMAIN`)
- `turn.chat.example.net` — TURN (`TURN_DOMAIN`), **coturn** в стеке по умолчанию (см. раздел TURN)

## Быстрый старт

1. **DNS:** записи **A** (или **AAAA**) на **все семь** хостов выше, включая **`TURN_DOMAIN`**.

2. **Конфиг:**
   - **Автоматически** (базовый домен, почта, внешний IP и секреты):  
     `./scripts/bootstrap-env.sh` — создаст **`.env`** из **`templates/env.bootstrap.template`** (поддомены вида `matrix.<ваш-домен>`, …).
   - **Вручную:** скопируйте **`.env.example`** в **`.env`** и заполните переменные (полный список и комментарии — в **`.env.example`**).

3. **Сгенерировать конфиги на диск** (после первого клона или при смене `.env` / `templates/*`). Обычный **`docker compose up`** **не** поднимает init-контейнеры (профиль **`init`**):
   ```bash
   docker compose --profile init up \
     livekit-init element-init element-call-init synapse-admin-init caddy-init coturn-init
   ```
   **Без** `-d` и **без** `--abort-on-container-exit`: все init стартуют **параллельно**, команда **ждёт**, пока **каждый** контейнер завершится, и только тогда выходит. Так конфиги успевают записаться во все каталоги.

   Флаг **`--abort-on-container-exit`** здесь **не используйте**: при нём первый завершившийся init **останавливает** остальные — часть конфигов не появится.

   Альтернатива — по одному: `docker compose --profile init run --rm element-init` и т.д.

   Не рекомендуется **`docker compose --profile init up -d`** без списка сервисов: рабочие контейнеры и init могут подняться **параллельно**, и конфиг ещё не успеют записаться на диск.

4. **Запуск боевого стека:**
   ```bash
   docker compose up -d
   ```
   Первый старт Synapse может занять несколько минут. Логи: `docker compose logs -f synapse`.

5. **Первый администратор:**
   ```bash
   docker compose exec synapse register_new_matrix_user -c /data/homeserver.yaml -a -u admin http://localhost:8008
   ```
   Вход в клиент: **`https://ELEMENT_DOMAIN`** (не matrix). Homeserver: **`https://MATRIX_SERVER_NAME`** (если задан отдельно от `MATRIX_DOMAIN` — обычно apex) или **`https://MATRIX_DOMAIN`**; Client API всегда на **`https://MATRIX_DOMAIN`**.

## Разделение по поддоменам

| Переменная | Пример | Назначение |
|------------|--------|------------|
| `MATRIX_DOMAIN` | `matrix.chat.example.net` | Хост Synapse в Caddy: HTTPS Client API (`/_matrix`, `/_synapse`), `public_baseurl` в Synapse |
| `MATRIX_SERVER_NAME` | `matrix.chat.example.net` или apex | Суффикс MXID `@user:…` и `server_name` в Synapse. По умолчанию = `MATRIX_DOMAIN`. Если задать apex отдельно от `MATRIX_DOMAIN`, **caddy-init** добавляет vhost (**`templates/Caddyfile.matrix-apex.template`**): **`server`** — статический `m.server`; **`client`** — **прокси на Synapse** с `Host: MATRIX_DOMAIN`, чтобы в ответе были MSC4143 / MatrixRTC (Element X). Нужен **DNS на apex**. |
| `ELEMENT_DOMAIN` | `element.chat.example.net` | Element Web — в браузере: `https://element.chat.example.net/` |
| `CALL_DOMAIN` | `call.chat.example.net` | Element Call (`element_call.url`) |
| `RTC_DOMAIN` | `rtc.chat.example.net` | `/livekit/jwt`, `/livekit/sfu` |
| `ADMIN_DOMAIN` | `admin.chat.example.net` | [Synapse Admin](https://github.com/Awesome-Technologies/synapse-admin) — вход учётной записью **администратора** Synapse; API остаётся на **`MATRIX_DOMAIN`** (`restrictBaseUrl` в `synapse-admin/config/config.json`) |
| `AUTH_DOMAIN` | `auth.chat.example.net` | Заглушка 501 — например MAS/OIDC позже |
| `ENABLE_USER_DIRECTORY_SEARCH` | `true` | В **`homeserver.yaml`**: поиск пользователей своего сервера в Element (`user_directory.search_all_users`). Для закрытых инсталлов можно `false`. |
| `TURN_*` | см. `.env.example` | Секрет и домен для Synapse `turn_uris` / coturn; см. раздел ниже. |

**Бот/скрипты:** URL Client API — **`https://MATRIX_DOMAIN`** (в Element как `base_url`). Утилиты **`scripts/backup_pg.sh`**, **`scripts/register_users.sh`** — см. раздел «Данные и бэкапы».

## Звонки (MatrixRTC)

Образ **Element Synapse** (`ghcr.io/element-hq/synapse`), **LiveKit**, **lk-jwt-service**, **Element Call**. URL JWT в Synapse и в `.well-known`: `https://RTC_DOMAIN/livekit/jwt`. Переменная `LIVEKIT_URL` у `lk-jwt`: `wss://RTC_DOMAIN/livekit/sfu`.

**Файрвол:** значения как в **`.env`**: **`LIVEKIT_UDP_PORT_START`–`LIVEKIT_UDP_PORT_END`** (UDP), TCP **`LIVEKIT_PORT`** и **`LIVEKIT_TCP_PORT`** (по умолчанию 7880/7881); те же переменные попадают в `livekit/config/livekit.yaml` и в `ports` у сервиса `livekit`.

### TURN (coturn) за NAT

Классическая VoIP-цепочка Synapse (если клиент не может установить прямое соединение). **MatrixRTC / LiveKit** остаётся как есть; TURN дополняет 1:1 VoIP. **coturn** входит в обычный **`docker compose up -d`** (отдельного профиля нет).

1. В **`.env`**: сильный **`TURN_SHARED_SECRET`** (например `openssl rand -hex 32`), **`TURN_DOMAIN`** (DNS **A/AAAA** на **публичный** IP), **`TURN_EXTERNAL_IP`** (= этот публичный IPv4). За **маскарадингом на том же хосте** при необходимости задайте **`TURN_INTERNAL_IP`** (локальный адрес интерфейса сервера) — в coturn будет `external-ip=внутренний/внешний`.
2. На роутере/файрволе пробросьте на сервер: **UDP и TCP** на порт **`COTURN_LISTENING_PORT`** (по умолчанию **3478**), а также **UDP (и при желании TCP)** на диапазон **TURN_MIN_PORT–TURN_MAX_PORT** (`49160–49260` по умолчанию). Тот же порт используется в `turn_uris` в Synapse.
3. **coturn** в compose с **`network_mode: host`** — ориентируйтесь на **Linux**-сервер (на Docker Desktop поведение может отличаться).
4. Конфиг **`coturn/config/turnserver.conf`** создаёт сервис **`coturn-init`** (профиль **`init`**, как у остальных генераторов): **`coturn/init.sh`**, шаблон **`templates/turnserver.conf.template`**. После смены TURN в **`.env`**: **`docker compose --profile init run --rm coturn-init`**, затем **`docker compose up -d --force-recreate coturn synapse`**.
5. Проверка: в Element «Настройки → Помощь и о программе → аккаунт» при тесте звонка; в логах Synapse при запросе **`/voip/turnServer`**.

## Что внутри

| Сервис | Назначение |
|--------|------------|
| **coturn** | TURN/STUN для VoIP Synapse (`network_mode: host`) |
| `postgres` | БД Synapse |
| `synapse` | Homeserver |
| `livekit` | SFU |
| `lk-jwt` | JWT для LiveKit |
| `element` | Element Web |
| `synapse-admin` | Веб-админка Synapse на `ADMIN_DOMAIN` |
| `element-call` | SPA на `CALL_DOMAIN` |
| `caddy` | TLS и маршрутизация по vhost |
| `*-init` | Генерация конфигов (профиль **`init`**): **`element/init.sh`**, **`element-call/init.sh`**, **`synapse-admin/init.sh`**, **`livekit/init.sh`**, **`caddy/init.sh`**, **`coturn/init.sh`** (сервис **`coturn-init`**) → каталоги **`*/config/`** |

## Переменные `.env` (кроме доменов)

Полный перечень с комментариями — в **`.env.example`**. Кратко:

| Переменная | Описание |
|------------|----------|
| `ACME_EMAIL` | Email для Let’s Encrypt |
| `POSTGRES_USER` / `POSTGRES_DB` | Пользователь и БД PostgreSQL (по умолчанию `synapse` / `synapse`); аргументы `initdb` — в **`docker-compose.yml`** |
| `POSTGRES_PASSWORD` | Пароль БД |
| `SYNAPSE_REPORT_STATS` | `yes` / `no` |
| `LIVEKIT_API_KEY` / `LIVEKIT_API_SECRET` | Ключи в `livekit.yaml` и у `lk-jwt` |
| `LIVEKIT_PORT` / `LIVEKIT_TCP_PORT` / `LIVEKIT_UDP_PORT_*` | Порты LiveKit (compose + YAML + `{$LIVEKIT_PORT}` в Caddy → `livekit`) |
| `COTURN_LISTENING_PORT` | Порт coturn и `turn:` в Synapse (по умолчанию `3478`) |
| `ELEMENT_*` / `ELEMENT_CALL_*` | Бренды, флаги и тайминги в JSON Element / Element Call |

## admin / auth

**`ADMIN_DOMAIN`** обслуживает контейнер **`synapse-admin`** (образ `awesometechnologies/synapse-admin`). Вход — логин и пароль **администратора** Synapse (созданного с **`register_new_matrix_user -a`** или эквивалентом). Запросы к API идут на **`https://MATRIX_DOMAIN`**; в **`synapse-admin/config/config.json`** задаётся **`restrictBaseUrl`**, чтобы нельзя было сменить homeserver в UI. После смены **`MATRIX_DOMAIN`**: **`docker compose --profile init run --rm synapse-admin-init`**, затем **`docker compose up -d synapse-admin`**.

Для **`AUTH_DOMAIN`** в `templates/Caddyfile.template` по-прежнему ответ **501** (под MAS/OIDC позже). Рабочий Caddy — **`caddy/config/Caddyfile`** (генерирует **`caddy-init`**).

## Связь с `deploy/Caddyfile`

Логика маршрутов **LiveKit / JWT** такая же, как в [../deploy/Caddyfile](../deploy/Caddyfile), но хосты вынесены по переменным (`RTC_DOMAIN`, `CALL_DOMAIN`).

## Обновление образов

```bash
docker compose pull
docker compose up -d
```

## Данные и бэкапы

На хосте (рядом с `docker-compose.yml`):

| Путь | Содержимое |
|------|------------|
| **`postgres/data/`** | файлы PostgreSQL |
| **`synapse/data/`** | `homeserver.yaml`, медиа и состояние Synapse (`/data` в контейнере) |
| **`caddy/data/`** | сертификаты и файловое хранилище Caddy (`/data` в контейнере) |
| **`caddy/config/`** | сгенерированный **`Caddyfile`**, подкаталог **`autosave/`** — служебный конфиг Caddy (`/config` в контейнере) |
| **`element/config/`**, **`element-call/config/`**, **`synapse-admin/config/`**, **`livekit/config/`**, **`coturn/config/`** | JSON/YAML/конфиги, которые пишут `*-init` |

Каталоги **`element/data/`**, **`element-call/data/`**, **`livekit/data/`**, **`coturn/data/`** зарезервированы под будущие данные на хосте (сейчас пустые).

Посмотреть или скопировать конфиг Synapse:

```bash
docker compose exec synapse cat /data/homeserver.yaml | less
docker cp "$(docker compose ps -q synapse)":/data/homeserver.yaml ./homeserver.yaml
```

Локальная копия на диске: **`synapse/data/`** (тот же том, что смонтирован в `/data` у контейнера `synapse`).

Дамп БД в gzip: **`./scripts/backup_pg.sh`** (по умолчанию каталог **`backups/`** в корне проекта). Массовая регистрация из **`users.txt`**: **`./scripts/register_users.sh`**. Случайные секреты в **`.env`**: **`./scripts/secrets_generate.sh`** (перед первым `up` или при ротации; при смене **`POSTGRES_PASSWORD`** нужна согласованность с уже созданной БД).

**Миграция со старой схемы** (`Docker volume` + общий `./data/`): остановите стек, скопируйте содержимое томов в **`postgres/data`**, **`synapse/data`**, **`caddy/data`** (и при необходимости файлы из старого **`data/`** в соответствующие **`*/config`**), затем `docker compose up -d`. Старые именованные тома можно удалить после проверки (`docker volume rm …`).

## Element: «Не удаётся связаться с сервером» (TLS / CORS / URL)

Клиент на **`element.*`** обращается к API на **`matrix.*`** (другой origin). Нужны **TLS** на обоих хостах, ответ по `https://MATRIX_DOMAIN/_matrix/client/versions` из браузера и **CORS** (в **`caddy/config/Caddyfile`**: `OPTIONS` и `Access-Control-*` на SNI Synapse).

На странице `https://element.…/login` откройте **F12 → Console** и выполните:

```js
fetch("https://matrix.chat.example.net/_matrix/client/versions")
  .then((r) => r.json())
  .then(console.log)
  .catch(console.error);
```

Должен вывестись объект с `versions`. Если `TypeError` / `Failed to fetch` — блокировка сети, расширение или не тот URL (в **`element-config.json`** должен быть **именно** `matrix.chat.…` с **https**).

В **`element-config.json`** задано **`disable_custom_urls: true`**, чтобы не подхватывался старый или ошибочный homeserver. После смены шаблона: `docker compose --profile init run --rm element-init && docker compose up -d element`.

Если в консоли **`matrix.example.net`** и **`ERR_NAME_NOT_RESOLVED`** — домен без `chat` не совпадает с вашим **`MATRIX_DOMAIN`**. В **`.env`** должно быть **`MATRIX_DOMAIN=matrix.chat.example.net`** (как в Synapse `server_name`). Проверка: `grep MATRIX_DOMAIN .env` и **`cat element/config/element-config.json`** — в `default_server_config`/`room_directory` везде **полное** имя. Затем снова **`docker compose --profile init run --rm element-init`** и **`docker compose up -d element`**. В браузере для **`element.chat.…`** удалите **данные сайта** (или инкогнито): в IndexedDB/localStorage часто остаётся старый `hs_url`.

Element сначала запрашивает **`/config.<hostname>.json`**, и только при 404 — **`/config.json`**. Старый **`/config.json`** часто висит в **Service Worker**, из‑за этого в консоли снова **`matrix.example.net`** и **`default_server_name`**, хотя на диске уже правильный JSON. В compose **`element-init`** кладёт копию в **`element/config/config.${ELEMENT_DOMAIN}.json`**, контейнер монтирует её в **`/app/`**. После обновления: **`docker compose --profile init run --rm element-init && docker compose up -d element`**. В браузере: **Application → Clear storage** (включая service workers) или инкогнито.

## Один домен `matrix.chat…` (проще всего)

Когда **`MATRIX_DOMAIN` = `MATRIX_SERVER_NAME`** (в **`.env`** обе строки одинаковые, например **`matrix.chat.example.net`**): хост API, `server_name` в Synapse и суффикс MXID совпадают; отдельный vhost на apex не нужен.

Проверка: **`docker compose exec synapse grep '^server_name:' /data/homeserver.yaml`** и **`grep public_baseurl`** — `server_name` = **`MATRIX_SERVER_NAME`**, `public_baseurl` = **`https://MATRIX_DOMAIN`**.

## Apex для MXID (`@user:example.net`), API на `matrix.…`

Если **`MATRIX_SERVER_NAME`** = apex (например **`chat.example.net`**), а **`MATRIX_DOMAIN`** = **`matrix.chat.example.net`**: в Synapse **`server_name`** и MXID — на apex, **`public_baseurl`** — на `https://matrix.chat.example.net`. Нужны **DNS A/AAAA на apex**; на apex **`/.well-known/matrix/client`** проксируется к Synapse (как на matrix-хосте), иначе клиенты вроде Element X не видят RTC в well-known. Затем **`docker compose --profile init run --rm caddy-init`** и **`docker compose up -d --force-recreate caddy`**. Новая установка: задайте переменные **до** первого старта Synapse. Смена `server_name` на уже заполненной БД — по [документации Synapse](https://element-hq.github.io/synapse/latest/), не «правкой одной строки».

### Уже развёрнут Synapse с `server_name: matrix.example.net`

Просто поменять строку в **`homeserver.yaml`** **нельзя** — в Postgres уже записаны события и пользователи под старым именем сервера.

- **Тестовый сервер, данные не жалко:** полный сбой БД и конфига Synapse, новый `server_name` с нуля:
  ```bash
  docker compose down
  docker volume rm matrix_postgres-data matrix_synapse-data   # только если ещё использовали именованные тома; имена: docker volume ls
  ```
  В **`.env`**: только **`MATRIX_DOMAIN=matrix.chat.example.net`**, без второго домена; **`docker compose up -d`**. Заново создайте пользователей (**регистрация** или **`register_new_matrix_user`**). Затем **`docker compose --profile init run --rm element-init && docker compose up -d element lk-jwt caddy`**.

- **Продакшен с ценными данными:** смотрите официальную документацию Synapse по смене имени сервера / миграции (вне этого репозитория) или оставьте текущий `server_name` и второй хост в DNS+Caddy.

Запросы **`msc2965/auth_metadata`** с **404** без OIDC — нормальны.

## Element: долго «Синхронизация…» после входа

Клиент держит long-poll на **`/_matrix/client/…/sync`**. Нужно: **`flush_interval -1`**, **таймауты ~360s** на **`/_matrix/*`** и **`/_synapse/*`**, и **не включать gzip на эти пути** (см. **`templates/Caddyfile.template`**). После правок шаблона: **`docker compose --profile init run --rm caddy-init`**, затем **`docker compose up -d --force-recreate caddy`**. Правьте **`templates/Caddyfile.template`**, не сгенерированный **`caddy/config/Caddyfile`** (его перезаписывает **`caddy-init`**).

**Пошагово**, если всё ещё висит: (1) в браузере **F12 → Network**, фильтр **`sync`**: статус **200** и через ~30s приходит ответ или **pending / (failed)**? (2) **`docker compose logs synapse -f`** во время входа — ошибки Python/БД? (3) **`df -h`**, **`free -h`** — диск и RAM. (4) Прямой тест без прокси: **`docker compose exec caddy wget -qO- --timeout=35 http://synapse:8008/_matrix/client/versions`**. (5) **Element Desktop** или другой браузер. (6) Временно отключить VPN/фильтры на ПК.

Ошибка **`Cannot access 'B' before initialization`** в **`init.js`** / **`WidgetLayoutStore`** — известный класс сбоев инициализации в части сборок Element; попробуйте другой браузер без расширений или зафиксируйте образ, например **`vectorim/element-web:v1.11.86`** вместо **`latest`** в **`docker-compose.yml`**.

После правок Caddy: `docker compose up -d --force-recreate caddy`. Если меняли только Synapse (`web_client_location`): `docker compose restart synapse`.

Дождитесь **`(healthy)`** у контейнера Synapse (не только `health: starting`), затем с клиента:  
`curl -sS "https://matrix.chat.example.net/_matrix/client/versions"`.  
Если ответ есть, а Element всё ещё «не связаться» — обновите **`templates/Caddyfile.template`** и перезапустите **caddy**.

После того как связь появится: **`ENABLE_REGISTRATION=true`** в `.env` (по умолчанию в compose так и есть) синхронизируется в **`homeserver.yaml`** при каждом старте Synapse; для отключения открытой регистрации задайте **`ENABLE_REGISTRATION=false`**, затем **`docker compose up -d synapse`**. Если регистрация выключена — создайте пользователя:  
`docker compose exec synapse register_new_matrix_user -c /data/homeserver.yaml -a -u USER http://localhost:8008`.

Проверка с вашего ПК:  
`curl -sS "https://matrix.chat.example.net/_matrix/client/versions"`  
и с Origin:  
`curl -sSI -H "Origin: https://element.chat.example.net" "https://matrix.chat.example.net/_matrix/client/versions"`  
во втором ответе должны быть строки `access-control-allow-origin`.

## `set: Illegal option -` в логах Synapse

Скрипт на сервере с **CRLF** (Windows) или «кривым» символом в `set …`. На сервере:

```bash
sed -i 's/\r$//' synapse/entrypoint.sh
docker compose up -d --force-recreate synapse
```

В репозитории `entrypoint.sh` без `set -u`, только `set -e`, чтобы dash/busybox не спотыкались.

## PostgreSQL не стартует (`dependency postgres failed` / unhealthy)

1. Запускайте compose **из каталога с `docker-compose.yml` и `.env`**: `cd /opt/matrix` (или ваш путь).
2. В **`.env` обязателен непустой** **`POSTGRES_PASSWORD`** — иначе образ postgres завершает работу. Удобно: **`./scripts/secrets_generate.sh`**.
3. Логи: **`docker compose logs postgres`** (там будет точная причина: пароль, права, `initdb`).
4. После **неудачной первой инициализации** каталог **`postgres/data/`** может остаться полупустым — остановите стек и **очистите данные** (только если БД не нужна):  
   `docker compose down` → **`rm -rf postgres/data/*`** → снова **`docker compose up -d`**.
5. Healthcheck в compose подставляет имя пользователя/БД из **`.env`** при `docker compose up`; первый старт БД может занять до **~2 минут** (`start_period`).

## Synapse постоянно Restarting (2)

1. Логи: `docker compose logs synapse --tail 150`.
2. Частая причина в этом compose: в `homeserver.yaml` после правки **listeners** получался **пустой** список — в `entrypoint.sh` это исправлено (пустым список не заменяем).
3. Если подозреваете `merge-matrixrtc.py`: в `.env` задайте **`SKIP_RTC_MERGE=1`**, `docker compose up -d --force-recreate synapse`. Если Synapse **поднялся** — проблема в блоках RTC/.well-known; пришлите лог и верните `SKIP_RTC_MERGE=0` после правки.
4. **`enable_registration` без верификации** (новые Synapse): в логах *«open registration without any verification»*. При **`ENABLE_REGISTRATION=true`** `entrypoint.sh` выставляет и **`enable_registration_without_verification: true`**. Или вручную в `homeserver.yaml`. Сообщение про **`suppress_key_server_warning`** и `matrix.org` — только предупреждение; при желании: `suppress_key_server_warning: true` в `homeserver.yaml`.

## Если Synapse/Element в цикле перезапуска

- **`set: pipefail: invalid option name`** — скрипт шёл через `sh` без bash; entrypoint на POSIX `sh` без `pipefail`. На Windows сохраняйте **LF**, на сервере при необходимости: `sed -i 's/\r$//' synapse/entrypoint.sh`.
- **`Permission denied` на `/app/config.json` у Element** — init теперь пишет с `umask 022` и `chmod 644`. После обновления: `docker compose --profile init run --rm element-init && docker compose --profile init run --rm element-call-init && docker compose up -d`.
- **Synapse всё ещё `Restarting`, в `docker ps` видно `/bin/bash`** — на сервере старый `docker-compose.yml`. Должно быть `entrypoint: ["/bin/sh", "/synapse-entrypoint.sh"]` и актуальный `synapse/entrypoint.sh` (запуск через `python3 /start.py`, не только `exec /start.py`).
- **Диагностика:** `docker compose logs synapse --tail 200` — по тексту ошибки видно конфиг/БД.
