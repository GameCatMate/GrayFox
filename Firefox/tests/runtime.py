"""Local-only Marionette harness for privileged Firefox browser chrome tests."""
import json
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / "GrayFox.app"

class Firefox:
    def __init__(self, profile=None):
        parent = ROOT / ".build/firefox/test-profiles"
        parent.mkdir(parents=True, exist_ok=True)
        self.profile = Path(profile) if profile else Path(tempfile.mkdtemp(prefix="test-", dir=parent))
        self.profile.mkdir(parents=True, exist_ok=True)
        with socket.socket() as probe:
            probe.bind(("127.0.0.1", 0)); self.port = probe.getsockname()[1]
        self.original_user_js=(self.profile/"user.js").read_bytes() if (self.profile/"user.js").exists() else None
        (self.profile / "user.js").write_text('user_pref("marionette.port", %d);\nuser_pref("browser.shell.checkDefaultBrowser", false);\nuser_pref("remote.prefs.recommended", false);\n' % self.port)
        self.log = (self.profile / "process.log").open("ab")
        env = {**os.environ, "MYBRO_FIREFOX_PROFILE": str(self.profile), "MOZ_CRASHREPORTER_DISABLE": "1", "MOZ_REMOTE_ALLOW_SYSTEM_ACCESS": "1"}
        self.process = subprocess.Popen([str(APP / "Contents/MacOS/mybro-launcher"), "--marionette", "--remote-allow-system-access", "-foreground"], env=env, stdout=self.log, stderr=self.log)
        self.socket = None
        self.buffer = b""
        self.index = 0
        deadline = time.monotonic() + 35
        while time.monotonic() < deadline:
            if self.process.poll() is not None:
                raise RuntimeError("Firefox exited: " + (self.profile / "process.log").read_text(errors="replace")[-3000:])
            try:
                self.socket = socket.create_connection(("127.0.0.1", self.port), timeout=1)
                self.socket.settimeout(30)
                break
            except OSError:
                time.sleep(.15)
        if not self.socket:
            raise RuntimeError("Marionette timeout: " + (self.profile / "process.log").read_text(errors="replace")[-3000:])
        self.receive()
        self.command("WebDriver:NewSession", {"capabilities": {"alwaysMatch": {"acceptInsecureCerts": False}}})
        self.command("Marionette:SetContext", {"value": "chrome"})

    def receive(self):
        while b":" not in self.buffer:
            part = self.socket.recv(65536)
            if not part: raise ConnectionError("Firefox closed connection")
            self.buffer += part
        raw_size, rest = self.buffer.split(b":", 1)
        size = int(raw_size)
        while len(rest) < size:
            part = self.socket.recv(65536)
            if not part: raise ConnectionError("Firefox closed connection")
            rest += part
        message, self.buffer = rest[:size], rest[size:]
        return json.loads(message)

    def command(self, name, parameters=None):
        self.index += 1
        payload = json.dumps([0, self.index, name, parameters or {}]).encode()
        self.socket.sendall(str(len(payload)).encode() + b":" + payload)
        while True:
            packet = self.receive()
            if packet[0] == 1 and packet[1] == self.index:
                if packet[2]: raise RuntimeError(json.dumps(packet[2], ensure_ascii=False))
                return packet[3]

    def js(self, script, args=None):
        result = self.command("WebDriver:ExecuteScript", {"script": script, "args": args or [], "newSandbox": False, "sandbox": "system"})
        return result.get("value", result) if isinstance(result, dict) else result

    def async_js(self, script, args=None):
        result = self.command("WebDriver:ExecuteAsyncScript", {"script": script, "args": args or [], "newSandbox": False, "sandbox": "system"})
        return result.get("value", result) if isinstance(result, dict) else result

    def wait(self, expression, seconds=10):
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            if self.js("return !!(" + expression + ");"): return
            time.sleep(.1)
        raise AssertionError("Timed out: " + expression)

    def close(self):
        if self.socket:
            try: self.command("Marionette:Quit", {"flags": ["eAttemptQuit"]})
            except (OSError, RuntimeError, ConnectionError): pass
            self.socket.close()
        try: self.process.wait(timeout=8)
        except subprocess.TimeoutExpired:
            self.process.terminate()
            self.process.wait(timeout=8)
        self.log.close()
        if self.original_user_js is None:
            (self.profile/"user.js").unlink(missing_ok=True)
        else:
            (self.profile/"user.js").write_bytes(self.original_user_js)
        prefs=self.profile/"prefs.js"
        if prefs.exists():
            prefs.write_text("\n".join(line for line in prefs.read_text().splitlines() if not line.startswith('user_pref("marionette.'))+"\n")

    def __enter__(self): return self
    def __exit__(self, *_): self.close()

if __name__ == "__main__":
    with Firefox() as browser:
        browser.wait("window.myBro")
        print(browser.js("return {ready: !!window.myBro, name: Services.appinfo.name, version: Services.appinfo.version, tabs: gBrowser.tabs.length, uri: gBrowser.currentURI.spec};"))
