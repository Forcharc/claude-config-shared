#!/usr/bin/env python3
"""Создать новый Gist

Использование:
    python3 gist_create.py <filename> <content> [--public] [--description "..."]

Или через stdin:
    echo "content" | python3 gist_create.py <filename> - [--public]

Примеры:
    python3 gist_create.py notes.md "# Заметки" --description "Мои заметки"
    python3 gist_create.py script.py "print('hello')" --public
    cat file.md | python3 gist_create.py doc.md -
"""
import sys
import os
import json
import urllib.request
import argparse

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from todo_config import TOKEN, GITHUB_USER, require


def create_gist(filename: str, content: str, description: str = "", public: bool = False):
    """Создать новый gist"""
    require("GITHUB_GIST_TOKEN")
    data = json.dumps({
        "description": description,
        "public": public,
        "files": {
            filename: {"content": content}
        }
    }).encode()

    req = urllib.request.Request(
        "https://api.github.com/gists",
        data=data,
        headers={
            "Authorization": f"token {TOKEN}",
            "Content-Type": "application/json"
        },
        method="POST"
    )

    with urllib.request.urlopen(req) as resp:
        d = json.loads(resp.read())
        return {
            "id": d["id"],
            "url": d["html_url"],
            "raw_url": d["files"][filename]["raw_url"],
            "public": d["public"]
        }


def main():
    parser = argparse.ArgumentParser(description="Создать новый Gist")
    parser.add_argument("filename", help="Имя файла (например notes.md)")
    parser.add_argument("content", help="Содержимое файла или '-' для stdin")
    parser.add_argument("--public", action="store_true", help="Сделать публичным (по умолчанию secret)")
    parser.add_argument("--description", "-d", default="", help="Описание gist")

    args = parser.parse_args()

    # Получить контент
    if args.content == "-":
        content = sys.stdin.read()
    else:
        content = args.content

    # Создать gist
    result = create_gist(
        filename=args.filename,
        content=content,
        description=args.description,
        public=args.public
    )

    visibility = "🌍 Public" if result["public"] else "🔒 Secret"
    print(f"✓ Gist создан ({visibility})")
    print(f"🔗 {result['url']}")
    print(f"📄 Raw: {result['raw_url']}")


if __name__ == "__main__":
    main()
