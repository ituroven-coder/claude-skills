---
name: telegram-channel-parser
description: |
  Парсинг публичных Telegram-каналов через веб-превью t.me/s/.
  Посты, метрики, аналитика, дайджесты, конкурентный анализ.
  Cache-first подход для гигиены контекстного окна.
  Triggers: telegram канал, telegram channel, парсинг телеграм,
  дайджест каналов, telegram digest, анализ канала, шер-парад,
  telegram analytics, мониторинг каналов.
---

# telegram-channel-parser

Парсинг публичных Telegram-каналов через веб-превью (t.me/s/). Без API-ключей, без MTProto, zero config.

## Config

Никаких токенов не требуется. Скилл работает из коробки — дефолтный набор AI/tech каналов уже зашит.

**Приоритет каналов:**
1. `--channels "a,b,c"` — явный параметр (высший приоритет)
2. `TG_CHANNELS` из `config/.env` — пользовательский набор
3. Встроенный community-список — дефолт (работает без конфига)

**Определение каналов агентом:**
- Пользователь назвал канал(ы) явно → передать через `--channel` / `--channels`
- Пользователь попросил дайджест без уточнения → запустить без `--channels` (используется дефолтный набор)
- Пользователь хочет свои каналы навсегда → `cp config/.env.example config/.env` и отредактировать

Подробности: `config/README.md`.

## Philosophy

1. **Cache-first** — HTML-страницы кешируются по ключу `channel+before_id`. Повторный запрос не тратит ни токенов, ни времени. Кеш — TSV, grep-friendly.
2. **Context window hygiene** — stdout ограничен 30 строками. Полные данные в TSV/CSV. LLM работает с компактным форматом, а не с сырым HTML.
3. **Rate limit** — между запросами к t.me пауза 1.5с. Не жадничаем.
4. **Чистый POSIX sh** — никаких зависимостей кроме curl, sed, awk, grep.

## Workflow

### Парсинг одного канала

1. **Получи посты:**
   ```bash
   bash scripts/fetch_posts.sh --channel countwithsasha --limit 50
   ```
   Выведет последние 50 постов в TSV (id, date, views, forwards, text_preview).

2. **Инфо о канале:**
   ```bash
   bash scripts/channel_info.sh --channel countwithsasha
   ```

3. **Поиск по постам:**
   ```bash
   bash scripts/search_posts.sh --channel countwithsasha --query "скилл"
   ```

4. **Топ постов (шер-парад):**
   ```bash
   bash scripts/top_posts.sh --channel countwithsasha --limit 50 --sort forwards
   ```

5. **Расписание публикаций:**
   ```bash
   bash scripts/posting_schedule.sh --channel countwithsasha --limit 100
   ```

6. **Экспорт:**
   ```bash
   bash scripts/export_csv.sh --channel countwithsasha --limit 100 --csv cache/export.csv
   ```

### Дайджест по нескольким каналам

```bash
# Явный список каналов
bash scripts/digest.sh --channels "countwithsasha,evilfreelancer,aostrikov_ai_agents" --period today

# Дефолтный набор (без --channels)
bash scripts/digest.sh --period today
```

Периоды: `today`, `yesterday`, `week`, `N` (последние N дней).

### Сравнение каналов

```bash
bash scripts/compare_channels.sh --channels "channel1,channel2,channel3" --limit 30
```

Таблица: подписчики, средние просмотры, частота публикаций, engagement.

## React-артифакт для дайджеста

При запросе дайджеста — **отображай результаты как React-артифакт** (лента карточек).

**Алгоритм:**
1. Запусти `digest.sh` для нужных каналов и периода
2. Запусти `channel_info.sh` для каждого канала (название, подписчики)
3. Прочитай шаблон: `assets/digest-feed.tsx`
4. Подставь данные в `POSTS_DATA` и `CHANNELS` в шаблоне
5. Отрендери как React-артифакт

**Формат данных для подстановки:**
```typescript
// POSTS_DATA — массив постов из TSV вывода digest.sh
// TSV колонки: id \t date \t views \t reactions \t fwd_from \t fwd_link \t text \t media_url
{ id: "123", channel: "countwithsasha", date: "2026-03-29T14:30:00+00:00", views: "1.2K", reactions: "45", text: "...", mediaUrl: "https://cdn..." }

// CHANNELS — инфо о каналах из channel_info.sh
{ countwithsasha: { title: "Count With Sasha", subscribers: "12K" } }
```

Посты автоматически сортируются по дате (новые сверху), перемешаны между каналами. Пользователь фильтрует по периоду и каналу через UI.

## Scripts

Общий паттерн вызова:
```bash
bash scripts/<script>.sh --channel <username> [--limit N] [--before <post_id>] [--csv path]
```

| Script | Description | Special params |
|--------|-------------|----------------|
| `fetch_posts.sh` | Посты канала → TSV | `--limit`, `--before`, `--after-date YYYY-MM-DD` |
| `channel_info.sh` | Название, описание, подписчики | — |
| `search_posts.sh` | Полнотекстовый поиск | `--query "text"` |
| `top_posts.sh` | Ранжирование постов | `--sort views\|forwards\|reactions`, `--limit` |
| `posting_schedule.sh` | Анализ времени публикаций | `--limit` |
| `export_csv.sh` | Экспорт в CSV | `--csv path` |
| `digest.sh` | Дайджест нескольких каналов | `--channels "a,b,c"`, `--period today\|yesterday\|week\|N` |
| `compare_channels.sh` | Сравнительная таблица | `--channels "a,b,c"` |

## Общие параметры

| Param | Required | Default | Description |
|-------|----------|---------|-------------|
| `--channel` | да* | — | Username канала (без @) |
| `--channels` | нет | community list | Несколько каналов через запятую |
| `--limit` | нет | 20 | Сколько постов загрузить |
| `--before` | нет | — | ID поста для пагинации |
| `--after-date` | нет | — | Не загружать посты старше даты (YYYY-MM-DD) |
| `--csv` | нет | — | Путь для экспорта |
| `--no-cache` | нет | — | Пропустить кеш |

*`--channel` для одного канала, `--channels` для мультиканальных команд.

## Кеш-стратегия

Кеш хранится в `cache/`:
- `channels/<username>/posts.tsv` — посты (id, date, views, reactions, fwd_from, fwd_link, text, media_url)
- `channels/<username>/info.json` — метаданные канала
- `channels/<username>/raw/*.html` — сырой HTML страниц (для повторного парсинга)

Для поиска по кешу: `grep "text" cache/channels/*/posts.tsv`.

TTL кеша: 6 часов (настраивается через `TG_CACHE_TTL_HOURS`).

## Ввод канала

Скилл принимает канал в любом формате:
- `countwithsasha` — просто username
- `@countwithsasha` — с собакой
- `https://t.me/countwithsasha` — прямая ссылка
- `https://t.me/s/countwithsasha` — ссылка на веб-превью
- `t.me/countwithsasha?before=500` — с параметрами

Всё автоматически нормализуется до голого username.

## Ограничения

- Только **публичные** каналы (у которых есть t.me/s/ превью)
- **Счётчик пересылок (shares) недоступен** — t.me/s/ его не отдаёт, только MTProto API
- Зато парсится **откуда переслан пост** (fwd_from + ссылка на оригинал)
- Реакции парсятся суммарно (общее количество по всем эмодзи)
- Пагинация: ~20 постов на страницу, для 100 постов = 5 запросов
- Rate limit: 1.5с между запросами к t.me
