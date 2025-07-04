# MessageBridge - Secure Payment Webhook Gateway

Надежное приложение на Go для приема и обработки платежных webhook'ов с гарантированной доставкой в Apache Kafka или удаленные URL'ы.

## 🎯 Основные возможности

- **Надежный прием webhook'ов** - HTTP сервер с защитой от паник и graceful shutdown
- **Гарантированная доставка** - резервное хранение в SQLite при сбоях
- **Поддержка Kafka** - полная конфигурация безопасности (SASL, TLS)
- **Отправка на удаленные URL** - альтернатива Kafka с retry логикой
- **Worker для повторных попыток** - автоматическая обработка неотправленных сообщений с настраиваемыми лимитами (включая неограниченные попытки)
- **Мониторинг здоровья** - встроенные health check'и
- **Безопасность** - защищенная контейнеризация и systemd интеграция

## 🏗️ Архитектура

```
HTTP Request → Server → Handler → [Kafka|Remote URL]
                  ↓ (on failure)
               SQLite ← Worker → [Kafka|Remote URL]
```

## 📦 Установка

### Из исходного кода

```bash
# Клонирование репозитория
git clone https://github.com/expai/messagebridge.git
cd messagebridge

# Сборка и установка
make deps
make install
```

### Docker

```bash
# Сборка образа
make docker-build

# Запуск контейнера
docker run -d \
  --name messagebridge \
  -p 8080:8080 \
  -v $(pwd)/config.yaml:/etc/messagebridge/config.yaml \
  -v messagebridge-data:/var/lib/messagebridge \
  messagebridge:latest
```

### 🎯 Автоматическая установка (рекомендуется)

```bash
# Скачивание и распаковка релиза
wget https://github.com/expai/messagebridge/releases/latest/download/messagebridge-linux-amd64.tar.gz
tar -xzf messagebridge-linux-amd64.tar.gz
cd messagebridge-*/

# Полная автоматическая установка с nginx
sudo ./scripts/install.sh

# Или минимальная установка только приложения
sudo ./scripts/install.sh --minimal

# Проверка системных требований
./scripts/install.sh --help
```

**Что включает полная установка:**
- ✅ Автоматическая проверка ОС (Ubuntu, Debian, Arch Linux)
- ✅ Установка зависимостей (SQLite, nginx)
- ✅ Создание системного пользователя и директорий
- ✅ Настройка systemd сервиса с автозапуском
- ✅ Генерация конфигурации nginx с SSL поддержкой
- ✅ Готовая production конфигурация

### Ручная установка

```bash
# Если предпочитаете ручную установку
sudo cp messagebridge /usr/local/bin/
sudo chmod +x /usr/local/bin/messagebridge
```

## ⚙️ Конфигурация

### Минимальная конфигурация

```yaml
server:
  host: "0.0.0.0"
  port: 8080

routes:
  - path: "/webhook/payment"
    queue: "payment-events"

kafka:
  brokers:
    - "localhost:9092"

worker:
  retry_interval: 5m       # How often to check for failed messages
  batch_size: 50           # Messages to fetch per batch (sent individually)
  max_retries: 0           # Retry attempts (0 = unlimited until success)
```

### Полная конфигурация

```yaml
server:
  host: "0.0.0.0"
  port: 8080

routes:
  - path: "/webhook/payment"
    queue: "payment-events"
  - path: "/webhook/user"
    queue: "user-events"
  - path: "/webhook/order"
    queue: "order-events"

kafka:
  brokers:
    - "kafka1:9092"
    - "kafka2:9092"
  security_protocol: "SASL_SSL"
  sasl_mechanism: "SCRAM-SHA-256"
  sasl_username: "your-username"
  sasl_password: "your-password"
  tls_enabled: true
  retry_max: 3
  retry_backoff: 2s
  batch_size: 100
  timeout: 30s

sqlite:
  database_path: "/var/lib/sbphub/messages.db"

# Альтернатива Kafka - отправка на удаленный URL
remote_url:
  url: "https://api.example.com/webhooks"
  timeout: 30s
  retries: 3

worker:
  retry_interval: 5m       # How often to check for failed messages  
  batch_size: 50           # Messages to fetch per batch (sent individually)
  max_retries: 0           # Retry attempts (0 = unlimited until success)
```

## 🚀 Запуск

### Локальный запуск

```bash
# Сборка и запуск
make run-dev

# Или напрямую
./messagebridge -config config.yaml
```

### Как системная служба

```bash
# После автоматической установки сервис уже запущен!
# Проверка статуса
sudo systemctl status messagebridge

# Управление сервисом
sudo systemctl start messagebridge
sudo systemctl stop messagebridge
sudo systemctl restart messagebridge

# Просмотр логов
sudo journalctl -u messagebridge -f
```

### 🔧 Настройка nginx и SSL

Автоматическая установка создаёт готовую конфигурацию nginx:

```bash
# 1. Установите SSL сертификат
sudo apt install certbot python3-certbot-nginx  # Ubuntu/Debian
sudo pacman -S certbot certbot-nginx            # Arch Linux

# 2. Получите сертификат для вашего домена
sudo certbot --nginx -d your-webhook-domain.com

# 3. Обновите конфигурацию
sudo nano /etc/messagebridge/config.yaml
# Измените:
# nginx:
#   domain: "your-webhook-domain.com"
# remote_url:
#   url: "https://your-api.com/webhooks"

# 4. Перезапустите сервисы
sudo systemctl restart messagebridge nginx
```

### В Docker

```bash
# Запуск с docker-compose
docker-compose up -d

# Или напрямую
docker run -d \
  --name messagebridge \
  -p 8080:8080 \
  -v ./config.yaml:/etc/messagebridge/config.yaml \
  messagebridge:latest
```

## 📡 API

### Webhook эндпоинты

```bash
# Отправка webhook'а
curl -X POST http://localhost:8080/webhook/payment \
  -H "Content-Type: application/json" \
  -d '{"order_id": "12345", "amount": 100.00, "currency": "USD"}'

# Ответ
{
  "message_id": "abc123def456",
  "status": "accepted",
  "timestamp": "2025-01-15T10:30:00Z"
}
```

### Мониторинг

```bash
# Health check
curl http://localhost:8080/health

# Статус приложения
curl http://localhost:8080/status
```

## 🔒 Безопасность

### Системная безопасность

- Запуск под отдельным пользователем
- Ограничение системных ресурсов
- Изоляция файловой системы (systemd)
- Отключение новых привилегий

### Сетевая безопасность

- Поддержка TLS для Kafka
- SASL аутентификация
- Timeout'ы для всех сетевых операций
- Валидация входящих данных

### Контейнерная безопасность

- Многоэтапная сборка Docker
- Запуск под non-root пользователем
- Минимальный базовый образ Alpine
- Health check'и контейнера

## 🛠️ Разработка

### Требования

- Go 1.24+
- GCC (для SQLite)
- Docker (опционально)

### Команды разработки

```bash
# Установка зависимостей
make deps

# Сборка
make build

# Тестирование
make test
make test-race

# Форматирование кода
make fmt

# Линтинг
make lint

# Отправка тестового webhook'а
make test-webhook
```

### Структура проекта

```
messagebridge/
├── config/         # Конфигурация
├── models/         # Модели данных
├── storage/        # SQLite хранилище
├── kafka/          # Kafka producer
├── httpclient/     # HTTP клиент
├── server/         # HTTP сервер
├── worker/         # Background worker
├── handler/        # Обработчик сообщений
├── examples/       # Примеры конфигураций
├── deployments/    # Файлы развертывания
├── go.mod          # Go modules (github.com/expai/messagebridge)
└── main.go         # Главный файл
```

### Go модули

Проект использует полные импорты согласно Go best practices:

```go
import (
    "github.com/expai/messagebridge/config"
    "github.com/expai/messagebridge/models"
)
```

## 📊 Мониторинг

### Логирование

```bash
# Системные логи
sudo journalctl -u messagebridge -f

# Docker логи
docker logs -f messagebridge
```

### Метрики

Приложение предоставляет следующие эндпоинты:

- `/health` - проверка здоровья
- `/status` - статус компонентов

### Алерты

Приложение возвращает специфичные exit коды:

- `0` - нормальное завершение
- `1` - ошибка
- `2` - требуется перезапуск

## 🔄 Восстановление после сбоев

### Автоматическое восстановление

1. **Panic recovery** - перехват паник с автоматическим перезапуском
2. **SQLite backup** - сохранение неотправленных сообщений
3. **Worker retry** - повторная отправка из резервного хранилища с гибкими настройками
4. **Health monitoring** - мониторинг состояния компонентов

### 🔁 Worker конфигурация

Worker обрабатывает неотправленные сообщения с экспоненциальным backoff:

```yaml
worker:
  retry_interval: 5m       # Как часто проверять неотправленные сообщения
  batch_size: 50           # Сколько сообщений забирать за раз (отправляются по одному!)
  max_retries: 0           # Максимум попыток: 0 = неограниченно до успеха
```

**Логика retry:**
- `max_retries: 0` - worker будет пытаться отправить **неограниченное количество раз** до успешной доставки
- `max_retries: 5` - после 5 неудачных попыток сообщение помечается как `failed`
- `batch_size: 50` - из базы забирается 50 сообщений, но **каждое отправляется отдельно**
- Экспоненциальная задержка: 2 мин → 4 мин → 8 мин → 16 мин...

### Ручное восстановление

```bash
# Перезапуск службы
sudo systemctl restart messagebridge

# Проверка логов на ошибки
sudo journalctl -u messagebridge --since "1 hour ago"

# Проверка состояния базы данных
sqlite3 /var/lib/messagebridge/messages.db "SELECT COUNT(*) FROM messages WHERE status='pending';"
```

## 🐛 Отладка

### Частые проблемы

1. **Не удается подключиться к Kafka**
   - Проверьте конфигурацию brokers
   - Убедитесь в правильности SASL настроек
   - Проверьте сетевую доступность

2. **Ошибки SQLite**
   - Проверьте права доступа к папке базы данных
   - Убедитесь в наличии свободного места

3. **HTTP ошибки**
   - Проверьте занятость порта
   - Убедитесь в правильности конфигурации роутов

### Включение отладки

```bash
# Запуск с подробным логированием
export LOG_LEVEL=debug
./messagebridge -config config.yaml
```

## 🚨 Устранение неполадок

### Быстрое исправление проблем с правами доступа

```bash
# Исправить права доступа для существующей установки
make fix-permissions

# Или напрямую
sudo ./scripts/fix-permissions.sh
```

### Подробное руководство

Полное руководство по устранению неполадок доступно в [TROUBLESHOOTING.md](TROUBLESHOOTING.md), включая:

- Проблемы с правами доступа к конфигурации
- Ошибки запуска службы  
- Проблемы с SSL/TLS сертификатами
- Проблемы с базой данных
- Сетевые проблемы
- Мониторинг и отладка
- Производительность

## 🗑️ Удаление

### Автоматическое удаление

```bash
# Безопасное удаление (сохраняет данные и конфигурацию)
sudo ./scripts/uninstall.sh

# Полное удаление (включая все данные и nginx)
sudo ./scripts/uninstall.sh --remove-data --remove-nginx

# Через Makefile
make uninstall-safe     # Безопасное удаление
make uninstall-full     # Полное удаление
```

### Ручное удаление

```bash
# Остановка сервиса
sudo systemctl stop messagebridge
sudo systemctl disable messagebridge

# Удаление файлов
sudo rm -f /etc/systemd/system/messagebridge.service
sudo rm -f /usr/local/bin/messagebridge

# Удаление данных (опционально)
sudo rm -rf /etc/messagebridge /var/lib/messagebridge /var/log/messagebridge

# Удаление nginx конфигурации (опционально)
sudo rm -f /etc/nginx/sites-enabled/messagebridge
sudo rm -f /etc/nginx/sites-available/messagebridge

# Удаление системного пользователя
sudo userdel messagebridge

sudo systemctl daemon-reload
```

## 📝 Лицензия

MIT License

## 🤝 Поддержка

Для вопросов и поддержки:

- GitHub Issues: [создать issue](https://github.com/expai/messagebridge/issues)
- Email: support@yourcompany.com

## 🏷️ Версионирование

Проект следует [Semantic Versioning](https://semver.org/):

- `MAJOR.MINOR.PATCH`
- Changelog в [CHANGELOG.md](CHANGELOG.md) 