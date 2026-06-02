#!/usr/bin/env python3
"""Создать Gist из локального файла

Использование:
    python3 gist_from_file.py <path> [--public] [--description "..."] [--name "custom_name.md"]

Примеры:
    python3 gist_from_file.py ./notes.md
    python3 gist_from_file.py ./script.py --public --description "Мой скрипт"
    python3 gist_from_file.py ./doc.md --name "readme.md"
"""
import sys
import os
import argparse

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gist_create import create_gist


def main():
    parser = argparse.ArgumentParser(description="Создать Gist из локального файла")
    parser.add_argument("path", help="Путь к файлу")
    parser.add_argument("--public", action="store_true", help="Сделать публичным")
    parser.add_argument("--description", "-d", default="", help="Описание gist")
    parser.add_argument("--name", "-n", help="Имя файла в gist (по умолчанию как у исходного)")

    args = parser.parse_args()

    # Проверить файл
    if not os.path.exists(args.path):
        print(f"❌ Файл не найден: {args.path}")
        sys.exit(1)

    # Прочитать файл
    with open(args.path, "r", encoding="utf-8") as f:
        content = f.read()

    # Имя файла
    filename = args.name or os.path.basename(args.path)

    # Создать gist
    result = create_gist(
        filename=filename,
        content=content,
        description=args.description,
        public=args.public
    )

    visibility = "🌍 Public" if result["public"] else "🔒 Secret"
    print(f"✓ Gist создан из {args.path} ({visibility})")
    print(f"🔗 {result['url']}")
    print(f"📄 Raw: {result['raw_url']}")


if __name__ == "__main__":
    main()
