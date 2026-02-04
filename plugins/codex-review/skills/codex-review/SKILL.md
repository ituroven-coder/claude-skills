---
name: codex-review
description: |
  Workflow кросс-агентного ревью с Codex.
  Triggers (RU): "кодекс ревью".
  Triggers (EN): "with codex review", "codex review workflow",
  "start codex review".
  ВАЖНО: при срабатывании триггера прочитай SKILL.md до любых других шагов.
---

# Codex Review Workflow

Кросс-агентное ревью: Claude реализует, Codex (GPT) ревьюит. Codex работает в той же директории и может самостоятельно смотреть код.

## Расположение скриптов

Скрипты лежат в `scripts/` рядом с этим SKILL.md. Определи полный путь:
- Этот файл: путь из которого ты прочитал SKILL.md
- Скрипты: замени `SKILL.md` на `scripts/codex-review.sh` (и `scripts/codex-state.sh`)

Все команды ниже используют относительный `scripts/` — подставь полный путь при вызове.

## Workflow

### 1. Инициализация сессии

Сессия может быть задана двумя способами:
- В `.codex-review/config.env` проекта: `CODEX_SESSION_ID=sess_...`
- Через команду `init` (создаёт новую)

Если сессии нет (exit 3 — NO_SESSION), спроси пользователя:
- Есть ли уже живая сессия с Codex? → пусть впишет id в config.env
- Или создать новую?

Аргумент `init` — описание задачи (не промпт ревьюера). Промпт ревьюера формируется скриптом автоматически. Для кастомизации используй `CODEX_REVIEWER_PROMPT` в `config.env`.

```bash
bash scripts/codex-review.sh init "Implement JWT authentication for API"
```

### 2. Ревью плана

Опиши ЧТО собираешься делать, КАКОЙ подход выбрал и ПОЧЕМУ.

```bash
bash scripts/codex-review.sh plan "План: реализовать авторизацию через JWT. Подход: middleware проверяет токен, refresh через отдельный endpoint. Решение: выбрал JWT вместо session-based т.к. API stateless."
```

### 3. Реализация

Перед началом реализации обнови фазу:

```bash
bash scripts/codex-state.sh set phase implementing
```

Имплементируй по утвержденному плану.

### 4. Ревью кода

Опиши ЧТО сделал, КАКИЕ решения принимал. НЕ передавай git diff — Codex сам посмотрит.

```bash
bash scripts/codex-review.sh code "Реализовал JWT auth: middleware в auth/jwt.py проверяет токен, refresh endpoint в api/auth.py. Добавил тесты для expired/invalid/valid токенов."
```

### 5. Управление состоянием

```bash
bash scripts/codex-state.sh show              # Текущее состояние
bash scripts/codex-state.sh reset             # Сброс итераций (session сохраняется)
bash scripts/codex-state.sh reset --full      # Полный сброс
bash scripts/codex-state.sh get session_id    # Получить поле
bash scripts/codex-state.sh set session_id <val>  # Установить вручную
bash scripts/codex-state.sh set phase implementing  # Обновить фазу
```

## Обработка exit-кодов

| Exit | Status | Действие |
|------|--------|----------|
| 0 | APPROVED | Продолжай работу |
| 0 | CHANGES_REQUESTED | Скорректируй и отправь снова |
| 1 | ERROR | Сообщи об ошибке, предложи проверить session_id |
| 2 | ESCALATE | Покажи пользователю историю из .codex-review/notes/ |
| 3 | NO_SESSION | Спроси: создать сессию? |

## STATUS.md

Файл `.codex-review/STATUS.md` создаётся и обновляется автоматически скриптами. Не редактируй его вручную.

- Файл **появляется** при `init` и обновляется при каждом `plan`/`code` и `codex-state.sh set`
- Файл **удаляется** при финальном APPROVED на этапе `code` и при `reset --full`
- Наличие файла = активное ревью, отсутствие = ревью не идёт

## Verdict

Codex пишет свой вердикт в `.codex-review/verdict.txt` (одно слово: `APPROVED` или `CHANGES_REQUESTED`). Файл очищается перед каждым запросом ревью. Если Codex не создал файл — скрипт парсит вердикт из текста ответа (fallback).

## Правила

- НИКОГДА не вызывай `codex exec` напрямую — только через скрипты `codex-review.sh` и `codex-state.sh`. Скрипты сами знают модель, конфиг и session_id
- Описывай ЧТО ты сделал и ПОЧЕМУ, какие решения принимал
- НЕ передавай git diff — Codex сам посмотрит, он в той же директории
- CHANGES_REQUESTED → скорректируй и отправь снова (max 3 итерации)
- APPROVED → продолжай работу
- Перед реализацией вызови `codex-state.sh set phase implementing`
- Есть заказчик (пользователь) — уточняй у него неоднозначные вопросы
- Опция `--max-iter N` позволяет изменить лимит итераций
