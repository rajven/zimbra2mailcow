#!/bin/bash

LOG_DIR="/var/log/mailcow"
ARCHIVE_ROOT="/var/log/archive"

shopt -s extglob

find "$LOG_DIR" -name "mailcow.log.*.gz" -regextype posix-egrep -regex '.*/mailcow\.log\.[0-9]+\.gz' 2>/dev/null | sort -t. -k3,3nr |  while read -r SRC_FILE; do

    [[ ! -f "$SRC_FILE" ]] && continue

    FILE_NUM=${SRC_FILE##*.}
    FILE_NUM=${FILE_NUM%.gz}

    echo "🔍 Обрабатываю: $SRC_FILE (номер: $FILE_NUM)"

    LOG_DATE=""

    # === Этап 1: читаем первую строку через zcat ===
    FIRST_LINE=$(zcat "$SRC_FILE" 2>/dev/null | head -n 1 | tr -d '\r')

    if [[ -n "$FIRST_LINE" ]]; then
        EXTRACTED_DATE=$(echo "$FIRST_LINE" | grep -o '^[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}')
        if [[ -n "$EXTRACTED_DATE" ]] && date -d "$EXTRACTED_DATE" >/dev/null 2>&1; then
            LOG_DATE="$EXTRACTED_DATE"
            echo "✅ Дата из лога: $LOG_DATE"
        else
            echo "⚠️ Не удалось извлечь дату из первой строки."
        fi
    else
        echo "⚠️ Не удалось прочитать содержимое $SRC_FILE через zcat."
    fi

    # === Этап 2: fallback — mtime минус один день ===
    if [[ -z "$LOG_DATE" ]]; then
        MTIME_EPOCH=$(stat -c %Y "$SRC_FILE" 2>/dev/null)
        if [[ -n "$MTIME_EPOCH" ]] && [[ "$MTIME_EPOCH" -gt 0 ]]; then
            LOG_DATE=$(date -d "@$MTIME_EPOCH - 1 day" +%Y-%m-%d)
            echo "📅 Fallback: mtime - 1 день → $LOG_DATE"
        else
            echo "❌ Не удалось получить mtime — пропускаю файл $SRC_FILE"
            continue
        fi
    fi

    # === Этап 3: копируем .gz файл в архив ===
    YEAR=$(echo "$LOG_DATE" | cut -d'-' -f1)
    MONTH=$(echo "$LOG_DATE" | cut -d'-' -f2)

    TARGET_DIR="$ARCHIVE_ROOT/$YEAR/$MONTH"
    TARGET_FILE="$TARGET_DIR/$LOG_DATE.log.gz"

    mkdir -p "$TARGET_DIR"

    if [[ -f "$TARGET_FILE" ]]; then
        echo "⚠️ Пропускаю: $TARGET_FILE уже существует."
        continue
    fi

    if cp "$SRC_FILE" "$TARGET_FILE"; then
        echo "✅ Успешно сохранён: $TARGET_FILE"
    else
        echo "❌ Ошибка при копировании: $SRC_FILE"
        continue
    fi

    echo "---"

done

echo "🏁 Обработка завершена."
