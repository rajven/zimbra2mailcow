#!/bin/bash

# Скрипт для установки квоты 10G для почтовых ящиков через API Mailcow
# Меняет квоту только если она меньше 10G (10240 MB)

. /root/mailcow/mailcow_config

# Проверяем наличие необходимых переменных
if [ -z "${API_RW_KEY}" ] || [ -z "${MC_SERVER}" ]; then
    echo "Ошибка: Не найдены API_RW_KEY или MC_SERVER в конфигурации"
    exit 1
fi

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${GREEN}=== Установка квоты 10G для почтовых ящиков (только если меньше) ===${NC}"

# Проверяем наличие jq
if ! command -v jq &> /dev/null; then
    echo -e "${RED}Ошибка: jq не установлен. Установите: apt-get install jq или yum install jq${NC}"
    exit 1
fi

# Получаем список всех почтовых ящиков
echo -e "${YELLOW}Получаем список почтовых ящиков...${NC}"

MAILBOXES=$(curl -s -X GET "https://${MC_SERVER}/api/v1/get/mailbox/all" \
    -H "X-API-Key: ${API_RW_KEY}" \
    -H "Content-Type: application/json")

if [ -z "$MAILBOXES" ] || [ "$MAILBOXES" = "[]" ] || [ "$MAILBOXES" = "null" ]; then
    echo -e "${RED}Ошибка: Не удалось получить список почтовых ящиков${NC}"
    echo "Ответ API: $MAILBOXES"
    exit 1
fi

COUNT=$(echo "$MAILBOXES" | jq '. | length' 2>/dev/null)
if [ -z "$COUNT" ] || [ "$COUNT" -eq 0 ]; then
    echo -e "${RED}Нет почтовых ящиков для обработки${NC}"
    exit 1
fi

echo -e "${GREEN}Найдено почтовых ящиков: $COUNT${NC}"

# Целевая квота в МБ
TARGET_QUOTA_MB=10240
# Целевая квота в байтах (Mailcow хранит в байтах)
TARGET_QUOTA_BYTES=$((TARGET_QUOTA_MB * 1024 * 1024))

echo -e "${YELLOW}Анализ текущих квот:${NC}"
NEED_UPDATE=0
ALREADY_OK=0
UNLIMITED=0
INVALID=0

# Массив для хранения ящиков, которые нужно обновить
UPDATE_LIST=()

# Проходим по всем ящикам
for i in $(seq 0 $((COUNT-1))); do
    MAILBOX=$(echo "$MAILBOXES" | jq -r ".[$i].username" 2>/dev/null)
    
    # Пропускаем пустые или null значения
    if [ -z "$MAILBOX" ] || [ "$MAILBOX" = "null" ] || [ "$MAILBOX" = "undefined" ]; then
        ((INVALID++))
        continue
    fi
    
    # Получаем квоту в БАЙТАХ (это то, что хранит Mailcow)
    CURRENT_QUOTA_BYTES=$(echo "$MAILBOXES" | jq -r ".[$i].quota // \"0\"" 2>/dev/null)
    if [ -z "$CURRENT_QUOTA_BYTES" ] || [ "$CURRENT_QUOTA_BYTES" = "null" ]; then
        CURRENT_QUOTA_BYTES="0"
    fi
    
    # Переводим в МБ для отображения и сравнения
    if [ "$CURRENT_QUOTA_BYTES" = "0" ]; then
        CURRENT_QUOTA_MB="0"
        QUOTA_DISPLAY="безлимит"
    else
        CURRENT_QUOTA_MB=$((CURRENT_QUOTA_BYTES / 1024 / 1024))
        QUOTA_DISPLAY="${CURRENT_QUOTA_MB}MB"
    fi
    
    # Отображаем статус с правильными цветами
    if [ "$CURRENT_QUOTA_BYTES" = "0" ]; then
        # Безлимит - желтый цвет
        echo -e "  ${YELLOW}∞${NC} $MAILBOX: безлимит -> нужно установить ${TARGET_QUOTA_MB}MB (10G)"
        ((NEED_UPDATE++))
        ((UNLIMITED++))
        UPDATE_LIST+=("$MAILBOX")
    elif [ "$CURRENT_QUOTA_MB" -lt "$TARGET_QUOTA_MB" ] 2>/dev/null; then
        # Нужно увеличить - желтый цвет
        echo -e "  ${YELLOW}⬆${NC} $MAILBOX: ${CURRENT_QUOTA_MB}MB -> увеличить до ${TARGET_QUOTA_MB}MB (10G)"
        ((NEED_UPDATE++))
        UPDATE_LIST+=("$MAILBOX")
    else
        # Уже OK - зеленый цвет
        echo -e "  ${GREEN}✓${NC} $MAILBOX: ${CURRENT_QUOTA_MB}MB (уже >= ${TARGET_QUOTA_MB}MB)"
        ((ALREADY_OK++))
    fi
done

echo ""
echo -e "${YELLOW}Статистика:${NC}"
echo -e "  Всего ящиков: $COUNT"
echo -e "  Безлимитных: $UNLIMITED"
echo -e "  ${YELLOW}Нужно увеличить: $NEED_UPDATE${NC}"
echo -e "  ${GREEN}Уже OK: $ALREADY_OK${NC}"
echo -e "  Невалидных: $INVALID"

if [ "$NEED_UPDATE" -eq 0 ]; then
    echo -e "${GREEN}Все ящики уже имеют квоту >= ${TARGET_QUOTA_MB}MB (10G) или безлимит${NC}"
    exit 0
fi

# Запрашиваем подтверждение
echo -e "${YELLOW}Внимание: Будет установлена квота ${TARGET_QUOTA_MB}MB (10G) для $NEED_UPDATE ящиков!${NC}"
read -p "Продолжить? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${RED}Операция отменена${NC}"
    exit 1
fi

echo -e "${GREEN}Начинаем установку квоты...${NC}"

SUCCESS=0
FAILED=0

# Обновляем только те ящики, которые нуждаются в этом
for MAILBOX in "${UPDATE_LIST[@]}"; do
    echo -n "Устанавливаю квоту ${TARGET_QUOTA_MB}MB (10G) для $MAILBOX... "

    # Формируем JSON в том же формате, что и в disable_mailbox.sh
    # quota указывается в МБ (API Mailcow принимает в МБ)
    JSON_TMPL='"attr":{"quota":"'${TARGET_QUOTA_MB}'"},"items":["%MBOX%"]'
    JSON_DATA=$(echo ${JSON_TMPL} | sed "s/%MBOX%/${MAILBOX}/")

    # Отправляем запрос на изменение квоты
    RESPONSE=$(curl -s -X POST "https://${MC_SERVER}/api/v1/edit/mailbox" \
        -H "X-API-Key: ${API_RW_KEY}" \
        -H "Content-Type: application/json" \
        -d "{ ${JSON_DATA} }" 2>&1)

    # Проверяем результат
    if echo "$RESPONSE" | grep -q '"type":"success"'; then
        echo -e "${GREEN}OK${NC}"
        ((SUCCESS++))
    else
        echo -e "${RED}FAIL${NC}"
        echo "  Ответ API: $RESPONSE"
        ((FAILED++))
    fi

    # Небольшая задержка, чтобы не перегружать API
    sleep 0.3
done

# Выводим статистику
echo -e "${GREEN}========================${NC}"
echo -e "${GREEN}Операция завершена!${NC}"
echo -e "Всего ящиков: $COUNT"
echo -e "Уже имели квоту >= ${TARGET_QUOTA_MB}MB: ${GREEN}$ALREADY_OK${NC}"
echo -e "Успешно обновлено: ${GREEN}$SUCCESS${NC}"
echo -e "Ошибок: ${RED}$FAILED${NC}"
echo -e "Пропущено: $INVALID"

# Проверяем результат для обновленных ящиков (первые 5)
if [ ${#UPDATE_LIST[@]} -gt 0 ]; then
    echo -e "${YELLOW}Проверяем обновленные квоты (первые 5)...${NC}"
    CHECK_COUNT=0
    for MAILBOX in "${UPDATE_LIST[@]}"; do
        if [ $CHECK_COUNT -ge 5 ]; then
            break
        fi
        
        CHECK_INFO=$(curl -s -X GET "https://${MC_SERVER}/api/v1/get/mailbox/${MAILBOX}" \
            -H "X-API-Key: ${API_RW_KEY}" \
            -H "Content-Type: application/json" 2>/dev/null)
        
        if [ ! -z "$CHECK_INFO" ] && [ "$CHECK_INFO" != "null" ]; then
            NEW_QUOTA_BYTES=$(echo "$CHECK_INFO" | jq -r '.quota // "0"' 2>/dev/null)
            USED_BYTES=$(echo "$CHECK_INFO" | jq -r '.used // "0"' 2>/dev/null)
            
            if [ -z "$NEW_QUOTA_BYTES" ] || [ "$NEW_QUOTA_BYTES" = "null" ]; then
                NEW_QUOTA_BYTES="0"
            fi
            if [ -z "$USED_BYTES" ] || [ "$USED_BYTES" = "null" ]; then
                USED_BYTES="0"
            fi
            
            NEW_QUOTA_MB=$((NEW_QUOTA_BYTES / 1024 / 1024))
            USED_MB=$((USED_BYTES / 1024 / 1024))
            
            if [ "$NEW_QUOTA_MB" -ge "$TARGET_QUOTA_MB" ] 2>/dev/null; then
                echo -e "  ${GREEN}✓${NC} $MAILBOX: квота ${NEW_QUOTA_MB}MB (использовано ${USED_MB}MB)"
            else
                echo -e "  ${RED}✗${NC} $MAILBOX: квота ${NEW_QUOTA_MB}MB (использовано ${USED_MB}MB)"
            fi
            ((CHECK_COUNT++))
        fi
    done
fi

echo -e "${GREEN}Готово!${NC}"
