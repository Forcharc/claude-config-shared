#!/usr/bin/env python3
"""Добавить задачу в TODO список

Использование:
    python3 todo_add.py <list_name> <task>

Примеры:
    python3 todo_add.py inbox "Купить молоко"
    python3 todo_add.py work "Сделать ревью"
"""
import sys
import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from todo_api import get_gist, update_gist, print_link


def main():
    if len(sys.argv) < 3:
        print("Использование: python3 todo_add.py <list_name> <task>")
        sys.exit(1)

    list_name = sys.argv[1]
    task = " ".join(sys.argv[2:])

    # Получить текущий gist
    d = get_gist()
    files = d.get("files", {})
    target = f"todo-{list_name}.md"

    if target in files:
        content = files[target]["content"].rstrip("\n")
        new_content = content + f"\n- [ ] {task}\n"
    else:
        new_content = f"# {list_name}\n\n- [ ] {task}\n"

    # Обновить
    update_gist({target: {"content": new_content}})

    print(f"✓ Добавлено в {list_name}: {task}")
    print_link()


if __name__ == "__main__":
    main()
