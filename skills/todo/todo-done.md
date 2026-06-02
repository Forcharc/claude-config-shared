# Отметить задачу выполненной

## Аргументы
- `$ARGUMENTS` — номер, текст или "все", опционально `@список`

## Примеры
```
/todo-done 1                → отметить #1 в inbox
/todo-done молоко           → найти по тексту в inbox
/todo-done 2 @work          → отметить #2 в work
/todo-done все              → все задачи в inbox
/todo-done all @work        → все в work
```

## Алгоритм

### 1. Распарси аргументы
- `@список` в конце → список = название
- Иначе → список = `inbox`
- Остальное = query (номер, текст или "все"/"all")

### 2. Выполни

```bash
python3 ~/.claude/scripts/todo_done.py LIST_NAME "QUERY"
```
