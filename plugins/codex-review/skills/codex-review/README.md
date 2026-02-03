# Codex Review Plugin

Кросс-агентное ревью: Claude Code реализует, Codex (GPT) ревьюит.

## Установка

1. Добавь плагин в проект:

```bash
claude plugins add /path/to/polyakov-claude-skills/plugins/codex-review
```

Или через marketplace:

```bash
claude plugins add codex-review --registry polyakov-claude-skills
```

2. Убедись, что `codex` CLI установлен:

```bash
npm install -g @openai/codex
```

## Настройка проекта

### .gitignore

Добавь в `.gitignore` проекта:

```
.codex-review/state.json
.codex-review/config.env
```

> `notes/` **НЕ** игнорируем — это журнал ревью для команды.

### AGENTS.md (для Codex)

Добавь в `AGENTS.md` проекта секцию:

```markdown
## Review Protocol

Если ты выступаешь ревьювером (запущен через codex-review workflow):
- Давай конкретный actionable фидбек
- Можешь смотреть код/diff самостоятельно
- Не запускай скрипты из skills/codex-review/ — ты ревьюер
```

### settings.local.json

Добавь разрешения в `.claude/settings.local.json`:

```json
{
  "permissions": {
    "allow": [
      "Bash(bash */codex-review.sh:*)",
      "Bash(bash */codex-state.sh:*)",
      "Bash(codex exec:*)"
    ]
  }
}
```

### Конфигурация (опционально)

Создай `.codex-review/config.env` в корне проекта:

```bash
CODEX_MODEL=o4-mini
CODEX_REASONING_EFFORT=high
CODEX_MAX_ITERATIONS=3
CODEX_YOLO=true
```

См. `config/defaults.env.example` для всех параметров.

## Использование

### Создание сессии

```
"Используем workflow с codex ревьювером. Задачи: #23, #10"
```

Claude попросит создать сессию Codex с промптом для ревьюера.

### Workflow

1. **Init** — Claude создает сессию Codex
2. **Plan Review** — Claude описывает план, Codex ревьюит
3. **Implementation** — Claude реализует по плану
4. **Code Review** — Claude описывает изменения, Codex ревьюит
5. **Done** — результат пользователю

### Управление состоянием

```bash
bash scripts/codex-state.sh show          # Текущее состояние
bash scripts/codex-state.sh reset         # Сброс итераций
bash scripts/codex-state.sh reset --full  # Полный сброс
bash scripts/codex-state.sh set session_id <value>  # Ручная установка
```

## Структура .codex-review/

В корне проекта создается директория:

```
.codex-review/
├── config.env              # gitignore — настройки
├── state.json              # gitignore — транзиентное состояние
├── notes/                  # В GIT — журнал ревью для команды
│   ├── .gitkeep
│   ├── plan-review-1.md
│   └── code-review-1.md
└── .gitkeep
```

## CLAUDE.md

Добавь в CLAUDE.md проекта:

```markdown
## Codex Review
- Задача: [описание]
- Статус: [planning|reviewing_plan|implementing|reviewing_code|done]
- Журнал: `.codex-review/notes/`
```

## Анти-рекурсия

Плагин защищен от рекурсивного вызова на 3 уровнях:

1. **Env guard** — `CODEX_REVIEWER=1` при вызове codex exec; если скрипт вызван с этой переменной — exit 1
2. **Промпт-контекст** — путь к скиллу в промпте для ориентации
3. **AGENTS.md** — инструкция для Codex о роли ревьюера
