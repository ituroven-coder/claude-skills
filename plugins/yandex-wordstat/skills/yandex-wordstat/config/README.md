# Получение токена Yandex Wordstat API

## Шаг 1: Зарегистрируйте приложение (если ещё нет)

1. Перейдите на https://oauth.yandex.ru/client/new
2. Укажите название приложения
3. В разделе "Платформы" выберите "Веб-сервисы"
4. В "Права" добавьте: **Яндекс.Директ API**
5. Сохраните `client_id` и `client_secret`

## Шаг 2: Получите OAuth токен

### Способ A: Через браузер (простой)

1. Откройте в браузере (замените YOUR_CLIENT_ID):
   ```
   https://oauth.yandex.ru/authorize?response_type=token&client_id=YOUR_CLIENT_ID
   ```

2. Авторизуйтесь и дайте разрешения приложению

3. Скопируйте токен из URL после редиректа:
   ```
   https://oauth.yandex.ru/#access_token=ВАШТОКЕН&token_type=bearer&expires_in=31536000
   ```

### Способ B: Через скрипт

```bash
bash scripts/get_token.sh --client-id YOUR_CLIENT_ID --client-secret YOUR_SECRET
```

Скрипт:
1. Покажет URL для авторизации
2. Попросит ввести код подтверждения
3. Автоматически сохранит токен в `.env`

## Шаг 3: Настройте токен

Если получили токен вручную, создайте файл `.env`:

```bash
cp config/.env.example config/.env
```

Вставьте токен:

```
YANDEX_WORDSTAT_TOKEN=ваш_токен_здесь
```

## Проверка

```bash
bash scripts/quota.sh
```

## Срок жизни токена

- Токен действует **1 год** (expires_in=31536000)
- После истечения нужно получить новый

## Лимиты API

- **10 запросов в секунду** (rate limit)
- **~1000 запросов в день** (зависит от аккаунта)
- Отчёты Wordstat создаются асинхронно (до 60 сек)

## Документация

- OAuth Яндекса: https://yandex.ru/dev/id/doc/ru/concepts/ya-oauth-intro
- API Wordstat: https://yandex.ru/dev/direct/doc/reports/wordstat.html
- Операторы: https://yandex.ru/support/direct/keywords/symbols-and-operators.html
