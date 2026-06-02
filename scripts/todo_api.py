"""Общие функции для работы с Gist API"""
import urllib.request
import json
from todo_config import TOKEN, GIST_ID, API_URL, GIST_URL, require


def get_gist():
    """Получить данные gist"""
    require("GITHUB_GIST_TOKEN", "GITHUB_TODO_GIST_ID")
    req = urllib.request.Request(
        API_URL,
        headers={"Authorization": f"token {TOKEN}"}
    )
    with urllib.request.urlopen(req) as resp:
        return json.loads(resp.read())


def update_gist(files_update: dict):
    """Обновить gist. files_update = {"filename": {"content": "..."}} или {"filename": None} для удаления"""
    require("GITHUB_GIST_TOKEN", "GITHUB_TODO_GIST_ID")
    data = json.dumps({"files": files_update}).encode()
    req = urllib.request.Request(
        API_URL,
        data=data,
        headers={
            "Authorization": f"token {TOKEN}",
            "Content-Type": "application/json"
        },
        method="PATCH"
    )
    with urllib.request.urlopen(req) as resp:
        return json.loads(resp.read())


def get_lists():
    """Получить все списки"""
    d = get_gist()
    files = d.get("files", {})
    return {
        f.replace("todo-", "").replace(".md", ""): files[f].get("content", "")
        for f in files if f.startswith("todo-")
    }


def get_list_content(list_name: str):
    """Получить содержимое списка"""
    lists = get_lists()
    return lists.get(list_name)


def print_link():
    """Вывести ссылку на gist"""
    print(f"🔗 {GIST_URL}")
