---
name: gist
description: "Manage GitHub Gists (create, view, update, delete)"
---

# Gist — универсальная команда для заметок

Управляй GitHub Gist'ами простым языком.

## Настройка (один раз)

Скрипты берут доступ к GitHub из переменных окружения — секретов в коде нет.
Добавь в `~/.zshrc` (или `~/.bashrc`) и перезапусти шелл:

```bash
export GITHUB_GIST_TOKEN=ghp_xxx        # токен с scope "gist"
export GITHUB_USER=your-github-username
```

Токен: https://github.com/settings/tokens (scope: gist). Если переменная не задана,
скрипт сам подскажет, чего не хватает.

## Аргументы
- `$ARGUMENTS` — что хочешь сделать, простым языком

## Примеры запросов
```
/gist покажи мои гисты
/gist сохрани этот код
/gist запиши наш разговор про архитектуру
/gist сделай публичный README
/gist добавь файл в мой последний гист
/gist обнови описание
/gist удали файл notes.md из гиста
/gist что в моём гисте abc123?
```

## Алгоритм

### 1. Пойми намерение пользователя

| Намерение | Скрипт |
|-----------|--------|
| Показать список | `gist_list.py` |
| Просмотреть содержимое | `gist_view.py` |
| Создать новый | `gist_create.py` или `gist_from_file.py` |
| Обновить/редактировать | `gist_update.py` |

### 2. Для создания

- **Имя файла**: красивое, английское, с расширением (.md, .py, .js)
- **Описание**: краткое и понятное
- **Публичность**: по умолчанию secret, если просят — `--public`

### 3. Выполни соответствующий скрипт

```bash
# Показать список
python3 ~/.claude/scripts/gist_list.py

# Просмотреть содержимое гиста
python3 ~/.claude/scripts/gist_view.py GIST_ID                    # все файлы
python3 ~/.claude/scripts/gist_view.py GIST_ID filename.md        # конкретный файл
python3 ~/.claude/scripts/gist_view.py GIST_ID filename.md --raw  # без форматирования

# Создать из контента
python3 ~/.claude/scripts/gist_create.py "file.md" "CONTENT" -d "Описание"
python3 ~/.claude/scripts/gist_create.py "file.md" "CONTENT" --public -d "..."

# Создать из файла
python3 ~/.claude/scripts/gist_from_file.py /path/to/file -d "Описание"

# Обновить файл из контента
python3 ~/.claude/scripts/gist_update.py GIST_ID filename.md "новый контент"

# Обновить файл из локального файла (через stdin)
cat /path/to/file | python3 ~/.claude/scripts/gist_update.py GIST_ID filename.md -

# Добавить файл
python3 ~/.claude/scripts/gist_update.py GIST_ID --add new.md "контент"

# Удалить файл
python3 ~/.claude/scripts/gist_update.py GIST_ID --delete old.md

# Изменить описание
python3 ~/.claude/scripts/gist_update.py GIST_ID -d "Новое описание"
```

### 4. Если нужен ID гиста — уточни

Если пользователь не дал ссылку, покажи список и спроси какой гист редактировать.

### 5. Покажи результат и ссылку

---

## Оглавление в гистах

**Каждый гист должен иметь файл-оглавление `00-README.md`**, который отображается первым (GitHub сортирует файлы по алфавиту, `00-` гарантирует первое место).

### Когда создавать

- **При создании нового гиста** с 2+ файлами — сразу добавлять `00-README.md`
- **При добавлении файлов** в существующий гист — обновить оглавление

### Формат `00-README.md`

```markdown
# Название гиста

Краткое описание (1-2 предложения).

## Содержимое

- **file-one.md** — Краткое описание файла
- **file-two.md** — Краткое описание файла
```

### Как добавить

```bash
# При создании гиста — первым файлом
python3 ~/.claude/scripts/gist_create.py "00-README.md" "CONTENT" -d "Описание"
# Потом добавить остальные файлы через --add

# В существующий гист
python3 ~/.claude/scripts/gist_update.py GIST_ID --add 00-README.md "контент"
```

### Важно

- Имя файла **всегда** `00-README.md` (не `README.md` — он окажется после файлов на цифры)
- При добавлении/удалении файлов в гисте — **обновить оглавление**

---

## Режим конспектирования

Для длинных сессий (конспекты лекций, заметки) используй локальный файл:

1. **Храни файл локально:** `.tmp/gist-notes/имя-файла.md`
2. **Редактируй через Edit** — не пиши весь контент в команду
3. **После каждой правки — сразу синхронизируй в гист:**
   ```bash
   cat .tmp/gist-notes/file.md | python3 ~/.claude/scripts/gist_update.py GIST_ID file.md -
   ```

Это экономит контекст и гарантирует, что ничего не потеряется.