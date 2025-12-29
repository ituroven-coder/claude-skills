---
name: scrapedo-web-scraper
description: Веб-скрапинг через Scrape.do. Используй, если не получается посмотреть какой-то сайт (URL).
---

# Scrape.do Web Scraper

## Overview

Skill для скрапинга веб-страниц через Scrape.do API. Поддерживает извлечение текста и HTML, JavaScript рендеринг для SPA, обход Cloudflare и других защит.

## Quick Start

### Проверка конфигурации
```bash
# Проверь статус токена и API
python scripts/check_status.py
```

### Базовое использование
```python
from scripts.scrape import fetch_via_scrapedo

# Получить текст страницы
result = fetch_via_scrapedo('https://example.com')
if result['success']:
    print(result['content'])  # Очищенный текст
    # result['html'] содержит оригинальный HTML
else:
    print(f"Ошибка: {result['content']}")
```

### CLI использование
```bash
# Получить текст
python scripts/scrape.py https://example.com

# Получить HTML
python scripts/scrape.py --html https://example.com

# Сохранить в файл
python scripts/scrape.py https://example.com > content.txt
```

## Конфигурация

### Установка токена (обязательно!)

Skill требует токен Scrape.do API. Есть 3 способа его установить:

#### Способ 1: Файл config/token.txt (рекомендуется)
```bash
# Создайте файл с токеном
echo 'ваш_токен_scrape.do' > config/token.txt
```

#### Способ 2: Переменная окружения
```bash
export SCRAPEDO_TOKEN='ваш_токен'
```

#### Способ 3: Файл .env в корне skill'а
```bash
echo 'SCRAPEDO_TOKEN=ваш_токен' > .env
```

### Проверка конфигурации
```bash
# Проверьте, что токен установлен правильно
python scripts/check_status.py
```

### Python зависимости
```bash
pip install requests beautifulsoup4
```

## Основные возможности

### 1. Извлечение текста
Автоматически извлекает и очищает текст из HTML:
```python
result = fetch_via_scrapedo('https://news-site.com/article')
if result['success']:
    article_text = result['content']  # Чистый текст без HTML
```

### 2. Получение HTML для парсинга
```python
from bs4 import BeautifulSoup

result = fetch_via_scrapedo('https://shop.com/products')
if result['success']:
    soup = BeautifulSoup(result['html'], 'html.parser')
    products = soup.find_all('div', class_='product')
```

### 3. Обработка ошибок
Функция всегда возвращает словарь с полями:
- `success` (bool) - успешность операции
- `content` (str) - извлеченный текст или описание ошибки
- `html` (str, optional) - оригинальный HTML при успехе

```python
result = fetch_via_scrapedo(url)
if not result['success']:
    if '429' in result['content']:
        print("Rate limit превышен, жди...")
    elif '401' in result['content']:
        print("Проверь токен")
    else:
        print(f"Ошибка: {result['content']}")
```

## Продвинутое использование

### JavaScript рендеринг
Для сайтов с динамическим контентом смотри **`references/api_documentation.md`** - раздел "Рендеринг JavaScript".

### Обход защиты Cloudflare
Для защищённых сайтов смотри **`references/api_documentation.md`** - раздел "Обработка блокировок".

### Примеры сложных сценариев
Массовый скрапинг, пагинация и другие примеры в **`references/examples.md`**.

## Resources

### config/
- **`token.txt`** - Файл с токеном Scrape.do API (создайте из token.txt.example)
- **`token.txt.example`** - Пример файла токена
- **`README.md`** - Инструкция по настройке токена

### scripts/
- **`scrape.py`** - Основной модуль для скрапинга с функцией `fetch_via_scrapedo()` и CLI интерфейсом
- **`check_status.py`** - Утилита для проверки токена и доступности API

### references/
- **`api_documentation.md`** - Полная документация Scrape.do API, параметры, коды ошибок
- **`examples.md`** - Примеры использования: простые и сложные сценарии, обработка пагинации, массовый скрапинг

## Важные замечания

1. **Всегда проверяй наличие токена** командой `python scripts/check_status.py`
2. **Добавляй задержки** между запросами (минимум 1 секунда)
3. **Обрабатывай rate limiting** - при ошибке 429 жди перед повтором
4. **Кешируй результаты** если данные не меняются часто
5. **Используй дополнительные параметры API только когда необходимо** - они замедляют запросы
