# Codex Review Plugin

Кросс-агентное ревью: Claude Code реализует, Codex (GPT) ревьюит.

> **ВАЖНО!** Скрипты плагина хранят всё состояние (сессию, конфиг, журнал ревью) в директории `.codex-review/` **в корне вашего проекта**, а не рядом с собой. Директория `config/` внутри плагина — это только шаблон. Не редактируйте файлы в директории установки плагина (`~/.claude/plugins/...`) — они перезапишутся при обновлении.

## Установка

### Вариант A: через marketplace (рекомендуется)

1. Добавь репозиторий как marketplace (один раз):

```bash
# Из локальной директории
claude plugin marketplace add /path/to/polyakov-claude-skills

# Или из GitHub
claude plugin marketplace add github:artwist-polyakov/polyakov-claude-skills
```

2. Установи плагин:

```bash
claude plugin install codex-review@polyakov-claude-skills
```

### Вариант B: для одной сессии

```bash
claude --plugin-dir /path/to/polyakov-claude-skills/plugins/codex-review
```

### Зависимости

Убедись, что `codex` CLI установлен:

```bash
npm install -g @openai/codex
```

## Настройка проекта

### .gitignore

Добавь в `.gitignore` проекта:

```
.codex-review/state.json
.codex-review/config.env
.codex-review/STATUS.md
.codex-review/verdict.txt
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
- После ревью запиши вердикт в .codex-review/verdict.txt (одно слово: APPROVED или CHANGES_REQUESTED)
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
# Существующая сессия Codex (или используй init для создания новой)
# CODEX_SESSION_ID=sess_your_session_id

CODEX_MODEL=gpt-5.2
CODEX_REASONING_EFFORT=high
CODEX_MAX_ITERATIONS=5
CODEX_YOLO=true

# Custom reviewer prompt (optional, replaces built-in default)
# CODEX_REVIEWER_PROMPT="You are a security-focused code reviewer..."
```

## Использование

### Подключение существующей сессии Codex

Если у вас уже есть живая сессия с Codex (например, вы обсуждали архитектуру), впишите её id в `.codex-review/config.env`:

```bash
CODEX_SESSION_ID=sess_ваш_id
```

Узнать id: `codex session list`

Альтернативно — через CLI: `bash scripts/codex-state.sh set session_id sess_ваш_id`

После этого команды `plan` и `code` будут отправлять ревью в эту сессию через `resume`.

### Создание новой сессии

```
"Используем workflow с codex ревьювером. Задачи: #23, #10"
```

Claude создаст сессию Codex автоматически. Аргумент `init` — описание задачи. Промпт для ревьюера формируется скриптом (встроенный или кастомный через `CODEX_REVIEWER_PROMPT`).

### Workflow

1. **Init** — Claude создает сессию Codex с описанием задачи
2. **Plan Review** — Claude описывает план, Codex ревьюит
3. **Implementation** — Claude обновляет фазу и реализует по плану
4. **Code Review** — Claude описывает изменения, Codex ревьюит
5. **Done** — результат пользователю

### Управление состоянием

```bash
bash scripts/codex-state.sh show          # Текущее состояние
bash scripts/codex-state.sh reset         # Сброс итераций
bash scripts/codex-state.sh reset --full  # Полный сброс
bash scripts/codex-state.sh set session_id <value>  # Ручная установка
bash scripts/codex-state.sh set phase implementing  # Обновить фазу
```

## Структура .codex-review/

В корне проекта создается директория:

```
.codex-review/
├── config.env              # gitignore — настройки
├── state.json              # gitignore — транзиентное состояние
├── STATUS.md               # gitignore — автогенерируемый статус для Claude
├── verdict.txt             # gitignore — последний вердикт от Codex
├── notes/                  # В GIT — журнал ревью для команды
│   ├── .gitkeep
│   ├── plan-review-1.md
│   └── code-review-1.md
└── .gitkeep
```

## CLAUDE.md

Добавь в CLAUDE.md проекта (одноразовая настройка):

```markdown
## Codex Review
If `.codex-review/STATUS.md` exists, read it before starting work — an active review is in progress.
```

`STATUS.md` создаётся и обновляется автоматически скриптами плагина. Наличие файла означает активное ревью, отсутствие — ревью не идёт или завершено.

## Анти-рекурсия

Плагин защищен от рекурсивного вызова на 3 уровнях:

1. **Env guard** — `CODEX_REVIEWER=1` при вызове codex exec; если скрипт вызван с этой переменной — exit 1
2. **Промпт-контекст** — путь к скиллу в промпте для ориентации
3. **AGENTS.md** — инструкция для Codex о роли ревьюера
