#!/bin/sh
# Дамп БД Synapse (PostgreSQL) → gzip в указанную папку.
# Запускать на хосте, где установлен Docker и есть docker compose.
# Требуется: контейнер postgres из этого проекта запущен.
#
# Использование:
#   ./scripts/backup_pg.sh [каталог_назначения]
# По умолчанию каталог дампов: backups/ в корне проекта
#
# Пароль и имя БД берутся из env контейнера postgres (как в docker-compose).
# Каталог с docker-compose.yml:
#   1) MATRIX_COMPOSE_DIR=/path/to/project
#   2) родитель scripts/, если там лежит docker-compose.yml (скрипт в project/scripts/)
#   3) текущий каталог, если в нём есть docker-compose.yml
# При необходимости: export COMPOSE_FILE=...
set -e

START_PWD=$(pwd)
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

if [ -n "${MATRIX_COMPOSE_DIR:-}" ] && [ -f "$MATRIX_COMPOSE_DIR/docker-compose.yml" ]; then
	ROOT_DIR=$(CDPATH= cd -- "$MATRIX_COMPOSE_DIR" && pwd)
elif [ -f "$SCRIPT_DIR/../docker-compose.yml" ]; then
	ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
elif [ -f "$START_PWD/docker-compose.yml" ]; then
	ROOT_DIR=$(CDPATH= cd -- "$START_PWD" && pwd)
else
	echo "Не найден docker-compose.yml. Зайдите в каталог проекта (где лежит compose) и запустите оттуда," >&2
	echo "или задайте: export MATRIX_COMPOSE_DIR=/home/matrix" >&2
	exit 1
fi
cd "$ROOT_DIR"

DEST=${1:-"$ROOT_DIR/backups"}
mkdir -p "$DEST"

TS=$(date +%Y%m%d_%H%M%S)
OUT="$DEST/postgres_synapse_${TS}.sql.gz"

echo "Дамп synapse → $OUT" >&2

docker compose exec -T postgres sh -c \
	'export PGPASSWORD="$POSTGRES_PASSWORD" && pg_dump -h 127.0.0.1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" --no-owner --no-acl' \
	| gzip -9 > "$OUT"

SIZE=$(wc -c < "$OUT" | tr -d ' ')
if [ "$SIZE" -lt 200 ] 2>/dev/null; then
	echo "Ошибка: дамп подозрительно маленький (${SIZE} байт). Проверьте: cd в каталог с compose, MATRIX_COMPOSE_DIR, docker compose ps postgres" >&2
	rm -f "$OUT"
	exit 1
fi
echo "Готово: $OUT ($SIZE байт)" >&2
