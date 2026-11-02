#!/usr/bin/env python3
"""Receives log lines, photos and replies from the Glasses Tutor app.

    scripts/debug-server.py [port] [dir]

Everything lands in <dir> (default ~/glasses-tutor-debug): log.txt gets every line,
photos are saved as <time>-<name>.jpg, replies as <time>-<name>.txt. Lines are also
printed to stdout. In the app, set "Debug server URL" to http://<laptop-ip>:<port>.
"""
import sys, time, pathlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

port = int(sys.argv[1]) if len(sys.argv) > 1 else 8787
root = pathlib.Path(sys.argv[2] if len(sys.argv) > 2 else "~/glasses-tutor-debug").expanduser()
root.mkdir(parents=True, exist_ok=True)
logfile = root / "log.txt"

def stamp():
    return time.strftime("%Y-%m-%d %H:%M:%S")

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_POST(self):
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length)
        parts = self.path.strip("/").split("/", 1)
        kind = parts[0]
        name = (parts[1] if len(parts) > 1 else "x").replace("/", "_")
        if kind == "log":
            line = f"{stamp()} {body.decode('utf-8', 'replace')}"
            print(line, flush=True)
            logfile.open("a").write(line + "\n")
        elif kind == "photo":
            path = root / f"{time.strftime('%H-%M-%S')}-{name}.jpg"
            path.write_bytes(body)
            msg = f"{stamp()} [photo {name}] {len(body)} bytes -> {path}"
            print(msg, flush=True)
            logfile.open("a").write(msg + "\n")
        elif kind == "text":
            path = root / f"{time.strftime('%H-%M-%S')}-{name}.txt"
            path.write_bytes(body)
            text = body.decode("utf-8", "replace")
            msg = f"{stamp()} [{name}] -> {path}\n{text}\n"
            print(msg, flush=True)
            logfile.open("a").write(msg + "\n")
        self.send_response(204)
        self.end_headers()

print(f"debug server on port {port}, writing to {root}", flush=True)
ThreadingHTTPServer(("0.0.0.0", port), Handler).serve_forever()
