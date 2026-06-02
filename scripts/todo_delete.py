#!/usr/bin/env python3
"""Удалить задачу или список

Использование:
    python3 todo_delete.py <list_name> <query>     # удалить задачу
    python3 todo_delete.py --list <list_name>      # удалить весь список

query может быть:
    - номер задачи (1, 2, 3...)
    - несколько номеров через запятую (1,3,5) — удаляются за один проход
    - часть текста задачи
    - "done" — удалить все выполненные

Примеры:
    python3 todo_delete.py inbox 1
    python3 todo_delete.py inbox 1,3,5
    python3 todo_delete.py inbox "молоко"
    python3 todo_delete.py inbox done
    python3 todo_delete.py --list work
"""
import sys
import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from todo_api import get_gist, update_gist, print_link


def delete_list(list_name: str):
    """Удалить весь список"""
    target = f"todo-{list_name}.md"
    update_gist({target: None})
    print(f"✓ Список '{list_name}' удалён")
    print_link()


def delete_task(list_name: str, query: str):
    """Удалить задачу из списка"""
    d = get_gist()
    files = d.get("files", {})
    target = f"todo-{list_name}.md"

    if target not in files:
        print(f"❌ Список '{list_name}' не найден")
        sys.exit(1)

    content = files[target]["content"]
    lines = content.split("\n")
    new_lines = []
    found = False
    msg = ""

    # Проверяем, является ли query списком номеров (1,3,5)
    def is_number_list(s):
        return all(p.strip().isdigit() for p in s.split(",") if p.strip())

    if query.lower() == "done":
        # Удалить все выполненные
        for line in lines:
            if line.startswith("- [x]"):
                found = True
            else:
                new_lines.append(line)
        msg = "Выполненные задачи удалены"
    elif query.isdigit() or ("," in query and is_number_list(query)):
        # Один номер или несколько через запятую
        nums = set(int(p.strip()) for p in query.split(",") if p.strip())
        count = 0
        deleted_tasks = []
        for line in lines:
            if line.startswith("- [ ]"):
                count += 1
                if count in nums:
                    found = True
                    deleted_tasks.append(f"#{count}: {line[6:]}")
                else:
                    new_lines.append(line)
            else:
                new_lines.append(line)
        if len(deleted_tasks) == 1:
            msg = f"Удалено: {deleted_tasks[0]}"
        else:
            msg = f"Удалено {len(deleted_tasks)} задач:\n" + "\n".join(f"  ✗ {t}" for t in deleted_tasks)
    else:
        for line in lines:
            if (line.startswith("- [ ]") or line.startswith("- [x]")) and query.lower() in line.lower() and not found:
                found = True
                msg = f"Удалено: {line[6:]}"
            else:
                new_lines.append(line)

    if not found:
        print(f"❌ Задача не найдена: {query}")
        sys.exit(1)

    new_content = "\n".join(new_lines)
    update_gist({target: {"content": new_content}})

    print(f"✓ {msg}")
    print_link()


def main():
    if len(sys.argv) < 3:
        print("Использование:")
        print("  python3 todo_delete.py <list_name> <query>")
        print("  python3 todo_delete.py --list <list_name>")
        sys.exit(1)

    if sys.argv[1] == "--list":
        delete_list(sys.argv[2])
    else:
        delete_task(sys.argv[1], " ".join(sys.argv[2:]))


if __name__ == "__main__":
    main()
