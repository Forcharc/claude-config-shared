"""Конфигурация для TODO/Gist скриптов.

Токен и идентификаторы берутся ТОЛЬКО из переменных окружения — в коде
секретов нет. Настрой один раз в ~/.zshrc (или ~/.bashrc):

    export GITHUB_GIST_TOKEN=ghp_xxx        # токен с scope "gist"
    export GITHUB_TODO_GIST_ID=xxx          # id gist, где хранятся todo-списки
    export GITHUB_USER=your-github-username # github-логин (для ссылок)

Токен создаётся здесь: https://github.com/settings/tokens
(Fine-grained или classic, достаточно одного scope: gist.)

GITHUB_TODO_GIST_ID — id любого gist (создай пустой на https://gist.github.com),
todo-скрипты будут держать списки в нём.
"""
import os
import sys

TOKEN = os.environ.get("GITHUB_GIST_TOKEN", "")
GIST_ID = os.environ.get("GITHUB_TODO_GIST_ID", "")
GITHUB_USER = os.environ.get("GITHUB_USER", "")
API_URL = f"https://api.github.com/gists/{GIST_ID}"
GIST_URL = f"https://gist.github.com/{GITHUB_USER}/{GIST_ID}"


def require(*names: str) -> None:
    """Fail-fast с понятной подсказкой, если нужные переменные окружения не заданы.

    Вызывать в начале main() каждого скрипта, передав имена нужных переменных.
    """
    hints = {
        "GITHUB_GIST_TOKEN": "export GITHUB_GIST_TOKEN=ghp_xxx   # scope: gist",
        "GITHUB_TODO_GIST_ID": "export GITHUB_TODO_GIST_ID=xxx   # id gist для todo",
        "GITHUB_USER": "export GITHUB_USER=your-github-username",
    }
    missing = [n for n in names if not os.environ.get(n)]
    if missing:
        sys.stderr.write(
            "Не заданы переменные окружения: " + ", ".join(missing) + "\n\n"
            "Добавь в ~/.zshrc и перезапусти шелл:\n"
            + "".join(f"    {hints.get(n, 'export ' + n + '=...')}\n" for n in missing)
            + "\nТокен создаётся тут: https://github.com/settings/tokens (scope: gist)\n"
        )
        sys.exit(1)
