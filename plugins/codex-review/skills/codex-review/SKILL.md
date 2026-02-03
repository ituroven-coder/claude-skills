---
name: codex-review
description: |
  Workflow кросс-агентного ревью с Codex.
  Triggers (RU): "workflow с codex ревьювером", "codex review workflow",
  "отправь на ревью в codex", "запусти codex ревью".
  Triggers (EN): "use codex review workflow", "start codex review",
  "send to codex for review".
---

# Codex Review Workflow

Кросс-агентное ревью: Claude реализует, Codex (GPT) ревьюит. Codex работает в той же директории и может самостоятельно смотреть код.

## Workflow

### 1. Инициализация сессии

Если сессии нет (exit 3 — NO_SESSION), спроси пользователя:
- Создать сессию? С каким промптом?
- Промпт должен описывать роль Codex (ревьюер проекта X, фокус на Y)

```bash
bash scripts/codex-review.sh init "Ты ревьюер проекта auth, фокус на безопасности"
```

### 2. Ревью плана

Опиши ЧТО собираешься делать, КАКОЙ подход выбрал и ПОЧЕМУ.

```bash
bash scripts/codex-review.sh plan "План: реализовать авторизацию через JWT. Подход: middleware проверяет токен, refresh через отдельный endpoint. Решение: выбрал JWT вместо session-based т.к. API stateless."
```

### 3. Реализация

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
```

## Обработка exit-кодов

| Exit | Status | Действие |
|------|--------|----------|
| 0 | APPROVED | Продолжай работу |
| 0 | CHANGES_REQUESTED | Скорректируй и отправь снова |
| 1 | ERROR | Сообщи об ошибке, предложи проверить session_id |
| 2 | ESCALATE | Покажи пользователю историю из .codex-review/notes/ |
| 3 | NO_SESSION | Спроси: создать сессию? с каким промптом? |

## Правила

- Описывай ЧТО ты сделал и ПОЧЕМУ, какие решения принимал
- НЕ передавай git diff — Codex сам посмотрит, он в той же директории
- CHANGES_REQUESTED → скорректируй и отправь снова (max 3 итерации)
- APPROVED → продолжай работу
- Есть заказчик (пользователь) — уточняй у него неоднозначные вопросы
- Опция `--max-iter N` позволяет изменить лимит итераций
