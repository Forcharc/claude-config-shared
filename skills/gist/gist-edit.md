# Редактировать Gist

## Аргументы
- `$ARGUMENTS` — что отредактировать и как

## Примеры
```
/gist-edit обнови описание в моём последнем gist
/gist-edit добавь файл script.py в gist abc123
/gist-edit замени содержимое notes.md в https://gist.github.com/...
/gist-edit удали старый файл из gist
```

## Алгоритм

### 1. Определи gist
- Если пользователь дал ссылку/ID — используй его
- Если нет — покажи список через `python3 ~/.claude/scripts/gist_list.py` и уточни

### 2. Определи действие

**Обновить файл:**
```bash
python3 ~/.claude/scripts/gist_update.py GIST_ID filename.md "новый контент"
```

**Добавить файл:**
```bash
python3 ~/.claude/scripts/gist_update.py GIST_ID --add newfile.md "контент"
```

**Удалить файл:**
```bash
python3 ~/.claude/scripts/gist_update.py GIST_ID --delete oldfile.md
```

**Изменить описание:**
```bash
python3 ~/.claude/scripts/gist_update.py GIST_ID --description "Новое описание"
```

**Посмотреть содержимое gist:**
```bash
python3 ~/.claude/scripts/gist_update.py GIST_ID
```

### 3. Покажи результат
