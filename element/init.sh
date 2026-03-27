#!/bin/sh
set -e

: "${ELEMENT_DOMAIN:?Set ELEMENT_DOMAIN in .env (e.g. element.chat.example.net)}"
: "${MATRIX_DOMAIN:?MATRIX_DOMAIN missing in .env}"
: "${CALL_DOMAIN:?CALL_DOMAIN missing in .env}"

export MATRIX_SERVER_NAME="${MATRIX_SERVER_NAME:-$MATRIX_DOMAIN}"
export ELEMENT_WEB_BRAND="${ELEMENT_WEB_BRAND:-Element}"
export ELEMENT_SHOW_LABS_SETTINGS="${ELEMENT_SHOW_LABS_SETTINGS:-true}"
export ELEMENT_DISABLE_GUESTS="${ELEMENT_DISABLE_GUESTS:-true}"
export ELEMENT_DISABLE_CUSTOM_URLS="${ELEMENT_DISABLE_CUSTOM_URLS:-true}"
export ELEMENT_FEATURE_ELEMENT_CALL_VIDEO_ROOMS="${ELEMENT_FEATURE_ELEMENT_CALL_VIDEO_ROOMS:-true}"
export ELEMENT_CALL_BRAND="${ELEMENT_CALL_BRAND:-Element Call}"
export ELEMENT_CALL_PARTICIPANT_LIMIT="${ELEMENT_CALL_PARTICIPANT_LIMIT:-8}"

TPL=/templates/element-config.json.template
if [ ! -f "$TPL" ]; then
	echo "element-init: нет файла $TPL" >&2
	exit 1
fi

apk add --no-cache gettext >/dev/null
mkdir -p /data
umask 022
envsubst < "$TPL" > /data/element-config.json
chmod 644 /data/element-config.json
cp /data/element-config.json "/data/config.${ELEMENT_DOMAIN}.json"
chmod 644 "/data/config.${ELEMENT_DOMAIN}.json"
