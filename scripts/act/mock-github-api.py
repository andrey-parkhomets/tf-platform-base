#!/usr/bin/env python3
"""Tiny stand-in for the GitHub REST endpoints the workflow's comment step uses.

Usage: mock-github-api.py <port> <state-file>

Serves issue comments (list / create / update) from memory, plus the permission lookup that
anthropics/claude-code-action does before it starts ("does the actor have write access?"; the answer is always
"write", because the local simulation has no real users) and writes them to <state-file> as JSON, so
simulate-pr.sh can assert on the exact comment the workflow would have posted. Every request is appended
to <state-file>.requests. Unknown endpoints answer 404 and are listed there too.
"""
import json
import re
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

port, state = int(sys.argv[1]), sys.argv[2]
comments = []


def save():
    with open(state, "w") as f:
        json.dump(comments, f)


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def reply(self, code, obj):
        data = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def handle_any(self, method):
        path = self.path.split("?")[0]
        path = re.sub(r"^/api/v3", "", path)
        with open(state + ".requests", "a") as f:
            f.write(f"{method} {path}\n")
        length = int(self.headers.get("content-length") or 0)
        body = json.loads(self.rfile.read(length) or b"{}") if length else {}

        if re.fullmatch(r"/repos/[^/]+/[^/]+/issues/\d+/comments", path):
            if method == "GET":
                return self.reply(200, comments)
            if method == "POST":
                c = {"id": len(comments) + 1, "body": body.get("body", ""),
                     "user": {"type": "Bot", "login": "github-actions[bot]"}}
                comments.append(c)
                save()
                return self.reply(201, c)
        m = re.fullmatch(r"/repos/[^/]+/[^/]+/issues/comments/(\d+)", path)
        if m and method == "PATCH":
            for c in comments:
                if c["id"] == int(m.group(1)):
                    c["body"] = body.get("body", "")
                    save()
                    return self.reply(200, c)
        m = re.fullmatch(r"/repos/[^/]+/[^/]+/collaborators/([^/]+)/permission", path)
        if m and method == "GET":
            login = m.group(1)
            return self.reply(200, {"permission": "write", "role_name": "write",
                                    "user": {"login": login, "type": "User"}})
        m = re.fullmatch(r"/users/([^/]+)", path)
        if m and method == "GET":
            return self.reply(200, {"login": m.group(1), "type": "User", "id": 1})
        return self.reply(404, {"message": "Not Found (mock)"})

    def do_GET(self):
        self.handle_any("GET")

    def do_POST(self):
        self.handle_any("POST")

    def do_PATCH(self):
        self.handle_any("PATCH")


save()
ThreadingHTTPServer(("0.0.0.0", port), Handler).serve_forever()
