#!/bin/sh
# Вызывается из compose (LF, без CRLF). Переменные из env контейнера / .env.
set -e

export COTURN_LISTENING_PORT="${COTURN_LISTENING_PORT:-3478}"

: "${TURN_SHARED_SECRET:?Set TURN_SHARED_SECRET in .env}"
: "${TURN_DOMAIN:?Set TURN_DOMAIN in .env}"
: "${TURN_EXTERNAL_IP:?Set TURN_EXTERNAL_IP in .env}"
: "${MATRIX_DOMAIN:?Set MATRIX_DOMAIN in .env}"

apk add --no-cache gettext >/dev/null
mkdir -p /data
umask 022

export MATRIX_DOMAIN TURN_SHARED_SECRET COTURN_LISTENING_PORT
export TURN_MIN_PORT="${TURN_MIN_PORT:-49160}"
export TURN_MAX_PORT="${TURN_MAX_PORT:-49260}"

if [ -n "${TURN_INTERNAL_IP:-}" ]; then
	export TURN_EXTERNAL_IP_LINE="${TURN_INTERNAL_IP}/${TURN_EXTERNAL_IP}"
else
	export TURN_EXTERNAL_IP_LINE="${TURN_EXTERNAL_IP}"
fi

TEMPLATE=/templates/turnserver.conf.template
if [ ! -f "$TEMPLATE" ]; then
	echo "coturn-init: нет файла шаблона: $TEMPLATE" >&2
	echo "Проверьте: ls -la templates/turnserver.conf.template" >&2
	ls -la /templates 2>/dev/null || true
	exit 1
fi

envsubst < "$TEMPLATE" > /data/turnserver.conf
chmod 644 /data/turnserver.conf
echo "coturn-init: wrote /data/turnserver.conf (listening-port=${COTURN_LISTENING_PORT}, external-ip line: ${TURN_EXTERNAL_IP_LINE})"
