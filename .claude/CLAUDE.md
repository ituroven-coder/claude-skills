# Правила проекта polyakov-claude-skills

## plugin.json — формат манифеста

При создании/редактировании `.claude-plugin/plugin.json`:

- **`author`** — ОБЯЗАТЕЛЬНО объект: `{"name": "Polyakov"}`. Строка вызывает ошибку валидации.
- **`skills`** — НЕ валидное поле. Не добавлять. Скиллы обнаруживаются автоматически из `skills/` директории.
- Эталонный формат:
  ```json
  {
    "name": "plugin-name",
    "version": "1.0.0",
    "description": "...",
    "author": {
      "name": "Polyakov"
    }
  }
  ```

## marketplace.json

- При добавлении нового плагина — обязательно добавить запись в `.claude-plugin/marketplace.json` → `plugins[]`, иначе плагин не будет виден через `/plugin install`.
