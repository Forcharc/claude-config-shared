#!/usr/bin/env python3
"""Отметить задачу выполненной

Использование:
    python3 todo_done.py <list_name> <query>

query может быть:
    - номер задачи (1, 2, 3...)
    - несколько номеров через запятую (1,3,5) — обрабатываются за один проход
    - часть текста задачи
    - "all" или "все" — отметить все

Примеры:
    python3 todo_done.py inbox 1
    python3 todo_done.py inbox 1,3,5
    python3 todo_done.py inbox "молоко"
    python3 todo_done.py work all
"""
import sys
import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from todo_api import get_gist, update_gist, print_link


def main():
    if len(sys.argv) < 3:
        print("Использование: python3 todo_done.py <list_name> <query>")
        sys.exit(1)

    list_name = sys.argv[1]
    query = " ".join(sys.argv[2:])

    # Получить текущий gist
    d = get_gist()
    files = d.get("files", {})
    target = f"todo-{list_name}.md"

    if target not in files:
        print(f"❌ Список '{list_name}' не найден")
        sys.exit(1)

    content = files[target]["content"]
    lines = content.split("\n")
    found = False
    msg = ""

    # Проверяем, является ли query списком номеров (1,3,5)
    def is_number_list(s):
        return all(p.strip().isdigit() for p in s.split(",") if p.strip())

    if query.lower() in ("все", "all"):
        new_lines = [line.replace("- [ ]", "- [x]") for line in lines]
        found = any("- [ ]" in line for line in lines)
        msg = "Все задачи отмечены"
    elif query.isdigit() or ("," in query and is_number_list(query)):
        # Один номер или несколько через запятую
        nums = set(int(p.strip()) for p in query.split(",") if p.strip())
        count = 0
        new_lines = []
        done_tasks = []
        for line in lines:
            if line.startswith("- [ ]"):
                count += 1
                if count in nums:
                    new_lines.append(line.replace("- [ ]", "- [x]"))
                    found = True
                    done_tasks.append(f"#{count}: {line[6:]}")
                else:
                    new_lines.append(line)
            else:
                new_lines.append(line)
        if len(done_tasks) == 1:
            msg = f"Задача {done_tasks[0]} выполнена"
        else:
            msg = f"Выполнено {len(done_tasks)} задач:\n" + "\n".join(f"  ✓ {t}" for t in done_tasks)
    else:
        new_lines = []
        for line in lines:
            if line.startswith("- [ ]") and query.lower() in line.lower() and not found:
                new_lines.append(line.replace("- [ ]", "- [x]"))
                found = True
                msg = f"Выполнено: {line[6:]}"
            else:
                new_lines.append(line)

    if not found:
        print(f"❌ Задача не найдена: {query}")
        sys.exit(1)

    new_content = "\n".join(new_lines)
    update_gist({target: {"content": new_content}})

    print(f"✓ {msg}")
    print_link()


if __name__ == "__main__":
    main()
