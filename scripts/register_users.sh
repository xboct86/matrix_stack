#!/bin/bash
# Массовая регистрация из users.txt в корне проекта. Запуск из любого каталога:
#   ./scripts/register_users.sh
set -e

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
cd "$ROOT_DIR"

# Файл со списком пользователей (в корне репозитория)
USERS_FILE="$ROOT_DIR/users.txt"
# Пароль по умолчанию
DEFAULT_PASSWORD="123456"
# Задержка между регистрациями (секунды)
DELAY=1
# Делать пользователя администратором? (--admin или --no-admin)
ADMIN_FLAG="--no-admin"

# Проверяем существование файла
if [ ! -f "$USERS_FILE" ]; then
    echo "Ошибка: Файл $USERS_FILE не найден!"
    exit 1
fi

# Очищаем файл от символов \r (Windows) и пустых строк
sed -i 's/\r$//' "$USERS_FILE"
sed -i '/^$/d' "$USERS_FILE"

# Счетчики
SUCCESS=0
FAILED=0
EXISTS=0

echo "Начинаем регистрацию пользователей..."
echo "================================"
echo "Задержка между пользователями: ${DELAY} секунд"
echo ""

# Читаем файл, используя дескриптор 3, чтобы избежать конфликта с stdin
while IFS= read -r username <&3 || [ -n "$username" ]; do
    # Удаляем пробелы в начале и конце
    username=$(echo "$username" | xargs)

    # Пропускаем пустые строки
    if [ -z "$username" ]; then
        continue
    fi

    echo "[$(date '+%H:%M:%S')] Обрабатываю пользователя: $username"

    # Выполняем регистрацию, перенаправляя /dev/null в stdin
    OUTPUT=$(docker compose exec --no-TTY synapse register_new_matrix_user \
        -c /data/homeserver.yaml \
        -u "$username" \
        -p "$DEFAULT_PASSWORD" \
        $ADMIN_FLAG \
        http://localhost:8008 2>&1 < /dev/null)

    # Проверяем результат
    if [[ "$OUTPUT" == *"Success"* ]]; then
        echo "  ✓ Пользователь $username успешно зарегистрирован"
        ((SUCCESS++))
    elif [[ "$OUTPUT" == *"already taken"* ]] || [[ "$OUTPUT" == *"User ID already taken"* ]]; then
        echo "  → Пользователь $username уже существует, пропускаем"
        ((EXISTS++))
    else
        echo "  ✗ Ошибка при регистрации пользователя $username"
        echo "    Сообщение: $OUTPUT"
        ((FAILED++))
    fi

    echo "  ---"
    if [ $((SUCCESS + FAILED + EXISTS)) -lt $(wc -l < "$USERS_FILE") ]; then
        echo "  Ожидание ${DELAY} секунд перед следующим пользователем..."
        sleep "$DELAY"
    fi

done 3< "$USERS_FILE"

echo ""
echo "================================"
echo "Регистрация завершена!"
echo "Успешно зарегистрировано: $SUCCESS"
echo "Уже существовали: $EXISTS"
echo "Ошибок: $FAILED"
echo "================================"
