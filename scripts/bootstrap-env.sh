#!/usr/bin/env bash
# Интерактивно создаёт .env из templates/env.bootstrap.template:
# базовый домен → поддомены matrix./element./…; почта; внешний IP; случайные секреты.
#
# Запуск:
#   ./scripts/bootstrap-env.sh
# Требуется: bash, openssl
set -e

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
TEMPLATE="$ROOT_DIR/templates/env.bootstrap.template"
OUT="$ROOT_DIR/.env"

if [ ! -f "$TEMPLATE" ]; then
	echo "Нет файла шаблона: $TEMPLATE" >&2
	exit 1
fi

if ! command -v openssl >/dev/null 2>&1; then
	echo "Нужен openssl в PATH." >&2
	exit 1
fi

printf "Базовый домен без префикса сервиса (например example.com или chat.example.net).\n"
printf "Будут созданы: matrix.<домен>, element.<домен>, …\n"
printf "Домен: "
read -r BASE_DOMAIN
BASE_DOMAIN=$(printf '%s' "$BASE_DOMAIN" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/\.$//')
if [ -z "$BASE_DOMAIN" ]; then
	echo "Домен не может быть пустым." >&2
	exit 1
fi

BASE_DOMAIN=$(printf '%s' "$BASE_DOMAIN" | tr '[:upper:]' '[:lower:]')

printf "Email для Let's Encrypt (ACME): "
read -r ACME_EMAIL
ACME_EMAIL=$(printf '%s' "$ACME_EMAIL" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
if [ -z "$ACME_EMAIL" ]; then
	echo "Email не может быть пустым." >&2
	exit 1
fi

printf "Внешний IPv4 сервера (для TURN/coturn, как видит интернет): "
read -r TURN_EXTERNAL_IP
TURN_EXTERNAL_IP=$(printf '%s' "$TURN_EXTERNAL_IP" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
if ! printf '%s' "$TURN_EXTERNAL_IP" | grep -qE '^[0-9]{1,3}(\.[0-9]{1,3}){3}$'; then
	echo "Похоже на неверный IPv4, остановка." >&2
	exit 1
fi

if [ -f "$OUT" ]; then
	printf "Файл .env уже существует. Перезаписать? [y/N]: "
	read -r yn
	case "$yn" in
		y|Y|yes|YES) ;;
		*) echo "Отмена."; exit 0 ;;
	esac
fi

MATRIX_DOMAIN="matrix.${BASE_DOMAIN}"
ELEMENT_DOMAIN="element.${BASE_DOMAIN}"
ADMIN_DOMAIN="admin.${BASE_DOMAIN}"
AUTH_DOMAIN="auth.${BASE_DOMAIN}"
CALL_DOMAIN="call.${BASE_DOMAIN}"
RTC_DOMAIN="rtc.${BASE_DOMAIN}"
TURN_DOMAIN="turn.${BASE_DOMAIN}"

POSTGRES_PASSWORD=$(openssl rand -hex 32)
TURN_SHARED_SECRET=$(openssl rand -hex 32)
LIVEKIT_API_SECRET=$(openssl rand -hex 48)
LIVEKIT_API_KEY="lk_$(openssl rand -hex 16)"

text=$(cat -- "$TEMPLATE")

replace_placeholder() {
	local key=$1
	local val=$2
	local ph="__${key}__"
	text="${text//$ph/$val}"
}

replace_placeholder MATRIX_DOMAIN "$MATRIX_DOMAIN"
replace_placeholder ELEMENT_DOMAIN "$ELEMENT_DOMAIN"
replace_placeholder ADMIN_DOMAIN "$ADMIN_DOMAIN"
replace_placeholder AUTH_DOMAIN "$AUTH_DOMAIN"
replace_placeholder CALL_DOMAIN "$CALL_DOMAIN"
replace_placeholder RTC_DOMAIN "$RTC_DOMAIN"
replace_placeholder TURN_DOMAIN "$TURN_DOMAIN"
replace_placeholder ACME_EMAIL "$ACME_EMAIL"
replace_placeholder TURN_EXTERNAL_IP "$TURN_EXTERNAL_IP"
replace_placeholder POSTGRES_PASSWORD "$POSTGRES_PASSWORD"
replace_placeholder TURN_SHARED_SECRET "$TURN_SHARED_SECRET"
replace_placeholder LIVEKIT_API_KEY "$LIVEKIT_API_KEY"
replace_placeholder LIVEKIT_API_SECRET "$LIVEKIT_API_SECRET"

printf '%s' "$text" > "$OUT"
echo "Записан $OUT"

echo ""
echo "Поддомены:"
echo "  MATRIX_DOMAIN=$MATRIX_DOMAIN"
echo "  ELEMENT_DOMAIN=$ELEMENT_DOMAIN"
echo "  … admin, auth, call, rtc, turn — см. .env"
echo ""
echo "Дальше: docker compose --profile init up --abort-on-container-exit \\"
echo "  livekit-init element-init element-call-init synapse-admin-init caddy-init coturn-init"
echo "Затем: docker compose up -d"
