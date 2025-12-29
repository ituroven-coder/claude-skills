# Scrape.do API Reference

## Основные параметры API

### Обязательные параметры
- `token` - API токен (из переменной GLOBAL_SYSTEM_SCRAPEDO_TOKEN)
- `url` - URL для скрапинга (должен быть закодирован)

### Дополнительные параметры Scrape.do

#### Рендеринг JavaScript
- `render=true` - включить рендеринг JavaScript (по умолчанию false)
- `waitUntil=networkidle2` - ждать загрузки всех ресурсов
- `waitFor=3000` - ждать указанное время в мс

#### Прокси и геолокация
- `geoCode=us` - использовать прокси из указанной страны
- `super=true` - использовать премиум прокси
- `regional=true` - использовать резидентные прокси

#### Обработка блокировок
- `playWithCaptcha=true` - автоматически решать CAPTCHA
- `bypassCf=true` - обходить Cloudflare защиту

#### Настройки браузера
- `device=desktop` - тип устройства (desktop/mobile)
- `width=1920` - ширина viewport
- `height=1080` - высота viewport

## Примеры использования в Python

### Базовый запрос
```python
from scripts.scrape import fetch_via_scrapedo

result = fetch_via_scrapedo('https://example.com')
if result['success']:
    print(result['content'])
```

### Запрос с JavaScript рендерингом
```python
import os
import requests
import urllib.parse

token = os.environ.get('GLOBAL_SYSTEM_SCRAPEDO_TOKEN')
url = urllib.parse.quote('https://example.com', safe='')

response = requests.get(
    'http://api.scrape.do',
    params={
        'token': token,
        'url': url,
        'render': 'true',
        'waitUntil': 'networkidle2'
    }
)
```

### Запрос с обходом Cloudflare
```python
response = requests.get(
    'http://api.scrape.do',
    params={
        'token': token,
        'url': url,
        'bypassCf': 'true',
        'render': 'true'
    }
)
```

## Коды ошибок

| Код | Описание | Решение |
|-----|----------|---------|
| 200 | Успешный запрос | - |
| 401 | Неверный токен | Проверить токен |
| 429 | Превышен лимит | Подождать или увеличить лимит |
| 500 | Ошибка сервера | Повторить позже |

## Лимиты и ограничения

- Стандартный тариф: 1000 запросов в месяц
- Таймаут запроса: 60 секунд
- Максимальный размер страницы: 10 МБ
- Параллельные запросы: зависит от тарифа

## Полезные советы

1. **Оптимизация запросов**
   - Используйте `render=true` только когда необходим JavaScript
   - Кешируйте результаты локально

2. **Обработка ошибок**
   - Всегда проверяйте статус ответа
   - Реализуйте retry логику для временных ошибок

3. **Безопасность**
   - Никогда не храните токен в коде
   - Используйте переменные окружения

## Дополнительная информация

Официальная документация: https://scrape.do/docs
