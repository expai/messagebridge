# Changelog

Все заметные изменения в этом проекте будут документированы в этом файле.

Формат основан на [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
и этот проект придерживается [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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