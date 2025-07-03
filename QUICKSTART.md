# 🚀 Быстрый старт MessageBridge

## ⚡ Автоматическая установка (самый быстрый способ)

```bash
# 1. Скачивание релиза
wget https://github.com/expai/messagebridge/releases/latest/download/messagebridge-linux-amd64.tar.gz
tar -xzf messagebridge-linux-amd64.tar.gz
cd messagebridge-*/

# 2. Автоматическая установка (полная с nginx)
sudo ./scripts/install.sh

# Готово! Сервис запущен и готов принимать webhook'и
curl -X POST https://your-domain.com/webhook/payment \
  -H "Content-Type: application/json" \
  -d '{"order_id": "12345", "amount": 100.50, "currency": "USD"}'
```

**Что получаете за 2 минуты:**
- ✅ Полностью настроенное приложение
- ✅ Systemd сервис с автозапуском  
- ✅ Nginx с готовой SSL конфигурацией
- ✅ Production-ready настройки
- ✅ SQLite резервное хранилище
- ✅ Автоматические retry механизмы

### Альтернативы установки

```bash
# Минимальная установка (только приложение)
sudo ./scripts/install.sh --minimal

# Проверка системных требований
./scripts/install.sh --help
```

## 🐳 Запуск с Docker Compose

1. **Клонирование и запуск**
   ```bash
   git clone https://github.com/expai/messagebridge.git
   cd messagebridge
   docker-compose up -d
   ```

2. **Проверка состояния**
   ```bash
   # Проверка сервисов
   docker-compose ps
   
   # Проверка логов
   docker-compose logs messagebridge
   
   # Health check
   curl http://localhost:8080/health
   ```

3. **Отправка тестового webhook'а**
   ```bash
   curl -X POST http://localhost:8080/webhook/payment \
     -H "Content-Type: application/json" \
     -d '{"order_id": "12345", "amount": 100.50, "currency": "USD"}'
   ```

4. **Мониторинг Kafka (UI доступен на http://localhost:8081)**
   - Topics: payment-events, user-events, order-events
   - Messages: можно видеть отправленные webhook'и

## Локальная сборка и запуск

1. **Требования**
   - Go 1.24+
   - Kafka (запущенная локально)

2. **Сборка**
   ```bash
   make deps
   make build
   ```

3. **Запуск**
   ```bash
   # С простой конфигурацией
   ./messagebridge -config examples/simple-config.yaml
   ```

## 🛠️ Управление системной службой

После автоматической установки:

```bash
# Проверка статуса (уже запущен!)
sudo systemctl status messagebridge

# Управление сервисом
sudo systemctl restart messagebridge
sudo systemctl stop messagebridge

# Просмотр логов
sudo journalctl -u messagebridge -f

# Настройка SSL (обязательно для production!)
sudo apt install certbot python3-certbot-nginx
sudo certbot --nginx -d your-domain.com
```

### Ручная установка (если нужна)

```bash
# Сборка и установка
make install

# Запуск службы
sudo systemctl enable messagebridge
sudo systemctl start messagebridge

# Проверка статуса
sudo systemctl status messagebridge
```

## Тестирование отказоустойчивости

1. **Остановка Kafka**
   ```bash
   docker-compose stop kafka
   ```

2. **Отправка webhook'а (будет сохранен в SQLite)**
   ```bash
   curl -X POST http://localhost:8080/webhook/payment \
     -H "Content-Type: application/json" \
     -d '{"test": "resilience", "amount": 200}'
   ```

3. **Запуск Kafka обратно**
   ```bash
   docker-compose start kafka
   ```

4. **Webhook автоматически отправится в Kafka через worker**

## Доступные эндпоинты

- `POST /webhook/payment` - webhook для платежей
- `POST /webhook/user` - webhook для пользователей  
- `POST /webhook/order` - webhook для заказов
- `GET /health` - проверка здоровья
- `GET /status` - статус системы

## Полезные команды

```bash
# Просмотр логов
docker-compose logs -f messagebridge

# Проверка сообщений в Kafka UI
open http://localhost:8081

# Проверка базы данных SQLite
docker-compose exec messagebridge sqlite3 /var/lib/messagebridge/messages.db "SELECT * FROM messages;"

# Остановка всех сервисов
docker-compose down
```

## Конфигурация

Основные файлы конфигурации:
- `examples/simple-config.yaml` - минимальная конфигурация
- `examples/config.yaml` - полная конфигурация
- `examples/docker-config.yaml` - для Docker окружения

## 🗑️ Удаление

```bash
# Безопасное удаление (сохраняет данные)
sudo ./scripts/uninstall.sh

# Полное удаление (включая все данные)
sudo ./scripts/uninstall.sh --remove-data --remove-nginx
```

## Troubleshooting

**Проблема**: Автоматическая установка не работает
```bash
# Проверка системных требований
./scripts/install.sh --help

# Ручная проверка зависимостей
command -v sqlite3 && echo "SQLite OK" || echo "SQLite missing"
command -v nginx && echo "Nginx OK" || echo "Nginx missing"
```

**Проблема**: Сервис не запускается после установки
```bash
# Проверка логов
sudo journalctl -u messagebridge -n 50

# Проверка конфигурации
sudo cat /etc/messagebridge/config.yaml

# Перезапуск
sudo systemctl restart messagebridge
```

**Проблема**: Nginx не работает
```bash
# Тест конфигурации nginx
sudo nginx -t

# Проверка SSL настроек
sudo certbot certificates

# Перезагрузка nginx
sudo systemctl reload nginx
```

**Проблема**: Docker - сервис не запускается
```bash
# Проверка логов
docker-compose logs messagebridge

# Проверка конфигурации
docker-compose exec messagebridge cat /etc/messagebridge/config.yaml
```

**Проблема**: Docker - Kafka недоступна  
```bash
# Проверка состояния Kafka
docker-compose logs kafka

# Проверка health check
docker-compose exec kafka kafka-broker-api-versions --bootstrap-server localhost:9092
```

**Проблема**: Сообщения не отправляются
```bash
# Для установленного сервиса
sudo sqlite3 /var/lib/messagebridge/messages.db "SELECT status, COUNT(*) FROM messages GROUP BY status;"

# Для Docker
docker-compose exec messagebridge sqlite3 /var/lib/messagebridge/messages.db "SELECT status, COUNT(*) FROM messages GROUP BY status;"
``` 