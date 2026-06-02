#!/usr/bin/env python3
"""Обновить существующий Gist

Использование:
    python3 gist_update.py <gist_id> <filename> <content>
    python3 gist_update.py <gist_id> <filename> -              # из stdin
    python3 gist_update.py <gist_id> --add <filename> <content>  # добавить файл
    python3 gist_update.py <gist_id> --delete <filename>         # удалить файл
    python3 gist_update.py <gist_id> --description "новое описание"

Примеры:
    python3 gist_update.py abc123 notes.md "# Новый контент"
    python3 gist_update.py abc123 --add script.py "print('hi')"
    python3 gist_update.py abc123 --delete old-file.md
    python3 gist_update.py abc123 --description "Обновлённое описание"
"""
import sys
import os
import json
import urllib.request
import argparse

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from todo_config import TOKEN, require


def update_gist(gist_id: str, files: dict = None, description: str = None):
    """Обновить gist"""
    require("GITHUB_GIST_TOKEN")
    payload = {}
    if files:
        payload["files"] = files
    if description is not None:
        payload["description"] = description

    data = json.dumps(payload).encode()

    req = urllib.request.Request(
        f"https://api.github.com/gists/{gist_id}",
        data=data,
        headers={
            "Authorization": f"token {TOKEN}",
            "Content-Type": "application/json"
        },
        method="PATCH"
    )

    with urllib.request.urlopen(req) as resp:
        return json.loads(resp.read())


def get_gist(gist_id: str):
    """Получить информацию о gist"""
    require("GITHUB_GIST_TOKEN")
    req = urllib.request.Request(
        f"https://api.github.com/gists/{gist_id}",
        headers={"Authorization": f"token {TOKEN}"}
    )
    with urllib.request.urlopen(req) as resp:
        return json.loads(resp.read())


def main():
    parser = argparse.ArgumentParser(description="Обновить Gist")
    parser.add_argument("gist_id", help="ID гиста (или URL)")
    parser.add_argument("filename", nargs="?", help="Имя файла для обновления")
    parser.add_argument("content", nargs="?", help="Новое содержимое или '-' для stdin")
    parser.add_argument("--add", nargs=2, metavar=("FILE", "CONTENT"), help="Добавить файл")
    parser.add_argument("--delete", metavar="FILE", help="Удалить файл")
    parser.add_argument("--description", "-d", help="Изменить описание")

    args = parser.parse_args()

    # Извлечь gist_id из URL если нужно
    gist_id = args.gist_id
    if "gist.github.com" in gist_id:
        gist_id = gist_id.rstrip("/").split("/")[-1]

    files = {}

    # Обновить файл
    if args.filename and args.content:
        content = sys.stdin.read() if args.content == "-" else args.content
        files[args.filename] = {"content": content}

    # Добавить файл
    if args.add:
        filename, content = args.add
        content = sys.stdin.read() if content == "-" else content
        files[filename] = {"content": content}

    # Удалить файл
    if args.delete:
        files[args.delete] = None

    # Выполнить обновление
    if files or args.description:
        result = update_gist(gist_id, files if files else None, args.description)
        print(f"✓ Gist обновлён")
        print(f"🔗 {result['html_url']}")

        if files:
            for f in files:
                if files[f] is None:
                    print(f"   🗑️  Удалён: {f}")
                else:
                    print(f"   📝 Обновлён: {f}")
    else:
        # Просто показать информацию
        g = get_gist(gist_id)
        print(f"## {g['description'] or '(без описания)'}")
        print(f"🔗 {g['html_url']}")
        print(f"Файлы:")
        for f in g["files"]:
            print(f"   - {f}")


if __name__ == "__main__":
    main()
