# Показать TODO список

## Аргументы
- `$ARGUMENTS` — название списка (по умолчанию `inbox`) или `--all` для всех

## Примеры
```
/todo-list              → inbox
/todo-list work         → work
/todo-list --all        → все списки
```

## Выполни

```bash
python3 ~/.claude/scripts/todo_list.py LIST_NAME
```

Замени `LIST_NAME` на название списка из аргументов (или `inbox` если пусто).
