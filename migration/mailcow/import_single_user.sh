#!/bin/bash

# ============================================================
# ИМПОРТ ОДНОГО ПОЛЬЗОВАТЕЛЯ ИЗ CSV В MAILCOW
# ============================================================
# Использование: ./import_single_user.sh user@domain.com mailcow_full_20260828.csv
# ============================================================

# Загружаем конфигурацию mailcow
. /root/mailcow/mailcow_config

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Проверяем аргументы
EMAIL_TO_IMPORT="${1}"
CSV_FILE="${2}"

if [ -z "${EMAIL_TO_IMPORT}" ] || [ -z "${CSV_FILE}" ]; then
    echo -e "${RED}❌ Ошибка: укажите email и CSV файл${NC}"
    echo ""
    echo "Использование: $0 <email> <csv_file>"
    echo ""
    echo "Пример: $0 user@domain.com mailcow_full_20260828.csv"
    echo ""
    echo "Формат CSV:"
    echo "email|password|displayName|aliases|quota|active|zimbraId"
    echo ""
    echo "Пример строки:"
    echo "user@domain.com|Pass123|Иван Петров|alias1@dom.com,alias2@dom.com|10240|1|uuid-123"
    exit 1
fi

# Проверяем существование CSV файла
if [ ! -f "${CSV_FILE}" ]; then
    echo -e "${RED}❌ Ошибка: CSV файл не найден: ${CSV_FILE}${NC}"
    exit 1
fi

# Создаем директорию для логов
LOG_DIR="/root/mailcow/import_logs"
mkdir -p ${LOG_DIR}
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="${LOG_DIR}/single_import_${EMAIL_TO_IMPORT}_${TIMESTAMP}.log"

# Функция логирования
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a ${LOG_FILE}
}

echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}ИМПОРТ ОДНОГО ПОЛЬЗОВАТЕЛЯ ИЗ CSV${NC}"
echo -e "${GREEN}==========================================${NC}"
log "🚀 Начало импорта: ${EMAIL_TO_IMPORT}"
log "📁 CSV файл: ${CSV_FILE}"

# Ищем пользователя в CSV
log "🔍 Ищем пользователя ${EMAIL_TO_IMPORT} в CSV..."

USER_LINE=$(grep "^${EMAIL_TO_IMPORT}|" "${CSV_FILE}" | head -n 1)

if [ -z "${USER_LINE}" ]; then
    echo -e "${RED}❌ Ошибка: пользователь ${EMAIL_TO_IMPORT} не найден в CSV файле${NC}"
    log "❌ Пользователь не найден в CSV"
    exit 1
fi

# Разбираем строку CSV
IFS='|' read -r EMAIL PASSWORD FIO ALIASES QUOTA ACTIVE ZIMBRA_ID <<< "${USER_LINE}"

# Проверяем обязательные поля
if [ -z "${EMAIL}" ] || [ -z "${PASSWORD}" ] || [ -z "${FIO}" ]; then
    echo -e "${RED}❌ Ошибка: в CSV отсутствуют обязательные поля (email, password, displayName)${NC}"
    log "❌ Отсутствуют обязательные поля"
    exit 1
fi

# Устанавливаем значения по умолчанию
QUOTA="${QUOTA:-10240}"  # По умолчанию 10G
ACTIVE="${ACTIVE:-1}"    # По умолчанию активен

echo -e "${YELLOW}📧 Найден пользователь:${NC}"
echo -e "  Email: ${GREEN}${EMAIL}${NC}"
echo -e "  ФИО: ${FIO}"
echo -e "  Квота: ${QUOTA}MB ($((${QUOTA}/1024)) GB)"
echo -e "  Активен: $([ "${ACTIVE}" = "1" ] && echo "${GREEN}Да${NC}" || echo "${RED}Нет${NC}")"
if [ ! -z "${ALIASES}" ] && [ "${ALIASES}" != "null" ]; then
    echo -e "  Алиасы: ${ALIASES}"
fi
echo ""

# Запрашиваем подтверждение
read -p "Продолжить импорт пользователя ${EMAIL}? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${RED}❌ Операция отменена${NC}"
    log "❌ Операция отменена пользователем"
    exit 1
fi

# Извлекаем домен и локальную часть
DOMAIN=$(echo "${EMAIL}" | awk -F "@" '{ print $NF }')
LOCAL_PART=$(echo "${EMAIL}" | awk -F "@" '{ print $1 }')

# Проверяем существование ящика
log "🔍 Проверяем существование ящика ${EMAIL}..."

EXISTING=$(curl -s -X 'GET' \
    -H "X-API-Key: ${API_RO_KEY}" \
    -H 'Content-Type: application/json' \
    "https://${MC_SERVER}/api/v1/get/mailbox/all/${DOMAIN}" 2>/dev/null | \
    jq -r ".[] | select(.username==\"${EMAIL}\").username" 2>/dev/null)

if [ ! -z "${EXISTING}" ] && [ "${EXISTING}" != "null" ]; then
    echo -e "${YELLOW}⚠️ Ящик ${EMAIL} уже существует${NC}"
    log "⚠️ Ящик ${EMAIL} уже существует, будет обновлён"
    ACTION="update"
else
    echo -e "${GREEN}✅ Ящик не существует, будет создан${NC}"
    log "✅ Ящик не существует, будет создан"
    ACTION="create"
fi

echo ""

# ============================================================
# ФУНКЦИЯ СОЗДАНИЯ ПОЧТОВОГО ЯЩИКА
# ============================================================
create_mailbox() {
    log "📝 Создаём ящик ${EMAIL}..."
    
    JSON_TMPL='"active": "%ACTIVE%", "domain": "%DOMAIN%", "local_part": "%MBOX%", "name": "%FIO%", "password": "%PASS%", "password2": "%PASS%", "quota": "%QUOTA%", "force_pw_update": "0", "tls_enforce_in": "1", "tls_enforce_out": "1"'
    
    JSON_DATA=$(echo ${JSON_TMPL} | \
        sed "s/%DOMAIN%/${DOMAIN}/" | \
        sed "s/%MBOX%/${LOCAL_PART}/" | \
        sed "s/%PASS%/${PASSWORD}/g" | \
        sed "s/%FIO%/${FIO}/" | \
        sed "s/%QUOTA%/${QUOTA}/" | \
        sed "s/%ACTIVE%/${ACTIVE}/")
    
    log "📤 Отправляем запрос на создание..."
    
    RESULT=$(curl -s -H "X-API-Key: ${API_RW_KEY}" \
        -H 'Content-Type: application/json' \
        -d "{ ${JSON_DATA} }" \
        "https://${MC_SERVER}/api/v1/add/mailbox" 2>&1)
    
    if [ $? -eq 0 ] && [[ ! "${RESULT}" =~ "error" ]]; then
        echo -e "${GREEN}✅ Ящик создан: ${EMAIL}${NC}"
        log "✅ Ящик создан: ${EMAIL}"
        echo "${EMAIL}|${PASSWORD}|${FIO}|${QUOTA}|${ACTIVE}" >> "${LOG_DIR}/created_${TIMESTAMP}.txt"
        return 0
    else
        echo -e "${RED}❌ Ошибка создания: ${RESULT}${NC}"
        log "❌ Ошибка создания: ${RESULT}"
        echo "${EMAIL}|${RESULT}" >> "${LOG_DIR}/errors_${TIMESTAMP}.txt"
        return 1
    fi
}

# ============================================================
# ФУНКЦИЯ ОБНОВЛЕНИЯ ПОЧТОВОГО ЯЩИКА
# ============================================================
update_mailbox() {
    log "📝 Обновляем ящик ${EMAIL}..."
    
    # Преобразуем активность
    [ "${ACTIVE}" = "1" ] && ACTIVE_STATUS="1" || ACTIVE_STATUS="0"
    
    JSON_TMPL='"attr":{"active":"%ACTIVE%","name":"%FIO%","quota":"%QUOTA%","password":"%PASS%","password2":"%PASS%"},"items":["%EMAIL%"]'
    
    JSON_DATA=$(echo ${JSON_TMPL} | \
        sed "s/%EMAIL%/${EMAIL}/" | \
        sed "s/%ACTIVE%/${ACTIVE_STATUS}/" | \
        sed "s/%FIO%/${FIO}/" | \
        sed "s/%PASS%/${PASSWORD}/g" | \
        sed "s/%QUOTA%/${QUOTA}/")
    
    log "📤 Отправляем запрос на обновление..."
    
    RESULT=$(curl -s -H "X-API-Key: ${API_RW_KEY}" \
        -H 'Content-Type: application/json' \
        -d "{ ${JSON_DATA} }" \
        "https://${MC_SERVER}/api/v1/edit/mailbox" 2>&1)
    
    if [ $? -eq 0 ] && [[ ! "${RESULT}" =~ "error" ]]; then
        echo -e "${GREEN}✅ Ящик обновлён: ${EMAIL}${NC}"
        log "✅ Ящик обновлён: ${EMAIL}"
        echo "${EMAIL}|${PASSWORD}|${FIO}|${QUOTA}|${ACTIVE}" >> "${LOG_DIR}/updated_${TIMESTAMP}.txt"
        return 0
    else
        echo -e "${RED}❌ Ошибка обновления: ${RESULT}${NC}"
        log "❌ Ошибка обновления: ${RESULT}"
        echo "${EMAIL}|${RESULT}" >> "${LOG_DIR}/errors_${TIMESTAMP}.txt"
        return 1
    fi
}

# ============================================================
# ФУНКЦИЯ СОЗДАНИЯ АЛИАСОВ
# ============================================================
create_alias() {
    local ALIAS="${1}"
    local GOTO="${2}"
    
    log "🔗 Добавляем алиас ${ALIAS} -> ${GOTO}"
    
    JSON_TMPL='"active": "1", "address": "%ALIAS%", "goto": "%GOTO%"'
    JSON_DATA=$(echo ${JSON_TMPL} | \
        sed "s/%ALIAS%/${ALIAS}/" | \
        sed "s/%GOTO%/${GOTO}/")
    
    RESULT=$(curl -s -H "X-API-Key: ${API_RW_KEY}" \
        -H 'Content-Type: application/json' \
        -d "{ ${JSON_DATA} }" \
        "https://${MC_SERVER}/api/v1/add/alias" 2>&1)
    
    if [ $? -eq 0 ] && [[ ! "${RESULT}" =~ "error" ]]; then
        echo -e "${GREEN}✅ Алиас добавлен: ${ALIAS} -> ${GOTO}${NC}"
        log "✅ Алиас добавлен: ${ALIAS} -> ${GOTO}"
        return 0
    else
        echo -e "${RED}❌ Ошибка добавления алиаса: ${RESULT}${NC}"
        log "❌ Ошибка добавления алиаса: ${RESULT}"
        return 1
    fi
}

# ============================================================
# ФУНКЦИЯ ОБНОВЛЕНИЯ АЛИАСА
# ============================================================
update_alias() {
    local ALIAS="${1}"
    local GOTO="${2}"
    
    # Проверяем текущий GOTO
    CURRENT_GOTO=$(curl -s -X 'GET' \
        -H "X-API-Key: ${API_RO_KEY}" \
        -H 'Content-Type: application/json' \
        "https://${MC_SERVER}/api/v1/get/alias/all" 2>/dev/null | \
        jq -r ".[] | select(.address==\"${ALIAS}\").goto" 2>/dev/null)
    
    # Если GOTO не изменился, пропускаем
    if [ "${CURRENT_GOTO}" = "${GOTO}" ]; then
        log "⏭️ Алиас ${ALIAS} уже верный, пропускаем"
        return 0
    fi
    
    JSON_TMPL='"attr":{"active":"1","goto":"%GOTO%"},"items":["%ALIAS%"]'
    JSON_DATA=$(echo ${JSON_TMPL} | \
        sed "s/%ALIAS%/${ALIAS}/" | \
        sed "s/%GOTO%/${GOTO}/")
    
    RESULT=$(curl -s -H "X-API-Key: ${API_RW_KEY}" \
        -H 'Content-Type: application/json' \
        -d "{ ${JSON_DATA} }" \
        "https://${MC_SERVER}/api/v1/edit/alias" 2>&1)
    
    if [ $? -eq 0 ] && [[ ! "${RESULT}" =~ "error" ]]; then
        echo -e "${GREEN}✅ Алиас обновлён: ${ALIAS} -> ${GOTO}${NC}"
        log "✅ Алиас обновлён: ${ALIAS} -> ${GOTO}"
        return 0
    else
        echo -e "${RED}❌ Ошибка обновления алиаса: ${RESULT}${NC}"
        log "❌ Ошибка обновления алиаса: ${RESULT}"
        return 1
    fi
}

# ============================================================
# ФУНКЦИЯ ОБРАБОТКИ АЛИАСОВ
# ============================================================
process_aliases() {
    if [ -z "${ALIASES}" ] || [ "${ALIASES}" = "null" ]; then
        log "ℹ️ Нет алиасов для обработки"
        return 0
    fi
    
    log "🔗 Обрабатываем алиасы: ${ALIASES}"
    
    # Разделяем алиасы по запятой
    IFS=',' read -ra ALIAS_ARRAY <<< "${ALIASES}"
    
    for alias in "${ALIAS_ARRAY[@]}"; do
        # Удаляем пробелы
        alias=$(echo "$alias" | xargs)
        
        # Пропускаем пустые алиасы и алиас равный основному ящику
        if [ -z "${alias}" ] || [ "${alias}" = "${EMAIL}" ]; then
            continue
        fi
        
        # Проверяем существование алиаса
        EXISTING_ALIAS=$(curl -s -X 'GET' \
            -H "X-API-Key: ${API_RO_KEY}" \
            -H 'Content-Type: application/json' \
            "https://${MC_SERVER}/api/v1/get/alias/all" 2>/dev/null | \
            jq -r ".[] | select(.address==\"${alias}\").address" 2>/dev/null)
        
        if [ ! -z "${EXISTING_ALIAS}" ] && [ "${EXISTING_ALIAS}" != "null" ]; then
            update_alias "${alias}" "${EMAIL}"
        else
            create_alias "${alias}" "${EMAIL}"
        fi
    done
}

# ============================================================
# ОСНОВНАЯ ЛОГИКА
# ============================================================

# Создаём или обновляем ящик
if [ "${ACTION}" = "create" ]; then
    if create_mailbox; then
        # Обрабатываем алиасы
        process_aliases
    else
        exit 1
    fi
else
    if update_mailbox; then
        # Обрабатываем алиасы
        process_aliases
    else
        exit 1
    fi
fi

# ============================================================
# ПРОВЕРКА РЕЗУЛЬТАТА
# ============================================================
echo ""
echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}ПРОВЕРКА СОЗДАННОГО ЯЩИКА${NC}"
echo -e "${GREEN}==========================================${NC}"

# Проверяем информацию о ящике
MAILBOX_INFO=$(curl -s -X 'GET' \
    -H "X-API-Key: ${API_RO_KEY}" \
    -H 'Content-Type: application/json' \
    "https://${MC_SERVER}/api/v1/get/mailbox/${EMAIL}" 2>/dev/null)

if [ ! -z "${MAILBOX_INFO}" ] && [ "${MAILBOX_INFO}" != "null" ]; then
    echo -e "${GREEN}✅ Информация о ящике:${NC}"
    echo "$MAILBOX_INFO" | jq '{
        username: .username,
        name: .name,
        quota: .quota,
        used: .used,
        active: .active,
        domain: .domain
    }'
    
    # Сохраняем информацию
    echo "$MAILBOX_INFO" | jq '.' > "${LOG_DIR}/mailbox_info_${EMAIL}_${TIMESTAMP}.json"
    log "📁 Информация сохранена в: ${LOG_DIR}/mailbox_info_${EMAIL}_${TIMESTAMP}.json"
else
    echo -e "${RED}❌ Не удалось получить информацию о ящике${NC}"
    log "❌ Не удалось получить информацию о ящике"
fi

# Проверяем алиасы
if [ ! -z "${ALIASES}" ] && [ "${ALIASES}" != "null" ]; then
    echo ""
    echo -e "${YELLOW}Проверка алиасов:${NC}"
    IFS=',' read -ra ALIAS_ARRAY <<< "${ALIASES}"
    for alias in "${ALIAS_ARRAY[@]}"; do
        alias=$(echo "$alias" | xargs)
        if [ ! -z "${alias}" ] && [ "${alias}" != "${EMAIL}" ]; then
            ALIAS_CHECK=$(curl -s -X 'GET' \
                -H "X-API-Key: ${API_RO_KEY}" \
                -H 'Content-Type: application/json' \
                "https://${MC_SERVER}/api/v1/get/alias/all" 2>/dev/null | \
                jq -r ".[] | select(.address==\"${alias}\").address" 2>/dev/null)
            
            if [ ! -z "${ALIAS_CHECK}" ] && [ "${ALIAS_CHECK}" != "null" ]; then
                echo -e "  ${GREEN}✅${NC} ${alias} -> ${EMAIL}"
            else
                echo -e "  ${RED}❌${NC} ${alias} не найден"
            fi
        fi
    done
fi

# ============================================================
# ИТОГОВЫЙ ОТЧЁТ
# ============================================================
echo ""
echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}✅ ОПЕРАЦИЯ ЗАВЕРШЕНА${NC}"
echo -e "${GREEN}==========================================${NC}"
echo -e "📧 Ящик: ${EMAIL}"
echo -e "👤 ФИО: ${FIO}"
echo -e "💾 Квота: ${QUOTA}MB ($((${QUOTA}/1024)) GB)"
echo -e "🔒 Статус: $([ "${ACTIVE}" = "1" ] && echo "Активен" || echo "Заблокирован")"
if [ ! -z "${ALIASES}" ] && [ "${ALIASES}" != "null" ]; then
    echo -e "🔗 Алиасы: ${ALIASES}"
fi
echo -e "📁 Лог: ${LOG_FILE}"
echo -e "${GREEN}==========================================${NC}"

log "✅ ИМПОРТ ЗАВЕРШЁН УСПЕШНО"

exit 0
