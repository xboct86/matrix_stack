#!/bin/sh
set -e

: "${MATRIX_DOMAIN:?MATRIX_DOMAIN missing in .env}"

TPL=/templates/Caddyfile.template
if [ ! -f "$TPL" ]; then
	echo "caddy-init: нет файла $TPL — на хосте должен быть templates/Caddyfile.template (файл)." >&2
	echo "Если это каталог: rm -rf templates/Caddyfile.template && скопируйте файл из репозитория." >&2
	ls -la /templates 2>/dev/null || true
	exit 1
fi

MATRIX_SERVER_NAME="${MATRIX_SERVER_NAME:-$MATRIX_DOMAIN}"
if [ "$MATRIX_SERVER_NAME" = "$MATRIX_DOMAIN" ]; then
	SYNAPSE_SNI="$MATRIX_DOMAIN"
else
	SYNAPSE_SNI="$MATRIX_DOMAIN, $MATRIX_SERVER_NAME"
fi

sed "s|@@SYNAPSE_SNI@@|${SYNAPSE_SNI}|g" "$TPL" > /data/Caddyfile
chmod 644 /data/Caddyfile
echo "caddy-init: SYNAPSE_SNI=${SYNAPSE_SNI} -> /data/Caddyfile"
