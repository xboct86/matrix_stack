#!/bin/sh
set -e

: "${MATRIX_DOMAIN:?MATRIX_DOMAIN missing in .env}"

TPL=/templates/Caddyfile.template
APEX_TPL=/templates/Caddyfile.matrix-apex.template
if [ ! -f "$TPL" ]; then
	echo "caddy-init: нет файла $TPL — на хосте должен быть templates/Caddyfile.template (файл)." >&2
	echo "Если это каталог: rm -rf templates/Caddyfile.template && скопируйте файл из репозитория." >&2
	ls -la /templates 2>/dev/null || true
	exit 1
fi

MATRIX_SERVER_NAME="${MATRIX_SERVER_NAME:-$MATRIX_DOMAIN}"

cp "$TPL" /data/Caddyfile
chmod 644 /data/Caddyfile

if [ "$MATRIX_SERVER_NAME" != "$MATRIX_DOMAIN" ]; then
	if [ ! -f "$APEX_TPL" ]; then
		echo "caddy-init: для MATRIX_SERVER_NAME≠MATRIX_DOMAIN нужен $APEX_TPL" >&2
		exit 1
	fi
	cat "$APEX_TPL" >> /data/Caddyfile
	echo "caddy-init: добавлен apex-блок (Caddy подставит MATRIX_SERVER_NAME/MATRIX_DOMAIN из env при старте)"
fi

echo "caddy-init: MATRIX_DOMAIN=${MATRIX_DOMAIN} -> /data/Caddyfile"
