#!/bin/sh
# Генерирует криптостойкие значения и записывает их в .env в корне проекта.
# Не трогает домены, порты и прочие не-секретные переменные.
#
# Использование:
#   ./scripts/secrets_generate.sh
#   MATRIX_COMPOSE_DIR=/path/to/project ./scripts/secrets_generate.sh
#
# Если .env нет — копируется из .env.example (проверьте домены и TURN_EXTERNAL_IP).
set -e

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

if [ -n "${MATRIX_COMPOSE_DIR:-}" ] && [ -f "$MATRIX_COMPOSE_DIR/docker-compose.yml" ]; then
	ROOT_DIR=$(CDPATH= cd -- "$MATRIX_COMPOSE_DIR" && pwd)
elif [ -f "$SCRIPT_DIR/../docker-compose.yml" ]; then
	ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
else
	echo "Не найден docker-compose.yml рядом с scripts/. Задайте MATRIX_COMPOSE_DIR или запустите из репозитория." >&2
	exit 1
fi

ENV_FILE="$ROOT_DIR/.env"
EXAMPLE="$ROOT_DIR/.env.example"

if [ ! -f "$ENV_FILE" ]; then
	if [ ! -f "$EXAMPLE" ]; then
		echo "Нет $ENV_FILE и нет $EXAMPLE — нечего копировать." >&2
		exit 1
	fi
	cp "$EXAMPLE" "$ENV_FILE"
	echo "Создан $ENV_FILE из .env.example — задайте домены, ACME_EMAIL, TURN_EXTERNAL_IP и снова запустите скрипт при необходимости." >&2
fi

if ! command -v openssl >/dev/null 2>&1; then
	echo "Нужен openssl в PATH." >&2
	exit 1
fi

POSTGRES_PASSWORD=$(openssl rand -hex 32)
TURN_SHARED_SECRET=$(openssl rand -hex 32)
LIVEKIT_API_SECRET=$(openssl rand -hex 48)
LIVEKIT_API_KEY="lk_$(openssl rand -hex 16)"

# Подстановка строки в .env: KEY=value (строка начинается с KEY=), иначе дописать в конец.
upsert_env() {
	_key=$1
	_val=$2
	_file=$3
	awk -v k="$_key" -v v="$_val" '
		index($0, k "=") == 1 { print k "=" v; replaced = 1; next }
		{ print }
		END {
			if (!replaced) print k "=" v
		}
	' "$_file" > "$_file.tmp"
	mv "$_file.tmp" "$_file"
}

upsert_env POSTGRES_PASSWORD "$POSTGRES_PASSWORD" "$ENV_FILE"
upsert_env TURN_SHARED_SECRET "$TURN_SHARED_SECRET" "$ENV_FILE"
upsert_env LIVEKIT_API_SECRET "$LIVEKIT_API_SECRET" "$ENV_FILE"
upsert_env LIVEKIT_API_KEY "$LIVEKIT_API_KEY" "$ENV_FILE"

echo "Обновлены секреты в $ENV_FILE:" >&2
echo "  POSTGRES_PASSWORD (64 hex)" >&2
echo "  TURN_SHARED_SECRET (64 hex)" >&2
echo "  LIVEKIT_API_SECRET (96 hex)" >&2
echo "  LIVEKIT_API_KEY" >&2
echo "" >&2
echo "Дальше: пересоберите конфиги (профиль init), затем при смене POSTGRES_PASSWORD пересоздайте БД или смените пароль вручную в Postgres." >&2
