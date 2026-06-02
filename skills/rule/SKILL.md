---
name: rule
description: "Add, edit, or remove rules in CLAUDE.md"
---

# RULE — управление правилами в ~/.claude/CLAUDE.md

## Аргументы
- `$ARGUMENTS` — что сделать с правилами

## Примеры
```
/rule покажи
/rule добавь правило про X
/rule измени секцию Y
/rule удали правило Z
```

## Алгоритм

1. ~/.claude/CLAUDE.md уже в контексте. Если нужно перечитать — используй Read tool
2. Предложи изменение и спроси подтверждение
3. После подтверждения — редактируй через Edit tool
