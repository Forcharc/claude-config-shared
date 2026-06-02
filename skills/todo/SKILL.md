---
name: todo
description: "Manage TODO lists via Gist-based storage"
---

# TODO — универсальная команда для задач

Управляй задачами простым языком.

## Настройка (один раз)

Скрипты берут доступ к GitHub из переменных окружения — секретов в коде нет.
Добавь в `~/.zshrc` (или `~/.bashrc`) и перезапусти шелл:

```bash
export GITHUB_GIST_TOKEN=ghp_xxx        # токен с scope "gist"
export GITHUB_TODO_GIST_ID=xxx          # id gist, где лежат todo-списки
export GITHUB_USER=your-github-username
```

Токен: https://github.com/settings/tokens (scope: gist). Gist для списков — создай
пустой на https://gist.github.com и подставь его id. Если переменная не задана,
скрипт сам подскажет, чего не хватает.

## Аргументы
- `$ARGUMENTS` — что хочешь сделать, простым языком

## Примеры запросов
```
/todo покажи мои задачи
/todo что там по работе?
/todo добавь "сделать ревью" в рабочие
/todo купить молоко
/todo отметь первую задачу
/todo выполнил всё в inbox
/todo удали выполненные
/todo какие есть списки?
```

## Алгоритм

### 1. Пойми намерение пользователя

| Намерение | Скрипт |
|-----------|--------|
| Показать задачи | `todo_list.py` |
| Добавить задачу | `todo_add.py` |
| Отметить выполненной | `todo_done.py` |
| Удалить | `todo_delete.py` |

### 2. Определи список

Сначала проверь существующие списки!

```bash
python3 ~/.claude/scripts/todo_list.py --names
```

Если список не указан явно — используй `inbox`.

Нормализуй названия:
- "работа", "рабочие" → `work`
- "личное" → `personal`
- "покупки" → `shopping`
- "бенчмарк" → `benchmark`

### 3. Выполни соответствующий скрипт

**ВАЖНО:** НЕ выполняй несколько todo-команд через `&&` в одной строке bash!
Это вызывает HTTP 409 Conflict (race condition при обновлении gist).
Выполняй команды по одной.

```bash
# Показать названия списков (без содержимого)
python3 ~/.claude/scripts/todo_list.py --names

# Показать конкретный список
python3 ~/.claude/scripts/todo_list.py LIST_NAME

# Показать все списки с содержимым (редко нужно!)
python3 ~/.claude/scripts/todo_list.py --all

# Добавить
python3 ~/.claude/scripts/todo_add.py LIST_NAME "задача"

# Выполнить
python3 ~/.claude/scripts/todo_done.py LIST_NAME "QUERY"  # номер, текст или "all"
python3 ~/.claude/scripts/todo_done.py LIST_NAME "1,3,5"  # несколько номеров за раз

# Удалить задачу
python3 ~/.claude/scripts/todo_delete.py LIST_NAME "QUERY"
python3 ~/.claude/scripts/todo_delete.py LIST_NAME "1,3,5"  # несколько номеров за раз

# Удалить список
python3 ~/.claude/scripts/todo_delete.py --list LIST_NAME
```

### 4. Покажи результат понятно