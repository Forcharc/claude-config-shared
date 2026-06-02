#!/bin/bash
# Claude Code rich statusLine — single-line, compact.

input=$(cat)
now=$(date +%s)

# --- Parse all JSON fields in a single jq call ---
{
  read -r model
  read -r ctx_size
  read -r ctx_pct
  read -r session_cost
  read -r session_ms
  read -r lines_added
  read -r lines_removed
  read -r rl_7d
  read -r rl_5h
  read -r rl_7d_reset
  read -r rl_5h_reset
  read -r cwd
} < <(jq -r '
  .model.display_name // "?",
  .context_window.context_window_size // 200000,
  .context_window.used_percentage // 0,
  .cost.total_cost_usd // 0,
  .cost.total_duration_ms // 0,
  .cost.total_lines_added // 0,
  .cost.total_lines_removed // 0,
  .rate_limits.seven_day.used_percentage // "",
  .rate_limits.five_hour.used_percentage // "",
  .rate_limits.seven_day.resets_at // "",
  .rate_limits.five_hour.resets_at // "",
  .workspace.current_dir // .cwd // ""
' <<< "$input")

# --- ANSI colors ---
R='\033[0m'
DIM='\033[2m'
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[34m'
MAGENTA='\033[35m'
CYAN='\033[36m'
GRAY='\033[90m'

# --- Monthly cost (async cache via ccusage) ---
CACHE_FILE="$HOME/.claude/.monthly-cost.cache"
LOCK_DIR="$HOME/.claude/.monthly-cost.lock.d"
CACHE_AGE_SEC=600
LOCK_TTL_SEC=60

cache_mtime=0
[ -f "$CACHE_FILE" ] && cache_mtime=$(stat -f %m "$CACHE_FILE" 2>/dev/null || echo 0)
age=$((now - cache_mtime))

# Reap stale lock (e.g., ccusage killed mid-run)
if [ -d "$LOCK_DIR" ]; then
  lock_mtime=$(stat -f %m "$LOCK_DIR" 2>/dev/null || echo 0)
  (( now - lock_mtime > LOCK_TTL_SEC )) && rmdir "$LOCK_DIR" 2>/dev/null
fi

# Atomic lock: mkdir wins exactly once even under race
if (( age > CACHE_AGE_SEC )) && mkdir "$LOCK_DIR" 2>/dev/null; then
  (
    MONTH=$(date +%Y-%m)
    npx -y ccusage@latest monthly --json --offline 2>/dev/null \
      | jq -r --arg m "$MONTH" '.monthly[] | select(.month == $m) | .totalCost' \
      > "$CACHE_FILE.tmp" 2>/dev/null \
      && mv "$CACHE_FILE.tmp" "$CACHE_FILE"
    rmdir "$LOCK_DIR" 2>/dev/null
  ) </dev/null >/dev/null 2>&1 &
  disown 2>/dev/null || true
fi

monthly_cost=""
if [ -f "$CACHE_FILE" ] && [ -s "$CACHE_FILE" ]; then
  read -r mc < "$CACHE_FILE" 2>/dev/null
  if [ -n "$mc" ]; then
    # Round to integer, but preserve cents if < $1 so "$0.49" doesn't become "$0"
    monthly_cost=$(printf "%.0f" "$mc" 2>/dev/null)
    if [ "$monthly_cost" = "0" ] && [ "$mc" != "0" ]; then
      monthly_cost=$(printf "%.2f" "$mc" 2>/dev/null)
    fi
  fi
fi

# --- Compact duration: "30s", "45m", "5h", "2d" ---
fmt_duration() {
  local sec=$1
  if [ -z "$sec" ] || (( sec <= 0 )); then
    echo "0s"
    return
  fi
  if   (( sec >= 86400 )); then echo "$((sec / 86400))d"
  elif (( sec >= 3600  )); then echo "$((sec / 3600))h"
  elif (( sec >= 60    )); then echo "$((sec / 60))m"
  else                          echo "${sec}s"
  fi
}

# Time remaining until reset. Returns empty if already past.
reset_in() {
  local target=$1
  [ -z "$target" ] && return
  local diff=$((target - now))
  (( diff <= 0 )) && return
  fmt_duration "$diff"
}

# --- Context progress bar ---
ctx_int=${ctx_pct%.*}
[ -z "$ctx_int" ] && ctx_int=0
filled=$((ctx_int / 10))
(( filled > 10 )) && filled=10
empty=$((10 - filled))
bar=""
i=0; while (( i < filled )); do bar="${bar}▓"; i=$((i+1)); done
i=0; while (( i < empty  )); do bar="${bar}░"; i=$((i+1)); done

if   (( ctx_int >= 80 )); then ctx_color="$RED"
elif (( ctx_int >= 50 )); then ctx_color="$YELLOW"
else                           ctx_color="$GREEN"
fi

# --- Model label: short form "O1M" / "S0.2M" / "H0.2M" ---
case "$model" in
  Opus*|opus*)   letter="O" ;;
  Sonnet*|sonnet*) letter="S" ;;
  Haiku*|haiku*)   letter="H" ;;
  *) letter="${model:0:1}" ;;
esac
case "$ctx_size" in
  1000000) ctx_short="1M" ;;
  200000)  ctx_short="0.2M" ;;
  *)
    if (( ctx_size >= 1000000 )); then
      ctx_short="$((ctx_size / 1000000))M"
    elif (( ctx_size >= 1000 )); then
      ctx_short="$((ctx_size / 1000))k"
    else
      ctx_short="${ctx_size}"
    fi
    ;;
esac
model_label="${letter}${ctx_short}"

# --- Папка: basename git toplevel (worktree root), fallback — basename cwd ---
git_info=""
if [ -n "$cwd" ] && [ -d "$cwd" ]; then
  toplevel=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)
  if [ -n "$toplevel" ]; then
    folder=$(basename "$toplevel")
  else
    folder=$(basename "$cwd")
  fi
  [ -n "$folder" ] && git_info="${MAGENTA}📁 ${folder}${R}"
fi

# --- Session edits ---
edits=""
if [ "$lines_added" != "0" ] || [ "$lines_removed" != "0" ]; then
  edits="${GREEN}+${lines_added}${R}/${RED}-${lines_removed}${R}"
fi

# --- Rate limits with reset countdowns (rounded to int) ---
rl=""
if [ -n "$rl_5h" ] && [ -n "$rl_7d" ]; then
  r7=$(reset_in "$rl_7d_reset")
  r5=$(reset_in "$rl_5h_reset")
  rl_7d_int=$(printf "%.0f" "$rl_7d" 2>/dev/null)
  rl_5h_int=$(printf "%.0f" "$rl_5h" 2>/dev/null)
  [ -z "$rl_7d_int" ] && rl_7d_int=0
  [ -z "$rl_5h_int" ] && rl_5h_int=0
  if   (( rl_7d_int >= 80 )); then rl_color="$RED"
  elif (( rl_7d_int >= 50 )); then rl_color="$YELLOW"
  else                             rl_color="$GREEN"
  fi
  r5_str=""; [ -n "$r5" ] && r5_str="(${r5})"
  r7_str=""; [ -n "$r7" ] && r7_str="(${r7})"
  rl="${rl_color}📈 ${rl_5h_int}%${r5_str}/${rl_7d_int}%${r7_str}${R}"
fi

# --- Spend: session(dur) / monthly(day-of-month) ---
sess_fmt=""
sess_dur=""
if [ "$session_cost" != "0" ] && [ -n "$session_cost" ]; then
  sess_fmt=$(printf "%.2f" "$session_cost" 2>/dev/null)
  sess_sec=$(( ${session_ms%.*} / 1000 ))
  sess_dur=$(fmt_duration "$sess_sec")
fi
month_day=$(date +%-d)
spend=""
if [ -n "$sess_fmt" ] && [ -n "$monthly_cost" ]; then
  spend="${YELLOW}💵 \$${sess_fmt}(${sess_dur})/\$${monthly_cost}(${month_day}d)${R}"
elif [ -n "$monthly_cost" ]; then
  spend="${YELLOW}💵 \$${monthly_cost}(${month_day}d)${R}"
elif [ -n "$sess_fmt" ]; then
  spend="${YELLOW}💵 \$${sess_fmt}(${sess_dur})${R}"
elif [ ! -f "$CACHE_FILE" ]; then
  spend="${DIM}💵 …${R}"
fi

# --- Build single-line output ---
SEP="${GRAY} │ ${R}"

# --- TEMPORARY: spend = только месячный (без session). Вернуть — снять override. ---
if [ -n "$monthly_cost" ]; then
  spend="${YELLOW}💵 \$${monthly_cost}(${month_day}d)${R}"
elif [ ! -f "$CACHE_FILE" ]; then
  spend="${DIM}💵 …${R}"
else
  spend=""
fi

out="${CYAN}${model_label}${R}"
out="${out}${SEP}${ctx_color}${bar} ${ctx_int}%${R}"
[ -n "$git_info" ] && out="${out}${SEP}${git_info}"
[ -n "$spend" ]    && out="${out}${SEP}${spend}"
[ -n "$rl" ]       && out="${out}${SEP}${rl}"
[ -n "$edits" ]    && out="${out}${SEP}📝 ${edits}"

printf "%b" "$out"
