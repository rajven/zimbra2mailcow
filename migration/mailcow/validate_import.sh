#!/bin/bash

# ============================================================
# ВАЛИДАЦИЯ ИМПОРТА (РАБОЧАЯ ВЕРСИЯ)
# ============================================================

. /root/mailcow/mailcow_config

CSV_FILE="${1}"
if [ -z "${CSV_FILE}" ] || [ ! -f "${CSV_FILE}" ]; then
    echo "❌ Файл не найден: ${CSV_FILE}"
    exit 1
fi

echo "=========================================="
echo "🔍 ВАЛИДАЦИЯ ИМПОРТА"
echo "=========================================="

# 1. Собираем список ящиков из mailcow
echo "📊 Получаем список ящиков из mailcow..."
MAILCOW_LIST="/tmp/mailcow_list_$$.txt"
> ${MAILCOW_LIST}

DOMAINS=$(curl -s -X 'GET' -H "X-API-Key: ${API_RO_KEY}" -H 'Content-Type: application/json' \
    "https://${MC_SERVER}/api/v1/get/domain/all" 2>/dev/null | jq -r '.[].domain_name' 2>/dev/null)

for DOMAIN in ${DOMAINS}; do
    curl -s -X 'GET' -H "X-API-Key: ${API_RO_KEY}" -H 'Content-Type: application/json' \
        "https://${MC_SERVER}/api/v1/get/mailbox/all/${DOMAIN}" 2>/dev/null | \
        jq -r '.[].username' 2>/dev/null >> ${MAILCOW_LIST}
done

MAILCOW_COUNT=$(wc -l < ${MAILCOW_LIST})
echo "✅ В mailcow: ${MAILCOW_COUNT} ящиков"

# 2. Читаем CSV
echo "📊 Читаем CSV файл..."

# Просто читаем все строки после заголовка
CSV_TEMP="/tmp/csv_temp_$$.txt"
tail -n +2 "${CSV_FILE}" | grep -v "^$" > ${CSV_TEMP}

CSV_COUNT=$(wc -l < ${CSV_TEMP})
echo "✅ В CSV: ${CSV_COUNT} ящиков"

if [ ${CSV_COUNT} -eq 0 ]; then
    echo ""
    echo "❌ ОШИБКА: CSV пустой или не читается!"
    echo ""
    echo "Проверьте содержимое файла:"
    echo "----------------------------------------"
    cat ${CSV_FILE} | head -10
    echo "----------------------------------------"
    rm -f ${MAILCOW_LIST} ${CSV_TEMP}
    exit 1
fi

# 3. Сравниваем
echo ""
echo "📊 Сравниваем..."
echo "=========================================="

MISSING=0
FOUND=0

while IFS='|' read -r email rest; do
    # Убираем возможные \r и пробелы
    email=$(printf '%s' "$email" | tr -d '\r' | xargs)

    if grep -Fxq "$email" "$MAILCOW_LIST" 2>/dev/null; then
        FOUND=$((FOUND + 1))
    else
        echo "❌ ОТСУТСТВУЕТ: ${email}"
        MISSING=$((MISSING + 1))
    fi
done < "$CSV_TEMP"

# 4. Итог
echo ""
echo "=========================================="
echo "📊 РЕЗУЛЬТАТ:"
echo "  Всего в CSV: ${CSV_COUNT}"
echo "  Найдено в mailcow: ${FOUND}"
echo "  Отсутствует: ${MISSING}"
echo "=========================================="

if [ ${MISSING} -eq 0 ]; then
    echo "🎉 ВСЕ ЯЩИКИ ИМПОРТИРОВАНЫ!"
elif [ ${MISSING} -lt 10 ]; then
    echo "⚠️ Отсутствует ${MISSING} ящиков (список выше)"
else
    echo "❌ Отсутствует ${MISSING} ящиков!"
    echo "Рекомендация: проверьте импорт или повторите его"
fi

# Очистка
rm -f ${MAILCOW_LIST} ${CSV_TEMP}
