"""Native Gecko MV2, autofill, downloads, migration and pointer interaction checks."""
import http.server
import json
from pathlib import Path
import tempfile
import ssl
import subprocess
import threading
import time
from urllib.parse import urlparse
from runtime import Firefox,ROOT
from test_runtime import task,check

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path=='/file':
            body=b'Synthetic myBro download\n';self.send_response(200);self.send_header('Content-Type','application/octet-stream');self.send_header('Content-Disposition','attachment; filename="mybro-test.txt"')
        else:
            body=b'<!doctype html><title>Synthetic login</title><form action="/done" method="post"><input id="username" name="username" autocomplete="username"><input id="password" name="password" type="password" autocomplete="current-password"><button>Sign in</button></form>';self.send_response(200);self.send_header('Content-Type','text/html')
        self.send_header('Content-Length',str(len(body)));self.end_headers();self.wfile.write(body)
    def log_message(self,*_):pass


def drag(f,a,b):
    f.command('WebDriver:PerformActions',{'actions':[{'type':'pointer','id':'mouse','parameters':{'pointerType':'mouse'},'actions':[{'type':'pointerMove','x':round(a['x']),'y':round(a['y']),'duration':0},{'type':'pointerDown','button':0},{'type':'pointerMove','x':round(b['x']),'y':round(b['y']),'duration':600},{'type':'pointerUp','button':0}]}]})
    f.command('WebDriver:ReleaseActions');time.sleep(.2)


def main():
    tls=Path(tempfile.mkdtemp(prefix='tls-',dir=ROOT/'.build/firefox'))
    subprocess.run(['openssl','req','-x509','-newkey','rsa:2048','-nodes','-keyout',str(tls/'key.pem'),'-out',str(tls/'cert.pem'),'-days','1','-subj','/CN=localhost','-addext','subjectAltName=DNS:localhost','-addext','basicConstraints=critical,CA:TRUE'],check=True,capture_output=True)
    subprocess.run(['openssl','req','-new','-newkey','rsa:2048','-nodes','-keyout',str(tls/'leaf-key.pem'),'-out',str(tls/'leaf.csr'),'-subj','/CN=localhost'],check=True,capture_output=True)
    (tls/'extensions').write_text('subjectAltName=DNS:localhost\nbasicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\n')
    subprocess.run(['openssl','x509','-req','-in',str(tls/'leaf.csr'),'-CA',str(tls/'cert.pem'),'-CAkey',str(tls/'key.pem'),'-CAcreateserial','-out',str(tls/'leaf.pem'),'-days','1','-extfile',str(tls/'extensions')],check=True,capture_output=True)
    context=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER);context.load_cert_chain(tls/'leaf.pem',tls/'leaf-key.pem')
    server=http.server.ThreadingHTTPServer(('127.0.0.1',0),Handler);server.socket=context.wrap_socket(server.socket,server_side=True)
    threading.Thread(target=server.serve_forever,daemon=True).start();base='https://localhost:'+str(server.server_port)
    try:
        with Firefox() as f:
            f.wait('window.myBro?.ready');time.sleep(.4)
            cert=(tls/'cert.pem').read_text().replace('-----BEGIN CERTIFICATE-----','').replace('-----END CERTIFICATE-----','').replace('\n','')
            f.js("Cc['@mozilla.org/security/x509certdb;1'].getService(Ci.nsIX509CertDB).addCertFromBase64(arguments[0],'CT,,','');return true;",[cert])
            folder=Path(tempfile.mkdtemp(prefix='native-',dir=ROOT/'.build/firefox'))
            addon=folder/'addon';addon.mkdir();(addon/'manifest.json').write_text(json.dumps({'manifest_version':2,'name':'myBro MV2 test','version':'1.0','browser_specific_settings':{'gecko':{'id':'mybro-native-test@example.invalid'}},'permissions':['webRequest','webRequestBlocking','<all_urls>'],'background':{'scripts':['background.js']}}));(addon/'background.js').write_text('browser.webRequest.onBeforeRequest.addListener(()=>({cancel:true}),{urls:["*://localhost/*blocked*"]},["blocking"]);')
            result=task(f,"const{AddonManager}=ChromeUtils.importESModule('resource://gre/modules/AddonManager.sys.mjs');const file=Cc['@mozilla.org/file/local;1'].createInstance(Ci.nsIFile);file.initWithPath(arguments[0]);window.nativeTestAddon=await AddonManager.installTemporaryAddon(file);return {active:nativeTestAddon.isActive,version:nativeTestAddon.manifestVersion};",[str(addon)])
            check(result['active'] and result['version']==2,'Manifest V2 extension installs and runs')
            task(f,"const L=ChromeUtils.importESModule('chrome://browser/content/mybro/library.sys.mjs');return await L.importPasswords([{origin:arguments[0],username:'synthetic-user',password:'synthetic-password'}]);",[base])
            f.js("gBrowser.selectedBrowser.loadURI(Services.io.newURI(arguments[0]+'/login'),{triggeringPrincipal:Services.scriptSecurityManager.getSystemPrincipal()});return true;",[base])
            f.command('Marionette:SetContext',{'value':'content'})
            try:f.wait("document.readyState==='complete'&&document.getElementById('password')")
            except AssertionError:
                print(f.js("return {url:location.href,text:document.body.textContent.slice(0,1800)};"));raise
            try:f.wait("document.getElementById('username').value==='synthetic-user'&&document.getElementById('password').value==='synthetic-password'",seconds=8)
            except AssertionError:
                print(f.js("return {origin:location.origin,secure:window.isSecureContext,values:[document.getElementById('username').value,document.getElementById('password').value]};"))
                f.command('Marionette:SetContext',{'value':'chrome'})
                print(task(f,"return {prefs:['signon.rememberSignons','signon.autofillForms','signon.autofillForms.http','signon.autofillForms.autocompleteOff'].map(k=>[k,Services.prefs.getBoolPref(k,false)]),entries:(await Services.logins.getAllLogins()).map(l=>({origin:l.origin,action:l.formActionOrigin,realm:l.httpRealm})),errors:Services.console.getMessageArray().filter(x=>/LoginManager|LoginForm|login-manager/.test(x.message)).map(x=>x.message).slice(-10)};"))
                raise
            check(True,'native password autofill on actual login form')
            result=task(f,"try{await fetch('/blocked');return false;}catch{return true;}")
            check(result,'Manifest V2 webRequestBlocking actually blocks a content request')
            f.command('Marionette:SetContext',{'value':'chrome'})
            task(f,"await nativeTestAddon.uninstall();return true;")
            f.js("const path=arguments[0],file=Cc['@mozilla.org/file/local;1'].createInstance(Ci.nsIFile);file.initWithPath(path);Services.prefs.setComplexValue('browser.download.dir',Ci.nsIFile,file);Services.prefs.setIntPref('browser.download.folderList',2);Services.prefs.setBoolPref('browser.download.useDownloadDir',true);gBrowser.selectedBrowser.loadURI(Services.io.newURI(arguments[1]+'/file'),{triggeringPrincipal:Services.scriptSecurityManager.getSystemPrincipal()});return true;",[str(folder),base])
            for _ in range(50):
                if(folder/'mybro-test.txt').exists():break
                time.sleep(.1)
            check((folder/'mybro-test.txt').read_bytes()==b'Synthetic myBro download\n','automatic download without save confirmation')
            result=task(f,"const L=ChromeUtils.importESModule('chrome://browser/content/mybro/library.sys.mjs');return (await(await L.downloads.getList(L.downloads.PUBLIC)).getAll()).some(d=>d.succeeded&&d.target.path.endsWith('/mybro-test.txt'));")
            check(result,'download is present in native history')
            f.js("myBro.write('groups',[{id:'a',name:'Alpha',color:'blue'},{id:'b',name:'Beta',color:'green'}]);myBro.selectGroup('a');myBro.newTab();return true;");time.sleep(.3)
            positions=f.js("return [...document.querySelectorAll('.mybro-group')].map(n=>{const r=n.getBoundingClientRect();return{x:r.x+r.width/2,y:r.y+r.height/2};});")
            f.js("window.dragEvents=[];for(const type of ['pointerdown','pointermove','pointerup','click'])window.addEventListener(type,e=>{if(dragEvents.length<60)dragEvents.push([type,e.clientX,e.clientY,e.target.id||e.target.className]);},true);return true;")
            target={**positions[1],'x':positions[1]['x']+15};drag(f,positions[0],target)
            if not f.js("return myBro.groups()[0].id==='b';"):
                print('DRAG',positions,f.js("return {groups:myBro.groups(),dom:[...document.querySelectorAll('.mybro-group')].map(x=>x.dataset.group),events:dragEvents,errors:Services.console.getMessageArray().filter(x=>x.message?.includes('mybro/chrome.js')).map(x=>x.message).slice(-5)};"))
            check(f.js("return myBro.groups()[0].id==='b';"),'actual mouse drag reorders groups')
            f.js("myBro.newTab();myBro.newTab();return true;");time.sleep(.2)
            positions=f.js("window.draggedTab=myBro.visible()[0];return [myBro.visible()[0],myBro.visible()[2]].map(n=>{const r=n.getBoundingClientRect();return{x:r.x+r.width/2,y:r.y+r.height/2};});")
            f.js("dragEvents=[];return true;")
            drag(f,positions[0],{**positions[1],'x':positions[1]['x']+15})
            if not f.js("return myBro.visible().indexOf(draggedTab)>=1;"):
                print('TAB DRAG',positions,f.js("return {index:myBro.visible().indexOf(draggedTab),events:dragEvents,errors:Services.console.getMessageArray().filter(x=>x.message?.includes('mybro/chrome.js')).map(x=>x.message).slice(-5)};"))
            check(f.js("return myBro.visible().indexOf(draggedTab)>=1;"),'actual mouse drag reorders tabs')
            legacy={'browser':{'tabs':[{'page':{'title':'Imported','url':base+'/imported'},'group':'Imported group'}],'selected':0,'groups':['Imported group'],'groupTints':{'Imported group':'Зелёный'},'history':[{'url':base+'/past','title':'Past','visitedAt':time.time()-978307200-300}],'bookmarks':[],'bookmarkFolders':[{'id':'f','name':'Imported folder','pages':[{'title':'Bookmark','url':base+'/bookmark'}]}]},'preferences':{'browser-theme':'dark'},'passwords':[{'origin':{'url':base},'username':'imported-user','password':'synthetic-imported-password'}]}
            result=task(f,"return await ChromeUtils.importESModule('chrome://browser/content/mybro/library.sys.mjs').importLegacy(arguments[0],window);",[legacy])
            check(result['tabs']==1 and result['groups']==1 and result['passwords']==1 and result['bookmarks']==1,'legacy myBro data migration through native Firefox services')
            f.wait("myBro.groups().some(g=>g.name==='Imported group')")
            print('PROFILE',f.profile,flush=True)
    finally:server.shutdown()

if __name__=='__main__':main()
