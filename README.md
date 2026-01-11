# polyakov-claude-skills

Набор скиллов для Claude Code.

## Установка

### Через маркетплейс (рекомендуется)

```bash
# Добавить маркетплейс
/plugin marketplace add polyakov/polyakov-claude-skills

# Установить нужные плагины
/plugin install docx-contracts
/plugin install scrapedo-web-scraper
/plugin install agent-deck
/plugin install genome-analizer
/plugin install ssh-remote-connection
```

### Ручная установка (без маркетплейса)

Если вы не хотите использовать маркетплейс, скопируйте папку скилла в директорию `.claude/skills/`:

**Глобально (для всех проектов):**
```bash
# Создать директорию если не существует
mkdir -p ~/.claude/skills

# Скопировать нужный скилл
cp -r plugins/agent-deck/skills/agent-deck ~/.claude/skills/
```

**Для конкретного проекта:**
```bash
# В корне проекта
mkdir -p .claude/skills

# Скопировать скилл
cp -r plugins/genome-analizer/skills/genome-analizer .claude/skills/
```

После копирования Claude Code автоматически подхватит скилл при следующем запуске.

### Локальное тестирование

```bash
claude --plugin-dir ./plugins/agent-deck
```

---

## Доступные скиллы

### [docx-contracts](plugins/docx-contracts/skills/docx-contracts)

Заполнение Word шаблонов (договоры, формы) по данным из контекста.

- Подставляет значения в плейсхолдеры `{{VARIABLE}}`
- Извлекает схему из шаблона
- Спрашивает недостающие данные

**Триггеры:** загрузка .docx файла с плейсхолдерами

---

### [scrapedo-web-scraper](plugins/scrapedo-web-scraper/skills/scrapedo-web-scraper)

Веб-скрапинг через Scrape.do с обходом защит и JavaScript рендерингом.

- Обход блокировок и CAPTCHA
- Поддержка JavaScript-рендеринга
- Извлечение текста из HTML

**Триггеры:** когда обычный fetch не работает

---

### [agent-deck](plugins/agent-deck/skills/agent-deck)

Управление сессиями AI агентов через agent-deck CLI.

- Создание и запуск дочерних сессий Claude
- Отслеживание статуса и получение результатов
- Подключение MCP серверов
- Иерархия parent-child сессий

**Триггеры (RU):**
- "запусти агента" / "запусти саб-агента"
- "проверь сессию" / "проверь статус"
- "покажи вывод агента"

**Триггеры (EN):**
- "launch sub-agent" / "create sub-agent"
- "check session" / "show agent output"

---

### [genome-analizer](plugins/genome-analizer/skills/genome-analizer)

Анализ генетических данных из VCF файла.

- Поиск SNP по теме вопроса (GWAS Catalog, SNPedia)
- Интерпретация генотипов
- Генерация персонализированных отчётов с рекомендациями

**Триггеры (RU):**
- "проанализируй мой геном"
- "что у меня с генетикой по [теме]"
- "мой генотип для [признака]"

**Триггеры (EN):**
- "analyze my genome"
- "what's my genetics for [topic]"

---

### [ssh-remote-connection](plugins/ssh-remote-connection/skills/ssh-remote-connection)

SSH подключение к удалённым серверам с agent forwarding.

- Выполнение команд на удалённом сервере
- Agent forwarding (`-A`) для использования локальных SSH ключей
- Управление Docker контейнерами, просмотр логов

**Триггеры (RU):**
- "выполни на сервере"
- "проверь логи на сервере"
- "перезапусти сервис"

**Триггеры (EN):**
- "run on server"
- "check server logs"
- "restart service"

---

## Структура репозитория

```
polyakov-claude-skills/
├── .claude-plugin/
│   └── marketplace.json      # Маркетплейс конфигурация
├── plugins/
│   ├── docx-contracts/       # Плагин для .docx
│   ├── scrapedo-web-scraper/ # Плагин для скрапинга
│   ├── agent-deck/           # Плагин для агентов
│   ├── genome-analizer/      # Плагин для анализа генома
│   └── ssh-remote-connection/# Плагин для SSH
└── README.md
```

---

## Лицензия

MIT
