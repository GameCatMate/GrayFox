"""Headless Gecko regression for script-opened authentication windows."""
import os
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from runtime import Firefox


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/account-picker':
            body = b'<title>Synthetic account picker</title><p>Choose a synthetic account</p>'
        else:
            body = b'''<button style="width:200px;height:60px" id="login">Synthetic sign-in</button><button id="continue">Finish preparing sign-in</button>
<script>document.querySelector('button').onclick=()=>{
const features=location.search.includes('full')?'toolbar=yes,location=yes,menubar=yes,status=yes,width=600,height=600':'popup,width=480,height=600';
const auth=window.open('', 'synthetic-auth', features);
document.querySelector('#continue').onclick=()=>{auth.location.href='/account-picker'};
};</script>'''
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
    base = f'http://127.0.0.1:{server.server_port}'
    try:
        with Firefox() as f:
            f.wait('window.myBro?.ready')
            f.wait("gBrowser.currentURI.spec==='about:mybro?view=start'")
            f.js("window.normalTest=OpenBrowserWindow();return true;")
            f.wait('normalTest.myBro?.ready')
            f.wait("normalTest.gBrowser.currentURI.spec==='about:mybro?view=start'")
            f.js("normalTest.close();Services.prefs.setIntPref('browser.link.open_newwindow',2);return true;")
            print('PASS: ordinary new window keeps the myBro start page', flush=True)
            for mode in ['popup', 'full']:
                f.command('Marionette:SetContext', {'value':'content'})
                f.command('WebDriver:Navigate', {'url':base + '/?' + mode})
                f.command('WebDriver:PerformActions', {'actions':[{'type':'pointer','id':'mouse','parameters':{'pointerType':'mouse'},'actions':[
                    {'type':'pointerMove','x':70,'y':35},{'type':'pointerDown','button':0},{'type':'pointerUp','button':0}]}]})
                f.command('Marionette:SetContext', {'value':'chrome'})
                f.wait("Array.from(Services.wm.getEnumerator('navigator:browser')).some(w=>w!==window&&!w.closed)")
                f.js("window.authTest=Array.from(Services.wm.getEnumerator('navigator:browser')).find(w=>w!==window&&!w.closed);return true;")
                f.wait('authTest.myBro?.ready')
                state = f.async_js("const done=arguments[arguments.length-1];setTimeout(()=>done({url:authTest.gBrowser.currentURI.spec,opener:!!authTest.gBrowser.selectedBrowser.browsingContext.opener,toolbar:authTest.toolbar.visible}),500);")
                assert state['url'] == 'about:blank', (mode, state)
                assert state['opener'], state
                f.command('Marionette:SetContext', {'value':'content'})
                f.js("document.querySelector('#continue').click();return true;")
                f.command('Marionette:SetContext', {'value':'chrome'})
                f.wait("authTest.gBrowser.currentURI.spec===" + repr(base + '/account-picker'))
                f.wait("authTest.gURLBar.untrimmedValue===" + repr(base + '/account-picker'))
                f.js('authTest.close();return true;')
                print('PASS: script-opened ' + mode + ' stays blank and then reaches the account picker', flush=True)
    finally:
        server.shutdown()


if __name__ == '__main__':
    main()
