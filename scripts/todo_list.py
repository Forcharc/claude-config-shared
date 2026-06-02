#!/usr/bin/env python3
"""Показать TODO список

Использование:
    python3 todo_list.py [list_name]

Примеры:
    python3 todo_list.py           # показать inbox
    python3 todo_list.py work      # показать work
    python3 todo_list.py --all     # показать все списки
"""
import sys
import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from todo_api import get_lists, print_link


def show_list(list_name: str, content: str):
    """Показать один список"""
    print(f"## {list_name}\n")
    num = 1
    for line in content.split("\n"):
        if line.startswith("- [ ]"):
            print(f"{num}. ☐ {line[6:]}")
            num += 1
        elif line.startswith("- [x]"):
            print(f"   ✓ {line[6:]} (выполнено)")


def show_names_only(lists: dict):
    """Показать только названия списков"""
    print("Доступные списки:")
    for name in lists:
        print(f"  - {name}")


def main():
    list_name = sys.argv[1] if len(sys.argv) > 1 else "inbox"
    lists = get_lists()

    if list_name == "--names":
        show_names_only(lists)
    elif list_name == "--all":
        for name, content in lists.items():
            show_list(name, content)
            print()
    elif list_name in lists:
        show_list(list_name, lists[list_name])
    else:
        print(f"❌ Список '{list_name}' не найден")
        show_names_only(lists)

    print()
    print_link()


if __name__ == "__main__":
    main()
