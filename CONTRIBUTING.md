# Участие в проекте MessageBridge

Спасибо за ваш интерес к участию в MessageBridge! Мы рады любым вкладам - от исправления ошибок до новых функций.

## Кодекс поведения

Участвуя в этом проекте, вы соглашаетесь поддерживать дружелюбную и инклюзивную среду для всех.

## Как внести вклад

### Сообщение об ошибках

1. Проверьте [существующие issues](https://github.com/expai/messagebridge/issues), чтобы убедиться, что ошибка ещё не была сообщена
2. Используйте шаблон bug report при создании нового issue
3. Включите как можно больше деталей: версию, ОС, шаги воспроизведения, логи

### Предложение новых функций

1. Создайте issue с использованием шаблона feature request
2. Опишите проблему, которую решает функция
3. Объясните, как она должна работать
4. Обсудите реализацию с мейнтейнерами перед началом работы

### Отправка Pull Requests

1. **Fork репозиторий** и создайте feature branch:
   ```bash
   git checkout -b feature/my-new-feature
   ```

2. **Настройте среду разработки**:
   ```bash
   go mod download
   ```

3. **Сделайте изменения**:
   - Следуйте стилю кода Go (используйте `gofmt`)
   - Добавьте тесты для новой функциональности
   - Обновите документацию при необходимости

4. **Запустите тесты**:
   ```bash
   make test
   make lint
   ```

5. **Commit изменения**:
   ```bash
   git commit -m "feat: добавить новую функцию"
   ```

6. **Push в ваш fork**:
   ```bash
   git push origin feature/my-new-feature
   ```

7. **Создайте Pull Request** с подробным описанием изменений

## Стандарты кода

### Go стиль

- Используйте `gofmt` для форматирования
- Следуйте [Effective Go](https://golang.org/doc/effective_go.html)
- Добавляйте комментарии к публичным функциям и типам
- Используйте осмысленные имена переменных и функций
- **Используйте полные импорты**: `"github.com/expai/messagebridge/config"` вместо `"messagebridge/config"`

### Commit сообщения

Используйте формат [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>[optional scope]: <description>

[optional body]

[optional footer]
```

Типы:
- `feat`: новая функция
- `fix`: исправление ошибки
- `docs`: изменения в документации
- `style`: форматирование, отсутствующие точки с запятой и т.д.
- `refactor`: рефакторинг кода
- `test`: добавление тестов
- `chore`: обновление зависимостей, конфигурации сборки и т.д.

Примеры:
```
feat(kafka): добавить поддержку SASL_SSL
fix(storage): исправить race condition в SQLite
docs: обновить README с примерами конфигурации
```

### Тестирование

- Пишите unit тесты для новой функциональности
- Поддерживайте покрытие тестами выше 80%
- Используйте table-driven тесты где это возможно
- Мокайте внешние зависимости

Пример теста:
```go
func TestMessageHandler(t *testing.T) {
    tests := []struct {
        name    string
        input   Message
        want    error
    }{
        {
            name:  "valid message",
            input: Message{ID: "test", Data: "data"},
            want:  nil,
        },
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            got := HandleMessage(tt.input)
            if got != tt.want {
                t.Errorf("HandleMessage() = %v, want %v", got, tt.want)
            }
        })
    }
}
```

## Структура проекта

```
messagebridge/
├── config/          # Конфигурация
├── handler/         # Обработчики сообщений
├── httpclient/      # HTTP клиент
├── kafka/           # Kafka producer
├── models/          # Модели данных
├── server/          # HTTP сервер
├── storage/         # SQLite хранилище
├── worker/          # Background worker
├── examples/        # Примеры конфигурации
└── deployments/     # Файлы развёртывания
```

## Локальная разработка

1. **Требования**:
   - Go 1.21+
   - Docker и Docker Compose
   - Make

2. **Запуск окружения**:
   ```bash
   # Запуск Kafka и зависимостей
   docker-compose up -d kafka zookeeper
   
   # Запуск приложения в dev режиме
   make run-dev
   ```

3. **Полезные команды**:
   ```bash
   make build        # Сборка
   make test         # Тесты
   make lint         # Линтинг
   make clean        # Очистка
   make docker-build # Сборка Docker образа
   ```

## Релизы

Релизы создаются автоматически при создании тега:

```bash
git tag -a v1.0.0 -m "Release v1.0.0"
git push origin v1.0.0
```

## Получение помощи

- Создайте issue с вопросом
- Присоединяйтесь к обсуждениям в GitHub Discussions
- Свяжитесь с мейнтейнерами

## Лицензия

Внося вклад в MessageBridge, вы соглашаетесь с тем, что ваш вклад будет лицензирован под MIT License. 