#!/usr/bin/env python3
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import time


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/download":
            self.slow_download()
            return
        if self.path != "/":
            self.send_error(404)
            return
        page = (b"<title>myBro Local Fixture</title><h1>myBro Local Fixture</h1>"
                b'<a href="/download">Download test file</a>')
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Set-Cookie", "mybro_fixture=present; Path=/")
        self.send_header("Content-Length", str(len(page)))
        self.end_headers()
        self.wfile.write(page)

    def slow_download(self):
        chunk = b"myBro download probe\n" * 1024
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Disposition", 'attachment; filename="mybro-download-probe-27a1.txt"')
        self.send_header("Content-Length", str(len(chunk) * 64))
        self.end_headers()
        try:
            for _ in range(64):
                self.wfile.write(chunk)
                self.wfile.flush()
                time.sleep(0.125)
        except (BrokenPipeError, ConnectionResetError):
            pass


if __name__ == "__main__":
    with ThreadingHTTPServer(("127.0.0.1", 0), Handler) as server:
        print(f"http://127.0.0.1:{server.server_port}/", flush=True)
        server.serve_forever()

