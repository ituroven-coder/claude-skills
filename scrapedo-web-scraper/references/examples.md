# Примеры использования Scrape.do Skill

## Настройка перед использованием

### 1. Установка токена
```bash
# Создайте файл с токеном (рекомендуется)
echo 'ваш_токен_scrape.do' > config/token.txt

# Или используйте переменную окружения
export SCRAPEDO_TOKEN='ваш_токен'
```

### 2. Проверка конфигурации
```bash
python scripts/check_status.py
```

## Простые примеры

### Извлечение текста со страницы
```python
from scripts.scrape import fetch_via_scrapedo

# Скрапинг новостной статьи
result = fetch_via_scrapedo('https://example.com/article')
if result['success']:
    print(result['content'])  # Текстовое содержимое
else:
    print(f"Ошибка: {result['content']}")
```

### Получение HTML для парсинга
```python
from scripts.scrape import fetch_via_scrapedo
from bs4 import BeautifulSoup

result = fetch_via_scrapedo('https://example.com/products')
if result['success']:
    soup = BeautifulSoup(result['html'], 'html.parser')
    
    # Извлечение конкретных элементов
    products = soup.find_all('div', class_='product')
    for product in products:
        name = product.find('h2').text
        price = product.find('span', class_='price').text
        print(f"{name}: {price}")
```

## Продвинутые примеры

### Скрапинг SPA (Single Page Application)
```python
import os
import requests
import urllib.parse
from bs4 import BeautifulSoup
from pathlib import Path

def get_token():
    """Получает токен из config/token.txt или переменной окружения"""
    # Путь к файлу токена
    token_file = Path(__file__).parent.parent / 'config' / 'token.txt'
    if token_file.exists():
        return token_file.read_text().strip()
    
    # Из переменной окружения
    return os.environ.get('SCRAPEDO_TOKEN')

def scrape_spa(url):
    """Скрапинг сайта с JavaScript рендерингом"""
    token = get_token()
    if not token:
        raise ValueError("Токен не найден. Создайте config/token.txt")
    
    encoded_url = urllib.parse.quote(url, safe='')
    
    response = requests.get(
        'http://api.scrape.do',
        params={
            'token': token,
            'url': encoded_url,
            'render': 'true',
            'waitUntil': 'networkidle2',
            'waitFor': '3000'  # Ждем 3 секунды после загрузки
        }
    )
    
    if response.status_code == 200:
        return response.text
    else:
        raise Exception(f"Ошибка скрапинга: {response.status_code}")

# Использование
html = scrape_spa('https://example.com/spa-app')
soup = BeautifulSoup(html, 'html.parser')
```

### Обход защиты Cloudflare
```python
def scrape_protected_site(url):
    """Скрапинг сайта с Cloudflare защитой"""
    token = get_token()  # Использует функцию выше
    if not token:
        raise ValueError("Токен не найден")
    
    encoded_url = urllib.parse.quote(url, safe='')
    
    response = requests.get(
        'http://api.scrape.do',
        params={
            'token': token,
            'url': encoded_url,
            'bypassCf': 'true',
            'render': 'true',
            'super': 'true'  # Используем премиум прокси
        }
    )
    
    return response.text
```

### Массовый скрапинг с обработкой ошибок
```python
import time
from scripts.scrape import fetch_via_scrapedo

def scrape_multiple_urls(urls, delay=1):
    """Скрапинг нескольких URL с задержкой"""
    results = []
    
    for url in urls:
        print(f"Скрапинг: {url}")
        
        # Попытка скрапинга с retry
        for attempt in range(3):
            result = fetch_via_scrapedo(url)
            
            if result['success']:
                results.append({
                    'url': url,
                    'content': result['content'],
                    'success': True
                })
                break
            elif '429' in result['content']:  # Rate limit
                print(f"Rate limit, ждем {delay * 2} секунд...")
                time.sleep(delay * 2)
            else:
                if attempt == 2:  # Последняя попытка
                    results.append({
                        'url': url,
                        'error': result['content'],
                        'success': False
                    })
        
        # Задержка между запросами
        time.sleep(delay)
    
    return results

# Использование
urls = [
    'https://example.com/page1',
    'https://example.com/page2',
    'https://example.com/page3'
]

results = scrape_multiple_urls(urls, delay=2)
for result in results:
    if result['success']:
        print(f"✓ {result['url']}: {len(result['content'])} символов")
    else:
        print(f"✗ {result['url']}: {result['error']}")
```

### Извлечение структурированных данных
```python
import json
from scripts.scrape import fetch_via_scrapedo
from bs4 import BeautifulSoup

def extract_structured_data(url):
    """Извлечение структурированных данных (JSON-LD)"""
    result = fetch_via_scrapedo(url)
    
    if not result['success']:
        return None
    
    soup = BeautifulSoup(result['html'], 'html.parser')
    
    # Поиск JSON-LD данных
    json_ld_scripts = soup.find_all('script', type='application/ld+json')
    
    structured_data = []
    for script in json_ld_scripts:
        try:
            data = json.loads(script.string)
            structured_data.append(data)
        except json.JSONDecodeError:
            continue
    
    return structured_data

# Использование
data = extract_structured_data('https://example.com/product')
if data:
    for item in data:
        if item.get('@type') == 'Product':
            print(f"Товар: {item.get('name')}")
            print(f"Цена: {item.get('offers', {}).get('price')}")
```

## CLI использование

### Базовый скрапинг через командную строку
```bash
# Получить текст страницы
python scripts/scrape.py https://example.com

# Получить HTML
python scripts/scrape.py --html https://example.com

# Использовать конкретный токен
python scripts/scrape.py --token YOUR_TOKEN https://example.com

# Сохранить результат в файл
python scripts/scrape.py https://example.com > content.txt

# Проверить статус API
python scripts/check_status.py
```

## Обработка специальных случаев

### Работа с пагинацией
```python
def scrape_paginated_content(base_url, max_pages=10):
    """Скрапинг страниц с пагинацией"""
    all_content = []
    
    for page in range(1, max_pages + 1):
        url = f"{base_url}?page={page}"
        result = fetch_via_scrapedo(url)
        
        if not result['success']:
            print(f"Ошибка на странице {page}")
            break
        
        # Проверяем, есть ли контент
        if "No results found" in result['content']:
            break
        
        all_content.append(result['content'])
        time.sleep(1)  # Задержка между запросами
    
    return all_content
```

### Работа с динамическим контентом
```python
def scrape_dynamic_content(url, wait_selector=None):
    """Скрапинг с ожиданием загрузки элемента"""
    params = {
        'render': 'true',
        'waitUntil': 'networkidle0'
    }
    
    if wait_selector:
        params['waitSelector'] = wait_selector
    
    # Здесь нужен прямой вызов API для дополнительных параметров
    # ... реализация
```

## Лучшие практики

1. **Всегда проверяйте наличие токена перед началом работы**
2. **Используйте задержки между запросами для избежания rate limiting**
3. **Кешируйте результаты, если данные не меняются часто**
4. **Обрабатывайте ошибки gracefully**
5. **Логируйте запросы для отладки**
