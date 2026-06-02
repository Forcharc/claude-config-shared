---
name: commit
description: "Git commit: stage, review, format message, push"
---

# Git Commit

Закоммить текущие изменения. Без подтверждения — сразу делай.

## Шаги:

1. `git log --oneline -5` и `git status` — параллельно. Если нет изменений (ни modified, ни untracked) — сообщи и выйди.

2. Если ничего не застейджено — застейдж все изменённые и новые файлы.
   Не стейджи файлы с секретами (.env, credentials, ключи API).

3. **Атомарность:** если изменения затрагивают несколько несвязанных вещей — разбей на отдельные коммиты. Каждый коммит = одна логическая единица.

4. Определи формат по истории:
   - Тикеты (PROJ-XXXXX, TICKET-XXXXX и т.д.) → `ТИКЕТ: описание` (на русском)
   - Без тикетов → `Краткое описание` (на языке истории коммитов)

5. Сгенерируй commit message:
   - **Title** (до 50 символов): что сделано. На английском — imperative mood ("Add", не "Added").
   - **Body** (опционально): ПОЧЕМУ сделано, какую проблему решает, контекст. Не пересказывай diff. Для тривиальных изменений body не нужен.
   - **Маскировка символов** — применяй группу α из `/remind-text-style` к title и body: никаких backticks вокруг имён функций/файлов (пиши `handleAuth()` как handleAuth()), никакого длинного тире (— → -), никаких умных кавычек, никаких →. Стиль body — свободный (можно подробно объяснять "почему"), правила «короче, без преамбул» к коммитам не применяются.

6. Выполни коммит. Покажи хэш и title.

7. **Ревью:** вычисли sessionId через ancestor процесса (надёжно в форках и после compaction - `ls -t *.jsonl` для этого не годится):
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
   Запусти `/review` на свежий HEAD, передав `sessionId=<UUID>` в промт review-orchestrator. Фиксы становятся отдельными коммитами, после каждого - новый `/review` на новом HEAD (тот же sessionId). Цикл сходится когда ревью не находит FIX (только DEBT или clean).

8. **Push:**
   - Определи, в worktree ли мы: `git rev-parse --absolute-git-dir`, case-match на `*/.git/worktrees/*`. Если матч — мы в worktree.
   - **В worktree** — НЕ push. Worktree-ветка merge'нется в main вызвавшим (см. `/remind-workflow` → «Изоляция через worktree»).
   - **В основном дереве** — по дефолту НЕ push. Push регулируется проектным CLAUDE.md:
     - Прочитай `<repo>/.claude/CLAUDE.md` (и/или `<repo>/CLAUDE.md`).
     - Если там явно разрешён auto-push для текущей ветки (формулировки вроде «push в origin автоматически», «auto-push после clean review» и т. п.) — `git push`. Если нет upstream — пропусти молча. Если конфликт — сообщи пользователю.
     - Если явного разрешения нет — НЕ push, ничего не говори. Оркестратор сам решит и при необходимости спросит пользователя.

## Аргументы

`$ARGUMENTS` парсится так:
- Если начинается с тикета (PROJ-12345, TICKET-678 и т.д.) — используй как тикет + остаток как title
- Если просто текст — используй как title
- Примеры:
  - `/commit` — автоматический title
  - `/commit fix auth bug` — title: "Fix auth bug"
  - `/commit PROJ-12345` — тикет PROJ-12345, title автоматический
  - `/commit PROJ-12345 fix auth` — тикет PROJ-12345, title: "Fix auth"
