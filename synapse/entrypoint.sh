#!/bin/sh
# Keep LF line endings on Linux (no CRLF from Windows).
set -e

: "${MATRIX_DOMAIN:?MATRIX_DOMAIN is required}"
: "${POSTGRES_PASSWORD:?POSTGRES_PASSWORD is required}"

if command -v python3 >/dev/null 2>&1; then
  PY=python3
elif command -v python >/dev/null 2>&1; then
  PY=python
else
  echo "Neither python3 nor python found in PATH" >&2
  exit 1
fi

merge_matrixrtc() {
  if [ ! -f /data/homeserver.yaml ]; then
    return 0
  fi
  if [ "${SKIP_RTC_MERGE:-0}" = "1" ]; then
    echo "SKIP_RTC_MERGE=1, skipping merge-matrixrtc.py" >&2
    return 0
  fi
  "$PY" /merge-matrixrtc.py
}

if [ ! -f /data/homeserver.yaml ]; then
  export SYNAPSE_NO_TLS=yes
  export SYNAPSE_SERVER_NAME="${MATRIX_DOMAIN}"
  export SYNAPSE_REPORT_STATS="${SYNAPSE_REPORT_STATS:-no}"
  "$PY" /start.py generate
  touch /data/.need-db-patch
fi

if [ -f /data/.need-db-patch ]; then
  "$PY" <<'PY'
import os
import yaml

path = "/data/homeserver.yaml"
with open(path, "r", encoding="utf-8") as f:
    cfg = yaml.safe_load(f)

pg_user = os.environ.get("POSTGRES_USER") or "synapse"
pg_db = os.environ.get("POSTGRES_DB") or "synapse"
cfg["database"] = {
    "name": "psycopg2",
    "args": {
        "user": pg_user,
        "password": os.environ["POSTGRES_PASSWORD"],
        "database": pg_db,
        "host": "postgres",
        "port": 5432,
        "cp_min": 5,
        "cp_max": 10,
    },
}

cfg["public_baseurl"] = f"https://{os.environ['MATRIX_DOMAIN']}"
cfg["use_x_forwarded_for"] = True

listeners = cfg.get("listeners")
if isinstance(listeners, list) and listeners:
    filtered = [
        L for L in listeners
        if not (isinstance(L, dict) and L.get("port") == 8448)
    ]
    if filtered:
        cfg["listeners"] = filtered

with open(path, "w", encoding="utf-8") as f:
    yaml.safe_dump(cfg, f, default_flow_style=False, sort_keys=False, allow_unicode=True)

os.unlink("/data/.need-db-patch")
PY
fi

merge_matrixrtc

# Регистрация из ENABLE_REGISTRATION; без верификации нужен флаг (Synapse 1.112+).
"$PY" <<'PY'
import os
import pathlib
import yaml

path = pathlib.Path("/data/homeserver.yaml")
if not path.exists():
    raise SystemExit(0)
cfg = yaml.safe_load(path.read_text(encoding="utf-8"))
if not isinstance(cfg, dict):
    raise SystemExit(0)

reg = os.environ.get("ENABLE_REGISTRATION", "true").lower() in ("1", "true", "yes")
cfg["enable_registration"] = reg
if reg:
    cfg["enable_registration_without_verification"] = True
else:
    cfg.pop("enable_registration_without_verification", None)

# Локальный каталог пользователей: поиск по серверу в Element
ud = cfg.get("user_directory")
if not isinstance(ud, dict):
    ud = {}
    cfg["user_directory"] = ud
if os.environ.get("ENABLE_USER_DIRECTORY_SEARCH", "true").lower() in ("1", "true", "yes"):
    ud["enabled"] = True
    ud["search_all_users"] = True
else:
    ud.setdefault("enabled", True)
    ud.setdefault("search_all_users", False)

# TURN (coturn): TURN_SHARED_SECRET + TURN_DOMAIN + COTURN_LISTENING_PORT в env контейнера
turn_secret = (os.environ.get("TURN_SHARED_SECRET") or "").strip()
turn_domain = (os.environ.get("TURN_DOMAIN") or "").strip()
turn_port = (os.environ.get("COTURN_LISTENING_PORT") or "3478").strip() or "3478"
if turn_secret and turn_domain:
    cfg["turn_shared_secret"] = turn_secret
    cfg["turn_uris"] = [
        f"turn:{turn_domain}:{turn_port}?transport=udp",
        f"turn:{turn_domain}:{turn_port}?transport=tcp",
    ]
else:
    cfg.pop("turn_shared_secret", None)
    cfg.pop("turn_uris", None)

path.write_text(
    yaml.safe_dump(
        cfg,
        default_flow_style=False,
        sort_keys=False,
        allow_unicode=True,
    ),
    encoding="utf-8",
)
PY

exec "$PY" /start.py
