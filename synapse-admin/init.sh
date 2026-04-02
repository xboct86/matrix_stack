#!/bin/sh
set -e

: "${MATRIX_DOMAIN:?MATRIX_DOMAIN missing in .env}"

TPL=/templates/synapse-admin-config.json.template
if [ ! -f "$TPL" ]; then
	echo "synapse-admin-init: нет файла $TPL" >&2
	exit 1
fi

apk add --no-cache gettext >/dev/null
mkdir -p /data
umask 022
envsubst < "$TPL" > /data/config.json
chmod 644 /data/config.json
