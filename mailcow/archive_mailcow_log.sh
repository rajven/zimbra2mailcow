#!/bin/bash

SRC_FILE="/var/log/mailcow/mailcow.log.1"
ARCHIVE_ROOT="/var/log/archive"

# Проверка существования файла
if [[ ! -f "$SRC_FILE" ]]; then
    echo "❌ Ошибка: файл $SRC_FILE не существует." >&2
    exit 1
fi

LOG_DATE=""

# === Этап 1: пробуем извлечь дату из первой строки лога ===
FIRST_LINE=$(head -n 1 "$SRC_FILE" 2>/dev/null | tr -d '\r')

if [[ -n "$FIRST_LINE" ]]; then
    # Извлекаем YYYY-MM-DD из начала строки (до 'T')
    EXTRACTED_DATE=$(echo "$FIRST_LINE" | grep -o '^[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}')
    
    # Проверяем, что дата извлечена и валидна
    if [[ -n "$EXTRACTED_DATE" ]] && date -d "$EXTRACTED_DATE" >/dev/null 2>&1; then
        LOG_DATE="$EXTRACTED_DATE"
        echo "✅ Используем дату из лога: $LOG_DATE"
    else
        echo "⚠️ Предупреждение: не удалось извлечь или проверить дату из первой строки." >&2
    fi
fi

# === Этап 2: fallback — дата = mtime файла минус один день ===
if [[ -z "$LOG_DATE" ]]; then
    MTIME_EPOCH=$(stat -c %Y "$SRC_FILE" 2>/dev/null)
    if [[ -n "$MTIME_EPOCH" ]] && [[ "$MTIME_EPOCH" -gt 0 ]]; then
        LOG_DATE=$(date -d "@$MTIME_EPOCH - 1 day" +%Y-%m-%d)
        echo "📅 Используем fallback: mtime - 1 день → $LOG_DATE"
    else
        echo "❌ Ошибка: не удалось получить mtime файла. Выход." >&2
        exit 1
    fi
fi

# === Этап 3: формируем структуру и сжимаем ===
YEAR=$(echo "$LOG_DATE" | cut -d'-' -f1)
MONTH=$(echo "$LOG_DATE" | cut -d'-' -f2)

TARGET_DIR="$ARCHIVE_ROOT/$YEAR/$MONTH"
TARGET_FILE="$TARGET_DIR/$LOG_DATE.log.gz"  # ← теперь .gz!

mkdir -p "$TARGET_DIR"

# Не перезаписываем, если уже существует
if [[ -f "$TARGET_FILE" ]]; then
    echo "⚠️ Файл $TARGET_FILE уже существует. Пропускаем." >&2
    exit 0
fi

# Сжимаем и сохраняем
if gzip -c "$SRC_FILE" > "$TARGET_FILE"; then
    echo "✅ Файл успешно сжат и сохранён: $TARGET_FILE"
else
    echo "❌ Ошибка при сжатии или записи файла." >&2
    exit 1
fi
