---
name: review
description: "Code review via parallel agents (logic, clean-code, efficiency, architecture, security, docs) — orchestrated by review-orchestrator"
---

# Code Review

**Обязателен после КАЖДОГО коммита, без исключений.** Даже для .md, конфигов, документации. Это исключение из общего правила «не делегировать тривиальное» — ревью работает на всё, что попало в git.

## Механика

Один вызов — вся работа внутри агента `review-orchestrator`:

```
Agent(review-orchestrator, prompt="head=HEAD repo=<абс-путь-cwd> sessionId=<UUID>. <короткий контекст задачи>")
```

**sessionId** — UUID текущей сессии вызывающего. Получить через ancestor процесса (надёжно в форках и после compaction — `ls -t *.jsonl` для этого не годится):
```bash
pid=$$
while [ "$pid" != "1" ] && [ -n "$pid" ]; do
  cmd=$(ps -p "$pid" -o command= 2>/dev/null)
  if echo "$cmd" | grep -qE -- '--resume [a-f0-9-]+'; then
    echo "$cmd" | grep -oE -- '--resume [a-f0-9-]+' | awk '{print $2}'
    break
  fi
  pid=$(ps -p "$pid" -o ppid= 2>/dev/null | tr -d ' ')
done
```
Передаётся чтобы DEBT-записи ссылались на сессию пользователя, а не на сессию sub-agent'а.

Агент сам:
1. Снимет diff и классифицирует коммит (языки, масштаб, файлы)
2. Параллельно спавнит `logic-reviewer` / `clean-code-reviewer` / `docs-reviewer` / `efficiency-reviewer` / `architecture-reviewer` / `security-reviewer` по правилам выбора
3. Верифицирует и дедуплицирует находки
4. FIX — закрывает через `implementer` агентов (параллельно где независимо), коммитит fix-коммит
5. DEBT — записывает в `docs/tech-debt/` (или `memory/tech-debt/` если `techdebt_location: local`)
6. Re-review на новый HEAD до сходимости
7. Возвращает короткий финальный отчёт (раундов, коммитов, FIX/DEBT/false-positives, статус clean/blocked)

## Что передать в промт

- **head** — по умолчанию `HEAD`; для ранее запушенных коммитов — конкретный ref
- **repo** — абсолютный путь к git-репо. Для текущего cwd — можно опустить, но в worktree / для `~/.claude/` всегда передавай явно
- **sessionId** — UUID текущей сессии (обязателен). Без него DEBT-записи получат UUID sub-agent'а и `/finalize` их не найдёт
- **Контекст задачи** — 1-2 строки: что за коммит, при какой задаче сделан. Нужен агенту для оценки релевантности находок
- **mode** (опционально) — `full` (default; FIX правятся через implementer'ов и коммитятся) или `analysis-only` (FIX только в отчёт, без правок и коммитов). Используй `analysis-only` когда ревьюишь чужой код (например, при `/review-mr`)

Примеры промта:
```
# Обычный коммит (full mode — default)
head=HEAD repo=/Users/foo/.claude sessionId=a1b2c3d4-e5f6-7890-abcd-ef1234567890
Коммит закрывает td-005: добавил предупреждение про sensitive-check в /techdebt и /techdebt-init скиллы.
```
```
# Ревью чужого МР (analysis-only — без правок и коммитов)
head=HEAD repo=/Users/foo/project mode=analysis-only sessionId=a1b2c3d4-e5f6-7890-abcd-ef1234567890
МР #42: рефакторинг auth модуля. Ревьюем чужой код, правки не делаем.
```

## После возврата

- Если `clean` → управление возвращается в вызвавший флоу (обычно `/commit` — он делает push)
- Если `blocked` → прочитай причину в отчёте агента, реши вручную

## Параллелизм с другими задачами

Пока review-orchestrator работает, можешь параллельно делать независимые операции (например, планировать следующий шаг). Но не стартуй ещё один коммит в тот же репо — review в процессе может делать fix-коммиты.

## Когда НЕ вызывать

- Если коммита ещё нет (working tree грязное) — сначала `/commit`
- Для черновиков вне git — ревью не применимо
