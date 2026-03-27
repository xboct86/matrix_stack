#!/bin/sh
set -e

export LIVEKIT_PORT="${LIVEKIT_PORT:-7880}"
export LIVEKIT_TCP_PORT="${LIVEKIT_TCP_PORT:-7881}"
export LIVEKIT_UDP_PORT_START="${LIVEKIT_UDP_PORT_START:-50000}"
export LIVEKIT_UDP_PORT_END="${LIVEKIT_UDP_PORT_END:-50100}"

: "${LIVEKIT_API_KEY:?Set LIVEKIT_API_KEY in .env}"
: "${LIVEKIT_API_SECRET:?Set LIVEKIT_API_SECRET in .env}"

TPL=/templates/livekit.yaml.template
if [ ! -f "$TPL" ]; then
	echo "livekit-init: нет файла $TPL" >&2
	exit 1
fi

apk add --no-cache gettext >/dev/null
mkdir -p /data
umask 022
envsubst < "$TPL" > /data/livekit.yaml
chmod 644 /data/livekit.yaml
echo "livekit-init: wrote /data/livekit.yaml (port ${LIVEKIT_PORT})"
