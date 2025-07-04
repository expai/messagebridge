#!/bin/bash

# MessageBridge Database Statistics Script
# Автор: MessageBridge Team
# Описание: Скрипт для мониторинга и анализа базы данных сообщений

set -euo pipefail

# Настройки по умолчанию
DB_PATH="/var/lib/messagebridge/messages.db"
DEFAULT_LIMIT=20
DEFAULT_PAGE=1

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Функция для отображения помощи
show_help() {
    cat << EOF
🔍 MessageBridge Database Statistics Tool

ИСПОЛЬЗОВАНИЕ:
    $0 [ОПЦИИ]

ОПЦИИ:
    -h, --help              Показать эту справку
    -d, --database PATH     Путь к базе данных (по умолчанию: $DB_PATH)
    
РЕЖИМЫ ПРОСМОТРА:
    --summary               Общая статистика (по умолчанию)
    --messages              Показать сообщения с пагинацией
    --status STATUS         Фильтр по статусу (pending, sent, failed, retrying)
    --queue QUEUE           Фильтр по очереди
    --message-id ID         Детальная информация о сообщении
    --failed-details        Детальная статистика ошибок
    --retry-analysis        Анализ повторных попыток
    --performance           Анализ производительности
    --cleanup-suggestions   Предложения по очистке БД

ОПЦИИ ПАГИНАЦИИ:
    --page N                Номер страницы (по умолчанию: $DEFAULT_PAGE)
    --limit N               Количество записей на странице (по умолчанию: $DEFAULT_LIMIT)

ОПЦИИ ВЫВОДА:
    --json                  Вывод в формате JSON
    --csv                   Вывод в формате CSV
    --no-color              Отключить цветной вывод

ПРИМЕРЫ:
    $0                                          # Общая статистика
    $0 --messages --page 2 --limit 10          # Вторая страница сообщений (10 записей)
    $0 --status pending                         # Только pending сообщения
    $0 --failed-details                         # Детальная статистика ошибок
    $0 --message-id "msg-123"                   # Информация о конкретном сообщении
    $0 --queue payments --json                  # JSON статистика для очереди payments
    $0 --retry-analysis                         # Анализ повторных попыток
    $0 --performance                            # Анализ производительности системы

EOF
}

# Функция для проверки существования базы данных
check_database() {
    if [[ ! -f "$DB_PATH" ]]; then
        echo -e "${RED}❌ База данных не найдена: $DB_PATH${NC}" >&2
        echo -e "${YELLOW}💡 Убедитесь что MessageBridge запущен и создал базу данных${NC}" >&2
        exit 1
    fi
    
    if ! command -v sqlite3 &> /dev/null; then
        echo -e "${RED}❌ sqlite3 не установлен${NC}" >&2
        echo -e "${YELLOW}💡 Установите: sudo apt install sqlite3 (Ubuntu/Debian) или sudo pacman -S sqlite (Arch)${NC}" >&2
        exit 1
    fi
}

# Функция для выполнения SQL запроса
execute_sql() {
    local query="$1"
    local format="${2:-table}"
    
    case "$format" in
        "json")
            sqlite3 -json "$DB_PATH" "$query"
            ;;
        "csv")
            sqlite3 -csv "$DB_PATH" "$query"
            ;;
        "table")
            sqlite3 -header -column "$DB_PATH" "$query"
            ;;
        *)
            sqlite3 "$DB_PATH" "$query"
            ;;
    esac
}

# Функция для отображения общей статистики
show_summary() {
    local format="$1"
    
    if [[ "$format" == "json" ]]; then
        cat << EOF
{
  "database_info": $(execute_sql "SELECT 
    (SELECT COUNT(*) FROM messages) as total_messages,
    (SELECT COUNT(*) FROM messages WHERE status = 'pending') as pending,
    (SELECT COUNT(*) FROM messages WHERE status = 'sent') as sent,
    (SELECT COUNT(*) FROM messages WHERE status = 'failed') as failed,
    (SELECT COUNT(*) FROM messages WHERE status = 'retrying') as retrying,
    (SELECT ROUND(AVG(retries), 2) FROM messages WHERE retries > 0) as avg_retries,
    (SELECT MAX(retries) FROM messages) as max_retries,
    (SELECT COUNT(DISTINCT queue) FROM messages) as unique_queues,
    (SELECT datetime(MIN(created_at), 'localtime') FROM messages) as oldest_message,
    (SELECT datetime(MAX(created_at), 'localtime') FROM messages) as newest_message" json),
  "queue_stats": $(execute_sql "SELECT queue, COUNT(*) as count FROM messages GROUP BY queue ORDER BY count DESC" json),
  "status_by_queue": $(execute_sql "SELECT queue, status, COUNT(*) as count FROM messages GROUP BY queue, status ORDER BY queue, status" json)
}
EOF
        return
    fi
    
    echo -e "${CYAN}📊 ОБЩАЯ СТАТИСТИКА БАЗЫ ДАННЫХ${NC}"
    echo "═══════════════════════════════════════════════════════════════"
    
    # Основная статистика
    local stats=$(execute_sql "SELECT 
        (SELECT COUNT(*) FROM messages) as total,
        (SELECT COUNT(*) FROM messages WHERE status = 'pending') as pending,
        (SELECT COUNT(*) FROM messages WHERE status = 'sent') as sent,
        (SELECT COUNT(*) FROM messages WHERE status = 'failed') as failed,
        (SELECT COUNT(*) FROM messages WHERE status = 'retrying') as retrying,
        (SELECT ROUND(AVG(retries), 2) FROM messages WHERE retries > 0) as avg_retries,
        (SELECT MAX(retries) FROM messages) as max_retries,
        (SELECT COUNT(DISTINCT queue) FROM messages) as queues" "raw")
    
    local total=$(echo "$stats" | cut -d'|' -f1)
    local pending=$(echo "$stats" | cut -d'|' -f2)
    local sent=$(echo "$stats" | cut -d'|' -f3)
    local failed=$(echo "$stats" | cut -d'|' -f4)
    local retrying=$(echo "$stats" | cut -d'|' -f5)
    local avg_retries=$(echo "$stats" | cut -d'|' -f6)
    local max_retries=$(echo "$stats" | cut -d'|' -f7)
    local queues=$(echo "$stats" | cut -d'|' -f8)
    
    echo -e "${BLUE}🔢 Общее количество сообщений:${NC} ${YELLOW}$total${NC}"
    echo ""
    
    echo -e "${GREEN}📈 СТАТИСТИКА ПО СТАТУСАМ:${NC}"
    echo "├─ 🟡 Ожидающие (pending):     $pending"
    echo "├─ 🟢 Отправленные (sent):     $sent"
    echo "├─ 🔴 Неудачные (failed):      $failed"
    echo "└─ 🟠 Повторные (retrying):    $retrying"
    echo ""
    
    echo -e "${MAGENTA}🔄 СТАТИСТИКА ПОВТОРОВ:${NC}"
    echo "├─ Среднее количество попыток: ${avg_retries:-0}"
    echo "├─ Максимальное количество:    ${max_retries:-0}"
    echo "└─ Уникальных очередей:        $queues"
    echo ""
    
    # Статистика по очередям
    echo -e "${CYAN}📋 СТАТИСТИКА ПО ОЧЕРЕДЯМ:${NC}"
    execute_sql "SELECT 
        queue as 'Очередь',
        COUNT(*) as 'Всего',
        SUM(CASE WHEN status = 'pending' THEN 1 ELSE 0 END) as 'Ожидает',
        SUM(CASE WHEN status = 'sent' THEN 1 ELSE 0 END) as 'Отправлено',
        SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END) as 'Ошибки',
        SUM(CASE WHEN status = 'retrying' THEN 1 ELSE 0 END) as 'Повторы'
    FROM messages 
    GROUP BY queue 
    ORDER BY COUNT(*) DESC"
    echo ""
    
    # Временная статистика
    echo -e "${YELLOW}⏰ ВРЕМЕННАЯ СТАТИСТИКА:${NC}"
    execute_sql "SELECT 
        'Самое старое сообщение' as 'Параметр',
        datetime(MIN(created_at), 'localtime') as 'Значение'
    FROM messages
    UNION ALL
    SELECT 
        'Самое новое сообщение',
        datetime(MAX(created_at), 'localtime')
    FROM messages
    UNION ALL
    SELECT 
        'Размер базы данных',
        ROUND(page_count * page_size / 1024.0 / 1024.0, 2) || ' MB'
    FROM pragma_page_count(), pragma_page_size()"
}

# Функция для отображения сообщений с пагинацией
show_messages() {
    local page="$1"
    local limit="$2"
    local status_filter="$3"
    local queue_filter="$4"
    local format="$5"
    
    local offset=$((($page - 1) * $limit))
    local where_clause=""
    
    # Построение WHERE clause
    local conditions=()
    if [[ -n "$status_filter" ]]; then
        conditions+=("status = '$status_filter'")
    fi
    if [[ -n "$queue_filter" ]]; then
        conditions+=("queue = '$queue_filter'")
    fi
    
    if [[ ${#conditions[@]} -gt 0 ]]; then
        where_clause="WHERE $(IFS=' AND '; echo "${conditions[*]}")"
    fi
    
    # Подсчет общего количества
    local total=$(execute_sql "SELECT COUNT(*) FROM messages $where_clause" "raw")
    local total_pages=$(( ($total + $limit - 1) / $limit ))
    
    if [[ "$format" == "json" ]]; then
        execute_sql "SELECT 
            id, queue, status, retries, 
            datetime(created_at, 'localtime') as created_at,
            datetime(updated_at, 'localtime') as updated_at,
            error
        FROM messages 
        $where_clause 
        ORDER BY created_at DESC 
        LIMIT $limit OFFSET $offset" json
        return
    fi
    
    echo -e "${CYAN}📝 СООБЩЕНИЯ (страница $page из $total_pages, всего: $total)${NC}"
    echo "═══════════════════════════════════════════════════════════════"
    
    if [[ -n "$status_filter" ]]; then
        echo -e "🔍 Фильтр по статусу: ${YELLOW}$status_filter${NC}"
    fi
    if [[ -n "$queue_filter" ]]; then
        echo -e "🔍 Фильтр по очереди: ${YELLOW}$queue_filter${NC}"
    fi
    echo ""
    
    execute_sql "SELECT 
        SUBSTR(id, 1, 12) || '...' as 'ID',
        queue as 'Очередь',
        status as 'Статус',
        retries as 'Попытки',
        datetime(created_at, 'localtime') as 'Создано',
        CASE 
            WHEN LENGTH(error) > 50 THEN SUBSTR(error, 1, 47) || '...'
            ELSE COALESCE(error, '')
        END as 'Ошибка'
    FROM messages 
    $where_clause 
    ORDER BY created_at DESC 
    LIMIT $limit OFFSET $offset"
    
    echo ""
    echo -e "${BLUE}📄 Навигация: страница $page из $total_pages${NC}"
    if [[ $page -lt $total_pages ]]; then
        echo -e "   Следующая страница: ${YELLOW}$0 --messages --page $((page + 1)) --limit $limit${NC}"
    fi
    if [[ $page -gt 1 ]]; then
        echo -e "   Предыдущая страница: ${YELLOW}$0 --messages --page $((page - 1)) --limit $limit${NC}"
    fi
}

# Функция для отображения детальной информации о сообщении
show_message_details() {
    local message_id="$1"
    local format="$2"
    
    local count=$(execute_sql "SELECT COUNT(*) FROM messages WHERE id = '$message_id'" "raw")
    
    if [[ "$count" -eq 0 ]]; then
        echo -e "${RED}❌ Сообщение с ID '$message_id' не найдено${NC}" >&2
        return 1
    fi
    
    if [[ "$format" == "json" ]]; then
        execute_sql "SELECT 
            id, path, queue, body, headers, timestamp,
            retries, status, error,
            datetime(created_at, 'localtime') as created_at,
            datetime(updated_at, 'localtime') as updated_at,
            datetime(next_retry_at, 'localtime') as next_retry_at
        FROM messages WHERE id = '$message_id'" json
        return
    fi
    
    echo -e "${CYAN}🔍 ДЕТАЛЬНАЯ ИНФОРМАЦИЯ О СООБЩЕНИИ${NC}"
    echo "═══════════════════════════════════════════════════════════════"
    
    execute_sql "SELECT 
        'ID' as 'Параметр', id as 'Значение' FROM messages WHERE id = '$message_id'
    UNION ALL SELECT 'Путь', path FROM messages WHERE id = '$message_id'
    UNION ALL SELECT 'Очередь', queue FROM messages WHERE id = '$message_id'
    UNION ALL SELECT 'Статус', status FROM messages WHERE id = '$message_id'
    UNION ALL SELECT 'Попытки', CAST(retries as TEXT) FROM messages WHERE id = '$message_id'
    UNION ALL SELECT 'Создано', datetime(created_at, 'localtime') FROM messages WHERE id = '$message_id'
    UNION ALL SELECT 'Обновлено', datetime(updated_at, 'localtime') FROM messages WHERE id = '$message_id'
    UNION ALL SELECT 'Следующая попытка', COALESCE(datetime(next_retry_at, 'localtime'), 'Не запланирована') FROM messages WHERE id = '$message_id'"
    
    echo ""
    echo -e "${YELLOW}📋 ЗАГОЛОВКИ:${NC}"
    execute_sql "SELECT headers FROM messages WHERE id = '$message_id'" "raw"
    
    echo ""
    echo -e "${YELLOW}📄 ТЕЛО СООБЩЕНИЯ:${NC}"
    local body=$(execute_sql "SELECT SUBSTR(body, 1, 500) FROM messages WHERE id = '$message_id'" "raw")
    echo "$body"
    if [[ ${#body} -eq 500 ]]; then
        echo "... (обрезано, показаны первые 500 символов)"
    fi
    
    echo ""
    echo -e "${RED}❌ ОШИБКА:${NC}"
    local error=$(execute_sql "SELECT COALESCE(error, 'Нет ошибок') FROM messages WHERE id = '$message_id'" "raw")
    echo "$error"
}

# Функция для анализа ошибок
show_failed_details() {
    local format="$1"
    
    if [[ "$format" == "json" ]]; then
        execute_sql "SELECT 
            error,
            COUNT(*) as count,
            AVG(retries) as avg_retries,
            MAX(retries) as max_retries,
            GROUP_CONCAT(queue) as affected_queues
        FROM messages 
        WHERE status IN ('failed', 'retrying') AND error IS NOT NULL
        GROUP BY error 
        ORDER BY count DESC" json
        return
    fi
    
    echo -e "${RED}🚨 ДЕТАЛЬНАЯ СТАТИСТИКА ОШИБОК${NC}"
    echo "═══════════════════════════════════════════════════════════════"
    
    local failed_count=$(execute_sql "SELECT COUNT(*) FROM messages WHERE status IN ('failed', 'retrying')" "raw")
    echo -e "${BLUE}📊 Всего сообщений с ошибками: ${YELLOW}$failed_count${NC}"
    echo ""
    
    echo -e "${YELLOW}🔥 ТОП ОШИБОК:${NC}"
    execute_sql "SELECT 
        CASE 
            WHEN LENGTH(error) > 60 THEN SUBSTR(error, 1, 57) || '...'
            ELSE error
        END as 'Ошибка',
        COUNT(*) as 'Количество',
        ROUND(AVG(retries), 1) as 'Сред.попытки',
        MAX(retries) as 'Макс.попытки'
    FROM messages 
    WHERE status IN ('failed', 'retrying') AND error IS NOT NULL
    GROUP BY error 
    ORDER BY COUNT(*) DESC 
    LIMIT 10"
    
    echo ""
    echo -e "${MAGENTA}📋 ОШИБКИ ПО ОЧЕРЕДЯМ:${NC}"
    execute_sql "SELECT 
        queue as 'Очередь',
        COUNT(*) as 'Ошибок',
        COUNT(DISTINCT error) as 'Уникальных',
        ROUND(AVG(retries), 1) as 'Сред.попытки'
    FROM messages 
    WHERE status IN ('failed', 'retrying')
    GROUP BY queue 
    ORDER BY COUNT(*) DESC"
}

# Функция для анализа повторных попыток
show_retry_analysis() {
    local format="$1"
    
    if [[ "$format" == "json" ]]; then
        execute_sql "SELECT 
            retries,
            COUNT(*) as count,
            GROUP_CONCAT(DISTINCT status) as statuses,
            GROUP_CONCAT(DISTINCT queue) as queues
        FROM messages 
        WHERE retries > 0
        GROUP BY retries 
        ORDER BY retries" json
        return
    fi
    
    echo -e "${MAGENTA}🔄 АНАЛИЗ ПОВТОРНЫХ ПОПЫТОК${NC}"
    echo "═══════════════════════════════════════════════════════════════"
    
    echo -e "${YELLOW}📊 РАСПРЕДЕЛЕНИЕ ПО КОЛИЧЕСТВУ ПОПЫТОК:${NC}"
    execute_sql "SELECT 
        retries as 'Попытки',
        COUNT(*) as 'Сообщений',
        ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM messages WHERE retries > 0), 1) || '%' as 'Процент'
    FROM messages 
    WHERE retries > 0
    GROUP BY retries 
    ORDER BY retries"
    
    echo ""
    echo -e "${BLUE}⏱️ СООБЩЕНИЯ С ЗАПЛАНИРОВАННЫМИ ПОВТОРАМИ:${NC}"
    execute_sql "SELECT 
        queue as 'Очередь',
        COUNT(*) as 'Ожидает повтора',
        MIN(datetime(next_retry_at, 'localtime')) as 'Ближайший повтор',
        MAX(datetime(next_retry_at, 'localtime')) as 'Последний повтор'
    FROM messages 
    WHERE status = 'retrying' AND next_retry_at IS NOT NULL
    GROUP BY queue"
    
    echo ""
    echo -e "${GREEN}🎯 СТАТИСТИКА УСПЕШНОСТИ:${NC}"
    local total_with_retries=$(execute_sql "SELECT COUNT(*) FROM messages WHERE retries > 0" "raw")
    local successful_after_retry=$(execute_sql "SELECT COUNT(*) FROM messages WHERE retries > 0 AND status = 'sent'" "raw")
    local failed_after_retry=$(execute_sql "SELECT COUNT(*) FROM messages WHERE retries > 0 AND status = 'failed'" "raw")
    
    if [[ $total_with_retries -gt 0 ]]; then
        local success_rate=$(( $successful_after_retry * 100 / $total_with_retries ))
        echo "├─ Всего сообщений с повторами: $total_with_retries"
        echo "├─ Успешно отправлено после повторов: $successful_after_retry"
        echo "├─ Окончательно неудачных: $failed_after_retry"
        echo "└─ Процент успешности повторов: ${success_rate}%"
    else
        echo "Нет сообщений с повторными попытками"
    fi
}

# Функция для анализа производительности
show_performance() {
    local format="$1"
    
    if [[ "$format" == "json" ]]; then
        cat << EOF
{
  "hourly_stats": $(execute_sql "SELECT 
    strftime('%Y-%m-%d %H:00', created_at) as hour,
    COUNT(*) as messages,
    SUM(CASE WHEN status = 'sent' THEN 1 ELSE 0 END) as sent,
    SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END) as failed
  FROM messages 
  WHERE created_at >= datetime('now', '-24 hours')
  GROUP BY strftime('%Y-%m-%d %H:00', created_at)
  ORDER BY hour DESC" json),
  "processing_times": $(execute_sql "SELECT 
    AVG(julianday(updated_at) - julianday(created_at)) * 24 * 60 as avg_processing_minutes,
    MIN(julianday(updated_at) - julianday(created_at)) * 24 * 60 as min_processing_minutes,
    MAX(julianday(updated_at) - julianday(created_at)) * 24 * 60 as max_processing_minutes
  FROM messages 
  WHERE status = 'sent' AND updated_at > created_at" json)
}
EOF
        return
    fi
    
    echo -e "${GREEN}⚡ АНАЛИЗ ПРОИЗВОДИТЕЛЬНОСТИ${NC}"
    echo "═══════════════════════════════════════════════════════════════"
    
    echo -e "${YELLOW}📈 АКТИВНОСТЬ ЗА ПОСЛЕДНИЕ 24 ЧАСА:${NC}"
    execute_sql "SELECT 
        strftime('%H:00', created_at) as 'Час',
        COUNT(*) as 'Всего',
        SUM(CASE WHEN status = 'sent' THEN 1 ELSE 0 END) as 'Отправлено',
        SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END) as 'Ошибки',
        ROUND(SUM(CASE WHEN status = 'sent' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 1) || '%' as 'Успешность'
    FROM messages 
    WHERE created_at >= datetime('now', '-24 hours')
    GROUP BY strftime('%H', created_at)
    ORDER BY strftime('%H', created_at) DESC
    LIMIT 12"
    
    echo ""
    echo -e "${BLUE}⏱️ ВРЕМЯ ОБРАБОТКИ СООБЩЕНИЙ:${NC}"
    execute_sql "SELECT 
        'Среднее время обработки (мин)' as 'Метрика',
        ROUND(AVG(julianday(updated_at) - julianday(created_at)) * 24 * 60, 2) as 'Значение'
    FROM messages 
    WHERE status = 'sent' AND updated_at > created_at
    UNION ALL
    SELECT 
        'Минимальное время (мин)',
        ROUND(MIN(julianday(updated_at) - julianday(created_at)) * 24 * 60, 2)
    FROM messages 
    WHERE status = 'sent' AND updated_at > created_at
    UNION ALL
    SELECT 
        'Максимальное время (мин)',
        ROUND(MAX(julianday(updated_at) - julianday(created_at)) * 24 * 60, 2)
    FROM messages 
    WHERE status = 'sent' AND updated_at > created_at"
    
    echo ""
    echo -e "${CYAN}🚀 ПРОПУСКНАЯ СПОСОБНОСТЬ:${NC}"
    execute_sql "SELECT 
        DATE(created_at) as 'Дата',
        COUNT(*) as 'Сообщений/день',
        ROUND(COUNT(*) / 24.0, 1) as 'Сообщений/час',
        SUM(CASE WHEN status = 'sent' THEN 1 ELSE 0 END) as 'Отправлено'
    FROM messages 
    WHERE created_at >= datetime('now', '-7 days')
    GROUP BY DATE(created_at)
    ORDER BY DATE(created_at) DESC"
}

# Функция для предложений по очистке
show_cleanup_suggestions() {
    echo -e "${CYAN}🧹 ПРЕДЛОЖЕНИЯ ПО ОЧИСТКЕ БАЗЫ ДАННЫХ${NC}"
    echo "═══════════════════════════════════════════════════════════════"
    
    local old_sent=$(execute_sql "SELECT COUNT(*) FROM messages WHERE status = 'sent' AND created_at < datetime('now', '-7 days')" "raw")
    local old_failed=$(execute_sql "SELECT COUNT(*) FROM messages WHERE status = 'failed' AND created_at < datetime('now', '-30 days')" "raw")
    local total_size=$(execute_sql "SELECT ROUND(page_count * page_size / 1024.0 / 1024.0, 2) FROM pragma_page_count(), pragma_page_size()" "raw")
    
    echo -e "${YELLOW}📊 АНАЛИЗ ДАННЫХ ДЛЯ ОЧИСТКИ:${NC}"
    echo "├─ Отправленных сообщений старше 7 дней: $old_sent"
    echo "├─ Неудачных сообщений старше 30 дней: $old_failed"
    echo "└─ Текущий размер базы: ${total_size} MB"
    echo ""
    
    if [[ $old_sent -gt 0 ]]; then
        echo -e "${GREEN}✅ РЕКОМЕНДАЦИЯ: Очистка старых отправленных сообщений${NC}"
        echo "   SQL команда:"
        echo "   DELETE FROM messages WHERE status = 'sent' AND created_at < datetime('now', '-7 days');"
        echo ""
    fi
    
    if [[ $old_failed -gt 0 ]]; then
        echo -e "${GREEN}✅ РЕКОМЕНДАЦИЯ: Очистка старых неудачных сообщений${NC}"
        echo "   SQL команда:"
        echo "   DELETE FROM messages WHERE status = 'failed' AND created_at < datetime('now', '-30 days');"
        echo ""
    fi
    
    echo -e "${BLUE}🔧 КОМАНДЫ ДЛЯ ОБСЛУЖИВАНИЯ:${NC}"
    echo "├─ Анализ базы: sqlite3 $DB_PATH 'ANALYZE;'"
    echo "├─ Вакуум: sqlite3 $DB_PATH 'VACUUM;'"
    echo "├─ Проверка целостности: sqlite3 $DB_PATH 'PRAGMA integrity_check;'"
    echo "└─ Автоочистка через скрипт: systemctl status messagebridge | grep cleanup"
}

# Парсинг аргументов
MODE="summary"
PAGE=$DEFAULT_PAGE
LIMIT=$DEFAULT_LIMIT
STATUS_FILTER=""
QUEUE_FILTER=""
MESSAGE_ID=""
OUTPUT_FORMAT="table"
USE_COLOR=true

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -d|--database)
            DB_PATH="$2"
            shift 2
            ;;
        --summary)
            MODE="summary"
            shift
            ;;
        --messages)
            MODE="messages"
            shift
            ;;
        --status)
            STATUS_FILTER="$2"
            if [[ "$MODE" == "summary" ]]; then
                MODE="messages"
            fi
            shift 2
            ;;
        --queue)
            QUEUE_FILTER="$2"
            if [[ "$MODE" == "summary" ]]; then
                MODE="messages"
            fi
            shift 2
            ;;
        --message-id)
            MESSAGE_ID="$2"
            MODE="message-details"
            shift 2
            ;;
        --failed-details)
            MODE="failed-details"
            shift
            ;;
        --retry-analysis)
            MODE="retry-analysis"
            shift
            ;;
        --performance)
            MODE="performance"
            shift
            ;;
        --cleanup-suggestions)
            MODE="cleanup-suggestions"
            shift
            ;;
        --page)
            PAGE="$2"
            shift 2
            ;;
        --limit)
            LIMIT="$2"
            shift 2
            ;;
        --json)
            OUTPUT_FORMAT="json"
            shift
            ;;
        --csv)
            OUTPUT_FORMAT="csv"
            shift
            ;;
        --no-color)
            USE_COLOR=false
            shift
            ;;
        *)
            echo -e "${RED}❌ Неизвестная опция: $1${NC}" >&2
            echo "Используйте --help для справки" >&2
            exit 1
            ;;
    esac
done

# Отключение цветов если нужно
if [[ "$USE_COLOR" == false ]] || [[ "$OUTPUT_FORMAT" != "table" ]]; then
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    MAGENTA=""
    CYAN=""
    NC=""
fi

# Проверка базы данных
check_database

# Валидация статуса
if [[ -n "$STATUS_FILTER" ]] && [[ ! "$STATUS_FILTER" =~ ^(pending|sent|failed|retrying)$ ]]; then
    echo -e "${RED}❌ Неверный статус: $STATUS_FILTER${NC}" >&2
    echo "Допустимые статусы: pending, sent, failed, retrying" >&2
    exit 1
fi

# Выполнение выбранного режима
case "$MODE" in
    "summary")
        show_summary "$OUTPUT_FORMAT"
        ;;
    "messages")
        show_messages "$PAGE" "$LIMIT" "$STATUS_FILTER" "$QUEUE_FILTER" "$OUTPUT_FORMAT"
        ;;
    "message-details")
        show_message_details "$MESSAGE_ID" "$OUTPUT_FORMAT"
        ;;
    "failed-details")
        show_failed_details "$OUTPUT_FORMAT"
        ;;
    "retry-analysis")
        show_retry_analysis "$OUTPUT_FORMAT"
        ;;
    "performance")
        show_performance "$OUTPUT_FORMAT"
        ;;
    "cleanup-suggestions")
        show_cleanup_suggestions
        ;;
    *)
        echo -e "${RED}❌ Неизвестный режим: $MODE${NC}" >&2
        exit 1
        ;;
esac 