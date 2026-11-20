"""Exercise the real Gecko content actors headlessly, with synthetic local data only."""
import os
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from runtime import Firefox


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        body = b'''<form><input id="username" name="username" type="login" autocomplete="email"></form>
<div class="post-view video-post"><a href="#post"><video style="width:320px;height:180px"></video></a><button class="sound-toggle">Sound</button></div>
<script>document.body.dataset.sound=0;document.body.dataset.posts=0;
document.querySelector('.sound-toggle').onclick=e=>{e.stopPropagation();document.body.dataset.sound++};
document.querySelector('a').onclick=e=>{e.preventDefault();document.body.dataset.posts++};</script>'''
        self.send_response(200)
        self.send_header('Content-Type', 'text/html')
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_):
        pass


def main():
    os.environ['MOZ_HEADLESS'] = '1'
    server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    try:
        with Firefox() as f:
            f.wait('window.myBro?.ready')
            f.js('''for(const [name,events] of [['MyBro9Gag',{click:{capture:true,mozSystemGroup:false}}],['MyBroLoginFields',{DOMWindowCreated:{}}]]){
ChromeUtils.unregisterWindowActor(name);ChromeUtils.registerWindowActor(name,{remoteTypes:['web'],safeForUntrustedWebProcess:true,child:{esModuleURI:'chrome://browser/content/mybro/'+name+'Child.sys.mjs',events},matches:['http://127.0.0.1/*'],allFrames:false});}return true;''')
            f.command('Marionette:SetContext', {'value':'content'})
            f.command('WebDriver:Navigate', {'url':f'http://127.0.0.1:{server.server_port}/'})
            try:
                f.wait('document.querySelector("#username").getAttribute("type")==="text"')
            except AssertionError:
                f.command('Marionette:SetContext', {'value':'chrome'})
                print(f.js('return Services.console.getMessageArray().map(m=>m.message).filter(m=>/MyBro|mybro|actor/i.test(m));'))
                raise
            assert f.js('return document.querySelector("#username").autocomplete') == 'username'
            for _ in range(2):
                f.command('WebDriver:PerformActions', {'actions':[{'type':'pointer','id':'mouse','parameters':{'pointerType':'mouse'},'actions':[
                    {'type':'pointerMove','x':100,'y':100},{'type':'pointerDown','button':0},{'type':'pointerUp','button':0}]}]})
            result = f.js('return {sound:document.body.dataset.sound,posts:document.body.dataset.posts}')
            assert result == {'sound':'2','posts':'0'}, result
            print('PASS: Gecko normalizes the login field and intercepts repeated video clicks')
    finally:
        server.shutdown()


if __name__ == '__main__':
    main()
