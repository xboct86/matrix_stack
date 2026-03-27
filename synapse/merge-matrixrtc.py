#!/usr/bin/env python3
"""Idempotent правки homeserver.yaml для звонков (MSC / matrix_rtc / .well-known)."""
import os
import pathlib

import yaml

path = pathlib.Path("/data/homeserver.yaml")
if not path.exists():
    raise SystemExit(0)

cfg = yaml.safe_load(path.read_text(encoding="utf-8"))
if not isinstance(cfg, dict):
    raise SystemExit(0)

# TURN / coturn — не зависит от RTC; применяем всегда (иначе ранний exit ниже блокировал запись).
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

rtc_host = (
    os.environ.get("RTC_DOMAIN")
    or os.environ.get("MATRIX_DOMAIN")
    or (cfg.get("server_name") if isinstance(cfg.get("server_name"), str) else "")
).strip()

if not rtc_host:
    import sys

    print(
        "merge-matrixrtc: RTC_DOMAIN/MATRIX_DOMAIN пусты, пропускаю блок matrix_rtc "
        "(TURN уже записан, если задан в env).",
        file=sys.stderr,
    )
    path.write_text(
        yaml.safe_dump(
            cfg,
            default_flow_style=False,
            sort_keys=False,
            allow_unicode=True,
        ),
        encoding="utf-8",
    )
    raise SystemExit(0)

jwt_url = f"https://{rtc_host}/livekit/jwt"


def ensure_dict(key: str) -> dict:
    """Если в YAML ключ есть, но null или не dict — заменить на {} (иначе .setdefault падает)."""
    val = cfg.get(key)
    if not isinstance(val, dict):
        val = {}
        cfg[key] = val
    return val


element_host = os.environ.get("ELEMENT_DOMAIN")
if element_host:
    cfg.setdefault(
        "web_client_location",
        f"https://{element_host.rstrip('/')}/",
    )

fe = ensure_dict("experimental_features")
fe.setdefault("msc3266_enabled", True)
fe.setdefault("msc4222_enabled", True)

cfg.setdefault("max_event_delay_duration", "24h")

if not isinstance(cfg.get("rc_message"), dict):
    cfg["rc_message"] = {"per_second": 0.5, "burst_count": 30}
if not isinstance(cfg.get("rc_delayed_event_mgmt"), dict):
    cfg["rc_delayed_event_mgmt"] = {"per_second": 1, "burst_count": 20}

mr = ensure_dict("matrix_rtc")
mr.setdefault(
    "transports",
    [{"type": "livekit", "livekit_service_url": jwt_url}],
)

ew = ensure_dict("extra_well_known_client_content")
ew.setdefault(
    "org.matrix.msc4143.rtc_foci",
    [{"type": "livekit", "livekit_service_url": jwt_url}],
)
ew.setdefault(
    "org.matrix.msc4143.rtc_transports",
    [{"type": "livekit", "livekit_service_url": jwt_url}],
)

path.write_text(
    yaml.safe_dump(
        cfg,
        default_flow_style=False,
        sort_keys=False,
        allow_unicode=True,
    ),
    encoding="utf-8",
)
