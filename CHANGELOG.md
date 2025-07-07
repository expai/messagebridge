# Changelog

Все заметные изменения в этом проекте будут документированы в этом файле.

Формат основан на [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
и этот проект придерживается [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.13] - 2025-01-07

### 🏗️ Архитектурные улучшения
- **BREAKING**: Рефакторинг для использования интерфейсов вместо конкретных типов
- Добавлен пакет `internal/interfaces/` с интерфейсами для всех внешних зависимостей
- Реализовано dependency injection для улучшения тестируемости
- Обновлены `main.go`, `handler/`, `worker/`, `server/` для использования интерфейсов

### ✅ Тестирование
- Добавлены comprehensive unit тесты для модуля `handler/` с mock объектами
- Добавлены unit тесты для модуля `config/` с покрытием всех сценариев валидации
- Реализованы table-driven тесты для лучшего покрытия edge cases
- Добавлены mock implementations для `MessageProducer`, `HTTPSender`, `MessageStorage`

### 🚨 Обработка ошибок
- Создан пакет `internal/errors/` с кастомными типами ошибок
- Добавлены структурированные ошибки с категоризацией по типам
- Реализованы функции-конструкторы для разных типов ошибок:
  - `NewConfigError()`, `NewStorageError()`, `NewKafkaError()`, `NewHTTPError()`
- Добавлена функция `IsType()` для проверки типа ошибки

### 🔄 CI/CD
- Создан comprehensive GitHub Actions workflow (`.github/workflows/ci.yml`)
- Добавлены автоматические тесты с race detection и coverage
- Интегрирован golangci-lint для статического анализа кода
- Добавлен Gosec security scanner с SARIF отчетами
- Настроены integration тесты с Kafka и Zookeeper services
- Добавлен Docker build step в CI pipeline


### 🎯 Migration Guide
```go
// Старый код:
handler := handler.NewMessageHandler(cfg, kafkaProducer, httpClient, storage)

// Новый код (тот же самый, но теперь type-safe через интерфейсы):
handler := handler.NewMessageHandler(cfg, kafkaProducer, httpClient, storage)
```

## [0.1.4]
### Добавлено
- Комментарии в конфиг systemd

## [0.1.2]

### Добавлено
- Первоначальная реализация MessageBridge
- HTTP сервер для приёма webhook'ов
- Kafka producer с поддержкой SASL/SSL
- SQLite для backup хранения сообщений
- Background worker для retry логики
- Конфигурация через YAML файлы
- Docker и Docker Compose поддержка
- Systemd сервис для автоматического запуска
- CI/CD с GitHub Actions
- Автоматические релизы
- Comprehensive документация

### Функции
- **Гарантированная доставка**: Резервное копирование в SQLite при сбоях Kafka
- **Автоматические повторы**: Экспоненциальный backoff для неудачных доставок
- **Безопасность**: Поддержка SASL_SSL, SCRAM-SHA-256/512
- **Мониторинг**: Health check и статистика
- **Graceful shutdown**: Корректное завершение с сохранением данных
- **Panic recovery**: Автоматический перезапуск при критических ошибках

### Поддерживаемые форматы
- JSON webhook'и
- Kafka topics
- Remote HTTP URLs
- SQLite backup storage

### Deployment опции
- Docker containers
- Systemd services  
- Standalone binaries
- Docker Compose стэк

## [0.1.1] - TBD

### Добавлено
- Первый стабильный релиз 