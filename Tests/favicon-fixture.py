from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import collections
import json
import struct
import zlib


def png(red, green, blue):
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(bytes([0, red, green, blue, 255]))) + chunk(b"IEND", b""))


pixels = bytes([230, 140, 40, 255]) * (16 * 16)
mask = bytes(4 * 16)
dib = struct.pack("<IiiHHIIiiII", 40, 16, 32, 1, 32, 0, len(pixels) + len(mask), 0, 0, 0, 0) + pixels + mask
ico = struct.pack("<HHH", 0, 1, 1) + struct.pack("<BBBBHHII", 16, 16, 0, 0, 1, 32, len(dib), 22) + dib
counts = collections.Counter()
cookies_received = False


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_GET(self):
        global cookies_received
        counts[self.path] += 1
        cookies_received |= bool(self.headers.get("Cookie"))
        body, content_type = {
            "/": (b'<title>Icon fixture</title><link rel="icon" type="image/svg+xml" href="/icon.svg">'
                   b'<link rel="icon" type="image/png" href="/site-icon.png"><h1>Icon fixture</h1>', "text/html"),
            "/favicon.ico": (ico, "image/x-icon"),
            "/site-icon.png": (png(230, 60, 70), "image/png"),
            "/invalid": (b"<html>Not an icon</html>", "text/html"),
            "/large": (b"x" * (512 * 1024 + 1), "image/png"),
            "/counts": (json.dumps({"requests": counts, "cookies": cookies_received}).encode(), "application/json"),
        }.get(self.path, (b"", "text/plain"))
        if self.path == "/favicon.ico" and self.headers.get("Host", "").startswith("localhost:"):
            body = b""
        self.send_response(200 if body else 404)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "public, max-age=3600")
        self.send_header("Set-Cookie", "icon_fixture=fixture; Path=/")
        self.end_headers()
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass


if __name__ == "__main__":
    with ThreadingHTTPServer(("127.0.0.1", 0), Handler) as server:
        print(f"http://127.0.0.1:{server.server_port}/", flush=True)
        server.serve_forever()
