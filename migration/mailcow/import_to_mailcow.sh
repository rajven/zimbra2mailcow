#!/bin/bash

# ============================================================
# ИМПОРТ ПОЛЬЗОВАТЕЛЕЙ ИЗ ZIMBRA В MAILCOW
# ============================================================
# Использование: ./import_to_mailcow.sh mailcow_full_20260828.csv
# ============================================================

# Загружаем конфигурацию mailcow
. /root/mailcow/mailcow_config

# Проверяем аргументы
CSV_FILE="${1}"
if [ -z "${CSV_FILE}" ] || [ ! -f "${CSV_FILE}" ]; then
    echo "❌ Ошибка: укажите CSV файл для импорта"
    echo "Пример: $0 mailcow_full_20260828.csv"
    exit 1
fi

# Создаем директории для логов
LOG_DIR="/root/mailcow/import_logs"
mkdir -p ${LOG_DIR}
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="${LOG_DIR}/import_${TIMESTAMP}.log"
ERROR_FILE="${LOG_DIR}/errors_${TIMESTAMP}.log"
SUCCESS_FILE="${LOG_DIR}/success_${TIMESTAMP}.log"

# Функция логирования
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a ${LOG_FILE}
}

log "🚀 НАЧАЛО ИМПОРТА"
log "📁 Файл: ${CSV_FILE}"
log "📝 Лог: ${LOG_FILE}"

# Счётчики
TOTAL=0
CREATED=0
UPDATED=0
FAILED=0
SKIPPED=0

# ============================================================
# ФУНКЦИЯ СОЗДАНИЯ/ОБНОВЛЕНИЯ ПОЧТОВОГО ЯЩИКА
# ============================================================
create_mailbox() {
    local EMAIL="${1}"
    local PASSWORD="${2}"
    local FIO="${3}"
    local QUOTA="${4}"
    local ACTIVE="${5}"
    
    # Извлекаем домен и локальную часть
    DOMAIN=$(echo "${EMAIL}" | awk -F "@" '{ print $NF }')
    LOCAL_PART=$(echo "${EMAIL}" | awk -F "@" '{ print $1 }')
    
    # Проверяем существование ящика
    EXISTING=$(curl -s -X 'GET' -H "X-API-Key: ${API_RO_KEY}" -H 'Content-Type: application/json' \
        "https://${MC_SERVER}/api/v1/get/mailbox/all/${DOMAIN}" | jq -r ".[] | select(.username==\"${EMAIL}\").username" 2>/dev/null)
    
    if [ ! -z "${EXISTING}" ]; then
        log "⚠️ Ящик ${EMAIL} уже существует, обновляем..."
        update_mailbox "${EMAIL}" "${PASSWORD}" "${FIO}" "${QUOTA}" "${ACTIVE}"
        return $?
    fi
    
    # Формируем JSON для создания
    JSON_TMPL='"active": "1", "domain": "%DOMAIN%", "local_part": "%MBOX%", "name": "%FIO%", "password": "%PASS%", "password2": "%PASS%","quota": "%QUOTA%", "force_pw_update": "0", "tls_enforce_in": "1", "tls_enforce_out": "1"'
    
    # Устанавливаем квоту
    if [ -z "${QUOTA}" ] || [ "${QUOTA}" = "0" ]; then
        QUOTA="10240"  # Дефолтная квота 1GB
    fi
    
    # Формируем данные
    JSON_DATA=$(echo ${JSON_TMPL} | sed "s/%DOMAIN%/${DOMAIN}/" | sed "s/%MBOX%/${LOCAL_PART}/" | sed "s/%PASS%/${PASSWORD}/g" | sed "s/%FIO%/${FIO}/" | sed "s/%QUOTA%/${QUOTA}/")
    
    # Отправляем запрос
    RESULT=$(curl -s -H "X-API-Key: ${API_RW_KEY}" -H 'Content-Type: application/json' \
        -d "{ ${JSON_DATA} }" "https://${MC_SERVER}/api/v1/add/mailbox" 2>&1)
    
    if [ $? -eq 0 ] && [[ ! "${RESULT}" =~ "error" ]]; then
        log "✅ Создан: ${EMAIL} (${FIO})"
        echo "${EMAIL}" >> ${SUCCESS_FILE}
        return 0
    else
        log "❌ Ошибка создания ${EMAIL}: ${RESULT}"
        echo "${EMAIL}|${RESULT}" >> ${ERROR_FILE}
        return 1
    fi
}

# ============================================================
# ФУНКЦИЯ ОБНОВЛЕНИЯ ПОЧТОВОГО ЯЩИКА
# ============================================================
update_mailbox() {
    local EMAIL="${1}"
    local PASSWORD="${2}"
    local FIO="${3}"
    local QUOTA="${4}"
    local ACTIVE="${5}"
    
    # Преобразуем активность
    [ "${ACTIVE}" = "1" ] && ACTIVE_STATUS="1" || ACTIVE_STATUS="0"
    
    # Формируем JSON для обновления
    JSON_TMPL='"attr":{"active":"%ACTIVE%","name":"%FIO%","quota":"%QUOTA%","password":"%PASS%","password2":"%PASS%"},"items":["%EMAIL%"]'
    
    JSON_DATA=$(echo ${JSON_TMPL} | sed "s/%EMAIL%/${EMAIL}/" | sed "s/%ACTIVE%/${ACTIVE_STATUS}/" | sed "s/%FIO%/${FIO}/" | sed "s/%PASS%/${PASSWORD}/g" | sed "s/%QUOTA%/${QUOTA}/")
    
    RESULT=$(curl -s -H "X-API-Key: ${API_RW_KEY}" -H 'Content-Type: application/json' \
        -d "{ ${JSON_DATA} }" "https://${MC_SERVER}/api/v1/edit/mailbox" 2>&1)
    
    if [ $? -eq 0 ] && [[ ! "${RESULT}" =~ "error" ]]; then
        log "🔄 Обновлён: ${EMAIL}"
        return 0
    else
        log "❌ Ошибка обновления ${EMAIL}: ${RESULT}"
        echo "${EMAIL}|${RESULT}" >> ${ERROR_FILE}
        return 1
    fi
}

# ============================================================
# ФУНКЦИЯ СОЗДАНИЯ АЛИАСОВ
# ============================================================
create_alias() {
    local ALIAS="${1}"
    local GOTO="${2}"
    
    # Проверяем, существует ли уже алиас
    EXISTING=$(curl -s -X 'GET' -H "X-API-Key: ${API_RO_KEY}" -H 'Content-Type: application/json' \
        "https://${MC_SERVER}/api/v1/get/alias/all" | jq -r ".[] | select(.address==\"${ALIAS}\").address" 2>/dev/null)
    
    if [ ! -z "${EXISTING}" ]; then
        log "⚠️ Алиас ${ALIAS} уже существует, обновляем..."
        update_alias "${ALIAS}" "${GOTO}"
        return $?
    fi
    
    JSON_TMPL='"active": "1", "address": "%ALIAS%", "goto": "%GOTO%"'
    JSON_DATA=$(echo ${JSON_TMPL} | sed "s/%ALIAS%/${ALIAS}/" | sed "s/%GOTO%/${GOTO}/")
    
    RESULT=$(curl -s -H "X-API-Key: ${API_RW_KEY}" -H 'Content-Type: application/json' \
        -d "{ ${JSON_DATA} }" "https://${MC_SERVER}/api/v1/add/alias" 2>&1)
    
    if [ $? -eq 0 ] && [[ ! "${RESULT}" =~ "error" ]]; then
        log "🔗 Алиас добавлен: ${ALIAS} -> ${GOTO}"
        return 0
    else
        log "❌ Ошибка создания алиаса ${ALIAS}: ${RESULT}"
        echo "${ALIAS}|${RESULT}" >> ${ERROR_FILE}
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
    CURRENT_GOTO=$(curl -s -X 'GET' -H "X-API-Key: ${API_RO_KEY}" -H 'Content-Type: application/json' \
        "https://${MC_SERVER}/api/v1/get/alias/all" | jq -r ".[] | select(.address==\"${ALIAS}\").goto" 2>/dev/null)
    
    # Если GOTO не изменился, пропускаем
    if [ "${CURRENT_GOTO}" = "${GOTO}" ]; then
        log "⏭️ Алиас ${ALIAS} уже верный, пропускаем"
        return 0
    fi
    
    JSON_TMPL='"attr":{"active":"1","goto":"%GOTO%"},"items":["%ALIAS%"]'
    JSON_DATA=$(echo ${JSON_TMPL} | sed "s/%ALIAS%/${ALIAS}/" | sed "s/%GOTO%/${GOTO}/")
    
    RESULT=$(curl -s -H "X-API-Key: ${API_RW_KEY}" -H 'Content-Type: application/json' \
        -d "{ ${JSON_DATA} }" "https://${MC_SERVER}/api/v1/edit/alias" 2>&1)
    
    if [ $? -eq 0 ] && [[ ! "${RESULT}" =~ "error" ]]; then
        log "🔄 Алиас обновлён: ${ALIAS} -> ${GOTO}"
        return 0
    else
        log "❌ Ошибка обновления алиаса ${ALIAS}: ${RESULT}"
        return 1
    fi
}

# ============================================================
# ФУНКЦИЯ БЛОКИРОВКИ/РАЗБЛОКИРОВКИ ЯЩИКА
# ============================================================
set_mailbox_status() {
    local EMAIL="${1}"
    local ACTIVE="${2}"
    
    [ "${ACTIVE}" = "1" ] && ACTIVE_STATUS="1" || ACTIVE_STATUS="0"
    
    JSON_TMPL='"attr":{"active":"%ACTIVE%","sogo_access":"%ACTIVE%"},"items":["%EMAIL%"]'
    JSON_DATA=$(echo ${JSON_TMPL} | sed "s/%EMAIL%/${EMAIL}/" | sed "s/%ACTIVE%/${ACTIVE_STATUS}/g")
    
    RESULT=$(curl -s -H "X-API-Key: ${API_RW_KEY}" -H 'Content-Type: application/json' \
        -d "{ ${JSON_DATA} }" "https://${MC_SERVER}/api/v1/edit/mailbox" 2>&1)
    
    if [ $? -eq 0 ] && [[ ! "${RESULT}" =~ "error" ]]; then
        log "🔒 Статус ${EMAIL}: $([ "${ACTIVE}" = "1" ] && echo "активен" || echo "заблокирован")"
        return 0
    else
        log "❌ Ошибка изменения статуса ${EMAIL}: ${RESULT}"
        return 1
    fi
}

# ============================================================
# ОСНОВНАЯ ЛОГИКА ИМПОРТА
# ============================================================
log "📊 Начинаем обработку файла..."

# Читаем CSV (пропускаем заголовок)
tail -n +2 "${CSV_FILE}" | while IFS='|' read -r email password displayName aliases quota active zimbraId; do
    # Пропускаем пустые строки
    [ -z "${email}" ] && continue
    
    TOTAL=$((TOTAL + 1))
    
    log ""
    log "---------- [${TOTAL}] Обработка: ${email} ----------"
    
    # Создаём или обновляем ящик
    if create_mailbox "${email}" "${password}" "${displayName}" "${quota}" "${active}"; then
        CREATED=$((CREATED + 1))
        
        # Если есть алиасы, создаём их
        if [ ! -z "${aliases}" ]; then
            # Разделяем алиасы по запятой
            IFS=',' read -ra ALIAS_ARRAY <<< "${aliases}"
            for alias in "${ALIAS_ARRAY[@]}"; do
                # Проверяем, что алиас не равен основному ящику
                if [ "${alias}" != "${email}" ]; then
                    create_alias "${alias}" "${email}"
                fi
            done
        fi
    else
        FAILED=$((FAILED + 1))
    fi
    
    # Небольшая задержка, чтобы не перегружать API
    sleep 0.5
done

# ============================================================
# ИТОГОВЫЙ ОТЧЁТ
# ============================================================
log ""
log "=========================================="
log "✅ ИМПОРТ ЗАВЕРШЁН"
log "=========================================="
log "📊 Всего обработано: ${TOTAL}"
log "✅ Создано/обновлено: ${CREATED}"
log "❌ Ошибок: ${FAILED}"
log "⏭️ Пропущено: ${SKIPPED}"
log ""
log "📁 Лог: ${LOG_FILE}"
log "❌ Ошибки: ${ERROR_FILE}"
log "✅ Успешные: ${SUCCESS_FILE}"
log "=========================================="

# Создаём краткий отчёт о паролях
PASS_REPORT="${LOG_DIR}/passwords_${TIMESTAMP}.txt"
log "🔑 Список созданных учётных записей с паролями сохранён в: ${PASS_REPORT}"

# Собираем только созданные ящики с паролями
tail -n +2 "${CSV_FILE}" | while IFS='|' read -r email password displayName aliases quota active zimbraId; do
    if grep -q "^${email}$" ${SUCCESS_FILE} 2>/dev/null; then
        echo "${email} | ${password} | ${displayName}" >> ${PASS_REPORT}
    fi
done

exit 0
