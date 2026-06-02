#!/usr/bin/env python3
"""Просмотреть содержимое Gist'а

Использование:
    python3 gist_view.py <gist_id>                    # показать все файлы
    python3 gist_view.py <gist_id> <filename>         # конкретный файл
    python3 gist_view.py <gist_id> --raw              # без форматирования
    python3 gist_view.py <gist_id> <filename> --raw   # конкретный файл без форматирования

Примеры:
    python3 gist_view.py abc123
    python3 gist_view.py abc123 notes.md
    python3 gist_view.py abc123 script.py --raw
"""
import sys
import os
import json
import urllib.request
import argparse

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from todo_config import TOKEN, require


def get_gist(gist_id: str) -> dict:
    """Получить гист по ID"""
    require("GITHUB_GIST_TOKEN")
    req = urllib.request.Request(
        f"https://api.github.com/gists/{gist_id}",
        headers={
            "Authorization": f"token {TOKEN}",
            "Accept": "application/vnd.github+json"
        }
    )

    with urllib.request.urlopen(req) as resp:
        return json.loads(resp.read())


def main():
    parser = argparse.ArgumentParser(description="Просмотреть содержимое Gist'а")
    parser.add_argument("gist_id", help="ID гиста")
    parser.add_argument("filename", nargs="?", help="Имя файла (опционально)")
    parser.add_argument("--raw", "-r", action="store_true", help="Без форматирования")

    args = parser.parse_args()

    try:
        gist = get_gist(args.gist_id)
    except urllib.error.HTTPError as e:
        print(f"❌ Ошибка: {e.code} — гист не найден или нет доступа")
        sys.exit(1)

    files = gist["files"]

    if args.filename:
        # Конкретный файл
        if args.filename not in files:
            print(f"❌ Файл '{args.filename}' не найден в гисте")
            print(f"   Доступные файлы: {', '.join(files.keys())}")
            sys.exit(1)

        content = files[args.filename]["content"]
        if args.raw:
            print(content)
        else:
            print(f"## {args.filename}\n")
            print(content)
    else:
        # Все файлы
        if args.raw:
            for name, data in files.items():
                print(f"=== {name} ===")
                print(data["content"])
                print()
        else:
            desc = gist.get("description") or "(без описания)"
            print(f"## {desc}")
            print(f"🔗 {gist['html_url']}")
            print(f"Файлы: {', '.join(files.keys())}\n")

            for name, data in files.items():
                print(f"### {name}")
                print("```")
                # Показываем первые 50 строк, если файл большой
                lines = data["content"].split("\n")
                if len(lines) > 50:
                    print("\n".join(lines[:50]))
                    print(f"\n... (+{len(lines) - 50} строк)")
                else:
                    print(data["content"])
                print("```\n")


if __name__ == "__main__":
    main()
