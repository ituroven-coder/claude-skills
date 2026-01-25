# Security Guardian

Система защитных хуков для Claude Code, позволяющая безопасно работать в режиме `--dangerously-skip-permissions`.

## Философия защиты

**Главный принцип: границы директорий важнее паттернов имён файлов.**

| Уровень | Защита | Надёжность |
|---------|--------|------------|
| **1. Границы директорий** | Любая операция за пределами проекта → блок | Высокая |
| **2. Белый список путей** | Пользователь явно добавляет разрешённые директории | Высокая |
| **3. Паттерны имён** | Дополнительный слой для типичных секретов внутри проекта | Средняя |

## Установка

### 1. Установить зависимости

```bash
cd .claude/hooks/security-guardian
uv sync
# или
pip install -e .
```

### 2. Добавить хуки в settings.json

Скопируйте содержимое `settings.template.json` в ваш `.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash|Read|Write|Edit|Glob|Grep|NotebookEdit",
        "hooks": [
          {
            "type": "command",
            "command": "uv run \"$CLAUDE_PROJECT_DIR/.claude/hooks/security-guardian/main.py\" 2>/dev/null || python3 \"$CLAUDE_PROJECT_DIR/.claude/hooks/security-guardian/main.py\"",
            "timeout": 10000
          }
        ]
      }
    ]
  }
}
```

### 3. Настроить конфигурацию (опционально)

Отредактируйте `config/security_config.yaml` под ваши нужды:

```yaml
directories:
  allowed_paths:
    - "${HOME}/Documents/shared-libs"
    - "/tmp/claude"
```

## Защиты

### Границы директорий (PRIMARY)
- Чтение/запись за пределами проекта → блок
- Симлинки за пределы проекта → блок (через realpath)
- Относительные пути типа `../../../etc` → блок

### Git-операции
- `git push --force` → блок (предложить `--force-with-lease`)
- `git reset --hard` → confirm
- `git branch -D` → confirm
- `git clean -fd` → confirm (но `--dry-run` разрешён)

### Обход защиты
- `eval` → блок
- `$VAR` как команда → блок
- `curl | bash` → блок
- `sh -c "..."` → блок

### Скачивание файлов
- Исполняемые файлы (.py, .sh, .exe) → дать команду пользователю
- Архивы → разрешено, но распаковка контролируется

### Секреты
- `.env` файлы → блок чтения
- `.env.example` → разрешено

## Тестирование

```bash
uv run -m pytest
```

## Структура

```
security-guardian/
├── main.py               # Entry point
├── pyproject.toml        # Dependencies
├── config/
│   └── security_config.yaml
├── parsers/
│   ├── bash_parser.py    # AST-парсинг через bashlex
│   └── path_parser.py    # Резолв путей
├── checks/
│   ├── directory_check.py    # Границы директорий (PRIMARY)
│   ├── git_check.py          # Git-операции
│   ├── deletion_check.py     # Удаление файлов
│   ├── bypass_check.py       # Обход защиты
│   ├── download_check.py     # Скачивание файлов
│   ├── unpack_check.py       # Распаковка архивов
│   ├── execution_check.py    # chmod +x
│   └── secrets_check.py      # Секреты
├── handlers/
│   ├── bash_handler.py
│   ├── read_handler.py
│   ├── write_handler.py
│   └── glob_grep_handler.py
└── messages/
    └── guidance.py       # Подсказки для Claude
```

## Логирование

Логи сохраняются в `~/.claude/logs/security-guardian/`.

Содержат только метаданные (команда, путь, причина блокировки), не содержат контент файлов.
