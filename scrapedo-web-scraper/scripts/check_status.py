#!/usr/bin/env python3
"""
Проверка статуса токена Scrape.do и доступности API
"""

import os
import sys
import requests
from pathlib import Path


def get_token():
    """Получает токен из различных источников"""
    # Определяем путь к директории skill'а
    script_dir = Path(__file__).parent.parent
    
    # Вариант 1: config/token.txt
    token_file = script_dir / 'config' / 'token.txt'
    if token_file.exists():
        try:
            token = token_file.read_text().strip()
            if token:
                return token, f"config/token.txt"
        except Exception:
            pass
    
    # Вариант 2: Переменная окружения SCRAPEDO_TOKEN
    token = os.environ.get('SCRAPEDO_TOKEN')
    if token:
        return token, "переменная окружения SCRAPEDO_TOKEN"
    
    # Вариант 3: .env файл
    env_file = script_dir / '.env'
    if env_file.exists():
        try:
            for line in env_file.read_text().splitlines():
                if line.startswith('SCRAPEDO_TOKEN='):
                    token = line.split('=', 1)[1].strip().strip('"').strip("'")
                    if token:
                        return token, ".env файл"
        except Exception:
            pass
    
    return None, None


def check_scrapedo_status():
    """Проверяет статус токена и API Scrape.do"""
    
    print("🔍 Проверка конфигурации Scrape.do...\n")
    
    # Определяем пути
    script_dir = Path(__file__).parent.parent
    config_dir = script_dir / 'config'
    token_file = config_dir / 'token.txt'
    
    # Проверяем наличие токена
    token, source = get_token()
    
    if not token:
        print("❌ Токен не найден")
        print("\n📝 Инструкция по установке токена:")
        print("\nВариант 1 (рекомендуется): Создайте файл с токеном")
        print(f"   mkdir -p {config_dir}")
        print(f"   echo 'ваш_токен' > {token_file}")
        print("\nВариант 2: Установите переменную окружения")
        print("   export SCRAPEDO_TOKEN='ваш_токен'")
        print("\nВариант 3: Создайте .env файл в директории skill'а")
        print(f"   echo 'SCRAPEDO_TOKEN=ваш_токен' > {script_dir}/.env")
        return False
    
    print(f"✅ Токен найден")
    print(f"   Источник: {source}")
    print(f"   Длина: {len(token)} символов")
    
    # Проверяем работу API с простым запросом
    print("\n📡 Проверка доступности API...")
    
    try:
        # Тестовый запрос к example.com
        test_url = "http://api.scrape.do"
        params = {
            'token': token,
            'url': 'https://example.com'
        }
        
        response = requests.get(test_url, params=params, timeout=10)
        
        if response.status_code == 200:
            print("✅ API доступен и токен валиден")
            print(f"   Статус: {response.status_code}")
            print(f"   Размер ответа: {len(response.text)} байт")
            
            # Проверяем, что получили HTML
            if '<html' in response.text.lower():
                print("   Контент: HTML страница получена корректно")
            
            print("\n✅ Все проверки пройдены успешно!")
            print("\n💡 Совет: Для безопасности используйте файл config/token.txt")
            print(f"   Текущий источник токена: {source}")
            return True
            
        elif response.status_code == 401:
            print("❌ Неверный токен или сервис заблокирован")
            print("   Проверьте правильность токена")
            print(f"   Текущий токен из: {source}")
            return False
            
        elif response.status_code == 429:
            print("⚠️  Превышен лимит запросов")
            print("   API работает, но достигнут лимит")
            print("   Токен валиден, подождите или увеличьте тариф")
            return False
            
        else:
            print(f"⚠️  Неожиданный статус: {response.status_code}")
            return False
            
    except requests.exceptions.Timeout:
        print("❌ Таймаут при подключении к API")
        return False
    except requests.exceptions.RequestException as e:
        print(f"❌ Ошибка подключения: {e}")
        return False
    except Exception as e:
        print(f"❌ Неожиданная ошибка: {e}")
        return False


if __name__ == '__main__':
    success = check_scrapedo_status()
    sys.exit(0 if success else 1)
