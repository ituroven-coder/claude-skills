# Настройка sourcecraft-publisher

## Быстрый старт

1. Скопируйте `.env.example`:
   ```bash
   cp config/.env.example config/.env
   ```
2. Заполните переменные (см. ниже)

## Получение токена SourceCraft

1. Откройте [SourceCraft](https://sourcecraft.yandex.cloud/)
2. Перейдите в **Settings → Access Tokens**
3. Создайте токен с правами **Contents: Read and Write** на нужный репозиторий
4. Скопируйте токен в `SOURCECRAFT_TOKEN`

> Если интерфейс отличается — ищите раздел OAuth/PAT tokens в настройках профиля или организации.

## Переменные окружения

| Переменная | Обязательна | Описание |
|-----------|-------------|----------|
| `SOURCECRAFT_TOKEN` | да | OAuth2 токен для push в SourceCraft |
| `SOURCECRAFT_REPO` | да | `org/repo` — целевой репозиторий |
| `SOURCECRAFT_BRANCH` | нет | Ветка для push (default: `master`) |
| `SOURCECRAFT_SITE_URL` | да | Публичный URL сайта, например `https://org.sourcecraft.site/repo` |

## Структура публикации

Артифакты публикуются в директории:
```
YYYY/YYYY-MM/page-slug/
```

Итоговый URL:
```
<SOURCECRAFT_SITE_URL>/YYYY/YYYY-MM/page-slug/
```

## SourceCraft Sites конфигурация

Скрипт автоматически создаёт `.sourcecraft/sites.yaml` в репозитории если его нет:
```yaml
site:
  root: "."
  ref: master
```
