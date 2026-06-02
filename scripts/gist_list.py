#!/usr/bin/env python3
"""Показать список своих Gist'ов

Использование:
    python3 gist_list.py [--limit N]

Примеры:
    python3 gist_list.py
    python3 gist_list.py --limit 5
"""
import sys
import os
import json
import urllib.request
import argparse

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from todo_config import TOKEN, require


def list_gists(limit: int = 10):
    """Получить список gist'ов"""
    require("GITHUB_GIST_TOKEN")
    req = urllib.request.Request(
        f"https://api.github.com/gists?per_page={limit}",
        headers={"Authorization": f"token {TOKEN}"}
    )

    with urllib.request.urlopen(req) as resp:
        return json.loads(resp.read())


def main():
    parser = argparse.ArgumentParser(description="Показать список Gist'ов")
    parser.add_argument("--limit", "-l", type=int, default=10, help="Количество (по умолчанию 10)")

    args = parser.parse_args()

    gists = list_gists(args.limit)

    print(f"## Твои Gist'ы ({len(gists)})\n")

    for g in gists:
        visibility = "🌍" if g["public"] else "🔒"
        files = list(g["files"].keys())
        files_str = ", ".join(files[:3])
        if len(files) > 3:
            files_str += f" (+{len(files)-3})"

        desc = g["description"] or "(без описания)"
        print(f"{visibility} **{files[0]}** — {desc}")
        print(f"   Файлы: {files_str}")
        print(f"   🔗 {g['html_url']}")
        print()


if __name__ == "__main__":
    main()
