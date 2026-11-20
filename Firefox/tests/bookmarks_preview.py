"""Serve the real bookmark UI with synthetic Places data for global Playwright."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

HERE = Path(__file__).resolve().parent
FILES = {
    '/bookmarks.html': (HERE / 'bookmarks-fixture.html', 'text/html'),
    '/history.html': (HERE / 'history-fixture.html', 'text/html'),
    '/addons.html': (HERE / 'addons-fixture.html', 'text/html'),
    '/navigation.js': (HERE.parent / 'chrome/navigation.js', 'text/javascript'),
    '/navigation.css': (HERE.parent / 'chrome/navigation.css', 'text/css'),
    '/addons-navigation.js': (HERE.parent / 'chrome/addons-navigation.js', 'text/javascript'),
    '/addons-layout.css': (HERE.parent / 'chrome/addons-layout.css', 'text/css'),
    '/manager.js': (HERE.parent / 'chrome/manager.js', 'text/javascript'),
    '/manager.css': (HERE.parent / 'chrome/manager.css', 'text/css'),
    '/MyBro9GagChild.sys.mjs': (HERE.parent / 'chrome/MyBro9GagChild.sys.mjs', 'text/javascript'),
    '/MyBroLoginFieldsChild.sys.mjs': (HERE.parent / 'chrome/MyBroLoginFieldsChild.sys.mjs', 'text/javascript'),
}


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        entry = FILES.get(urlparse(self.path).path)
        if not entry:
            self.send_error(404)
            return
        path, kind = entry
        data = path.read_bytes()
        self.send_response(200)
        self.send_header('Content-Type', kind + '; charset=utf-8')
        self.send_header('Content-Length', str(len(data)))
        self.send_header('Cache-Control', 'no-store')
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, *_):
        pass


if __name__ == '__main__':
    server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
    print('http://127.0.0.1:' + str(server.server_port) + '/bookmarks.html?view=bookmarks', flush=True)
    server.serve_forever()
