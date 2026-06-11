#!/bin/bash
# Каноника алгоритма вычисления sessionId; используется из /techdebt шаг 3, /finalize шаг 1, /commit "Подпись коммита".
# Идём вверх по дереву процессов до Claude-процесса с флагом --resume <UUID>.
# Надёжно в форках и после compaction; ls -t *.jsonl НЕ годится (вернёт parent в форках).
# Пусто на выходе = сессия запущена без --resume; fallback — греп уникальной
# строки диалога по ~/.claude/projects/<slug>/*.jsonl (см. /commit "Подпись коммита").
pid=$$
while [ "$pid" != "1" ] && [ -n "$pid" ]; do
  cmd=$(ps -p "$pid" -o command= 2>/dev/null)
  if echo "$cmd" | grep -qE -- '--resume [a-f0-9-]+'; then
    echo "$cmd" | grep -oE -- '--resume [a-f0-9-]+' | awk '{print $2}'
    break
  fi
  pid=$(ps -p "$pid" -o ppid= 2>/dev/null | tr -d ' ')
done
