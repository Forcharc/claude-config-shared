#!/bin/bash
# Ожидание результатов продолженных агентов (обход бага Claude Code: ответ агента,
# продолженного через SendMessage, уходит в главную сессию, если распорядитель закончил ход;
# https://github.com/anthropics/claude-code/issues/81438).
# Использование: runner-wait.sh <T0> <agentId>[=<out-файл>] ...
#   T0 - число из `date +%s`, снятое ДО SendMessage.
#   agentId=out-файл - ждём непустой файл, записанный после T0 (mtime >= T0:
#   файл прошлого раунда за результат не считается); agentId без файла - ждём конец хода
#   агента в транскрипте (запись новее T0).
# Печатает статус каждого агента (`<agentId> <СТАТУС>`) и итоговую строку:
#   ALL_DONE | ATTENTION | TIMEOUT. Код выхода 0; 2 - ошибка запуска (usage или нет jq), сообщение в stderr.
# Переменные: TD - каталог транскриптов (для тестов), WAIT_SECONDS - потолок (540).
T0=$1; shift
[ -z "$T0" ] || [ $# -eq 0 ] && { echo "usage: runner-wait.sh <T0> <agentId>[=<out>] ..." >&2; exit 2; }
IDS=(); OUTS=()
for a in "$@"; do IDS+=("${a%%=*}"); case $a in *=*) OUTS+=("${a#*=}") ;; *) OUTS+=("") ;; esac; done
TD=${TD:-$HOME/.claude/projects/*/$CLAUDE_CODE_SESSION_ID/subagents}
command -v jq >/dev/null || { echo "jq not found: runner-wait.sh needs jq to read transcripts" >&2; exit 2; }
end=$((SECONDS+${WAIT_SECONDS:-540}))

# mtime файла: GNU (Linux) или BSD (macOS); GNU первым: на нём `stat -f` печатает статус ФС в stdout
mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1"; }

tr_of() { ls $TD/agent-${IDS[$1]}.jsonl 2>/dev/null | head -1; }

st0() {
  local t r ts ty sr api sub
  t=$(tr_of "$1"); [ -z "$t" ] && { echo NO_TRANSCRIPT; return; }
  [ "$(mtime "$t")" -gt "$T0" ] || { echo ALIVE; return; }
  # недописанная последняя строка: ждём 2 секунды, потом ERROR
  tail -n 1 "$t" | jq -e . >/dev/null 2>&1 || { sleep 2; tail -n 1 "$t" | jq -e . >/dev/null 2>&1 || { echo ERROR; return; }; }
  # последняя осмысленная запись среди последних 20 строк (attachment и прочее пропускаем)
  r=$(tail -n 20 "$t" | jq -Rr "fromjson? | select(.type==\"assistant\" or .type==\"user\" or .type==\"error\" or .isApiErrorMessage==true) | [((.timestamp // \"1970-01-01T00:00:00Z\")[0:19] + \"Z\" | fromdateiso8601), .type, (.message.stop_reason // \"-\"), (.isApiErrorMessage // false), (.subtype // \"-\")] | join(\" \")" 2>/dev/null | tail -n 1)
  read -r ts ty sr api sub <<< "$r"
  [ "${ts:-0}" -gt "$T0" ] || { echo ALIVE; return; }
  if [ "$api" = true ] || [ "$ty" = error ] || [[ "$sub" == *error* ]]; then echo ERROR
  elif [ "$ty" = assistant ] && [ "$sr" = end_turn ]; then echo ENDED_NO_FILE
  elif [ "$ty" = assistant ] && [ "$sr" != - ] && [ "$sr" != tool_use ]; then echo ERROR
  else echo ALIVE; fi
}

fresh() { [ -s "$1" ] && [ "$(mtime "$1")" -ge "$T0" ]; }

st() {
  local o=${OUTS[$1]} r
  if [ -n "$o" ]; then fresh "$o" && { echo DONE; return; }; fi
  r=$(st0 "$1")
  case $r in
    ENDED_NO_FILE|ERROR)
      if [ -n "$o" ]; then fresh "$o" && r=DONE   # файл мог появиться между проверками
      elif [ "$r" = ENDED_NO_FILE ]; then r=DONE; fi ;;  # без файла конец хода и есть результат
  esac
  echo "$r"
}

rep() { for i in "${!IDS[@]}"; do echo "${IDS[$i]} ${S[$i]}"; done; }

NT=()
while [ $SECONDS -lt $end ]; do
  S=(); bad=0; all=1
  for i in "${!IDS[@]}"; do
    S[$i]=$(st "$i")
    if [ "${S[$i]}" = NO_TRANSCRIPT ]; then
      [ -z "${NT[$i]}" ] && NT[$i]=$SECONDS
      [ $((SECONDS-NT[$i])) -ge 30 ] && S[$i]=NOT_FOUND
    else NT[$i]=; fi
    case ${S[$i]} in DONE) ;; ENDED_NO_FILE|ERROR|NOT_FOUND) bad=1; all=0 ;; *) all=0 ;; esac
  done
  [ $bad = 1 ] && { rep; echo ATTENTION; exit 0; }
  [ $all = 1 ] && { rep; echo ALL_DONE; exit 0; }
  sleep 3
done
echo TIMEOUT; rep
for i in "${!IDS[@]}"; do
  t=$(tr_of "$i")
  [ -n "$t" ] && echo "${IDS[$i]} age=$(( $(date +%s) - $(mtime "$t") ))s"
done
exit 0
