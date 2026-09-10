#!/bin/bash

# Скрипт для установки квоты 10G для всех почтовых ящиков через API Mailcow
# Использует тот же формат, что и disable_mailbox.sh

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
NC='\033[0m'

echo -e "${GREEN}=== Установка квоты 10G для всех почтовых ящиков ===${NC}"

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

COUNT=$(echo "$MAILBOXES" | jq '. | length')
echo -e "${GREEN}Найдено почтовых ящиков: $COUNT${NC}"

if [ "$COUNT" -eq 0 ]; then
    echo -e "${RED}Нет почтовых ящиков для обработки${NC}"
    exit 1
fi

# Показываем первые 5 ящиков для проверки
echo -e "${YELLOW}Первые 5 ящиков:${NC}"
for i in $(seq 0 $((COUNT < 5 ? COUNT-1 : 4))); do
    MAILBOX=$(echo "$MAILBOXES" | jq -r ".[$i].username")
    CURRENT_QUOTA=$(echo "$MAILBOXES" | jq -r ".[$i].quota // \"не установлена\"")
    echo "  $MAILBOX (текущая квота: $CURRENT_QUOTA MB)"
done

# Запрашиваем подтверждение
echo -e "${YELLOW}Внимание: Будет установлена квота 10G (10240 MB) для ВСЕХ почтовых ящиков!${NC}"
read -p "Продолжить? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${RED}Операция отменена${NC}"
    exit 1
fi

echo -e "${GREEN}Начинаем установку квоты...${NC}"

SUCCESS=0
FAILED=0
SKIPPED=0

# Проходим по всем ящикам
for i in $(seq 0 $((COUNT-1))); do
    MAILBOX=$(echo "$MAILBOXES" | jq -r ".[$i].username")
    
    if [ -z "$MAILBOX" ] || [ "$MAILBOX" = "null" ]; then
        ((SKIPPED++))
        continue
    fi
    
    echo -n "Устанавливаю квоту 10G для $MAILBOX... "
    
    # Формируем JSON в том же формате, что и в disable_mailbox.sh
    # quota указывается в MB, 10240 MB = 10 GB
    JSON_TMPL='"attr":{"quota":"10240"},"items":["%MBOX%"]'
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
echo -e "Успешно: ${GREEN}$SUCCESS${NC}"
echo -e "Ошибок: ${RED}$FAILED${NC}"
echo -e "Пропущено: $SKIPPED"

# Проверяем результат
echo -e "${YELLOW}Проверяем новые квоты (первые 5 ящиков)...${NC}"
for i in $(seq 0 $((COUNT < 5 ? COUNT-1 : 4))); do
    MAILBOX=$(echo "$MAILBOXES" | jq -r ".[$i].username")
    if [ -n "$MAILBOX" ] && [ "$MAILBOX" != "null" ]; then
        CHECK_INFO=$(curl -s -X GET "https://${MC_SERVER}/api/v1/get/mailbox/${MAILBOX}" \
            -H "X-API-Key: ${API_RW_KEY}" \
            -H "Content-Type: application/json")
        NEW_QUOTA=$(echo "$CHECK_INFO" | jq -r '.quota // "0"')
        USED=$(echo "$CHECK_INFO" | jq -r '.used // "0"')
        echo "$MAILBOX: квота ${NEW_QUOTA}MB (использовано ${USED}MB)"
    fi
done

echo -e "${GREEN}Готово!${NC}"
