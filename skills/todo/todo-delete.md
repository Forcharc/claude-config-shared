# Удалить задачу или список

## Аргументы
- `$ARGUMENTS` — что удалить

## Примеры
```
/todo-delete 1                  → удалить задачу #1 из inbox
/todo-delete молоко             → найти и удалить по тексту
/todo-delete done               → удалить все выполненные из inbox
/todo-delete 3 @work            → удалить #3 из work
/todo-delete --list work        → удалить весь список work
```

## Алгоритм

### 1. Распарси аргументы
- `--list название` → удалить весь список
- `@список` в конце → список = название
- Иначе → список = `inbox`
- Остальное = query

### 2. Выполни

Удалить задачу:
```bash
python3 ~/.claude/scripts/todo_delete.py LIST_NAME "QUERY"
```

Удалить весь список:
```bash
python3 ~/.claude/scripts/todo_delete.py --list LIST_NAME
```
