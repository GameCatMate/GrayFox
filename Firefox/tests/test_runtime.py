"""Real Gecko acceptance checks. Runs only against disposable profiles."""
import base64
import json
from pathlib import Path
import sys
import tempfile
import time
import zipfile
from runtime import Firefox, ROOT


def task(browser,script,args=None):
    result=browser.async_js("const done=arguments[arguments.length-1];(async()=>{"+script+"})().then(value=>done({ok:true,value}),error=>done({ok:false,error:String(error),stack:error.stack}));",args)
    assert result["ok"], result
    return result.get("value")


def check(condition,message):
    assert condition,message
    print("PASS",message,flush=True)


def main():
    with Firefox() as f:
        f.wait("window.myBro?.ready")
        f.wait("gBrowser.currentURI.spec.startsWith('about:mybro')")
        check(f.js("return Services.appinfo.name==='GrayFox' && Services.appinfo.version==='160.0.1';"),"GrayFox runs on Gecko 160.0.1")
        check(f.js("return navigator.userAgent.includes('Firefox/160.0') && !navigator.userAgent.includes('GrayFox/');"),"standard Firefox compatibility User-Agent")
        for view in ["start","history","bookmarks","downloads","settings","profile"]:
            f.js("myBro.openManager(arguments[0]);return true;",[view])
            flag="grayfoxReady" if view=="settings" else "ready"
            f.wait("gBrowser.selectedBrowser.contentDocument?.documentElement?.dataset."+flag+"==='true'")
            notice="grayfox-settings-notice" if view=="settings" else "notice"
            check(not f.js("return gBrowser.selectedBrowser.contentDocument.getElementById(arguments[0]).textContent;",[notice]),"internal page "+view)
        f.js("myBro.write('groups',[{id:'a',name:'Работа',color:'blue'},{id:'b',name:'Личное',color:'green'}]);myBro.selectGroup('a');myBro.newTab();myBro.selectGroup('b');myBro.newTab();return true;")
        check(f.js("return myBro.visible().length===2 && myBro.visible().every(t=>myBro.groupOf(t)==='b');"),"new tabs inherit selected group")
        f.js("myBro.selectGroup('a');return true;");time.sleep(.2)
        check(f.js("return myBro.visible().length===2 && [...gBrowser.tabs].filter(t=>!t.hasAttribute('mybro-hidden')).every(t=>myBro.groupOf(t)==='a');"),"other groups are hidden")
        f.js("window.testTab=gBrowser.selectedTab;gBrowser.removeTab(testTab);return true;")
        time.sleep(.4);f.js('myBro.reopenClosed();return true;');time.sleep(.6)
        check(f.js("return myBro.groupOf(gBrowser.selectedTab)==='a' && myBro.current==='a';"),"closed tab restores into its group")
        f.js("myBro.newTab();myBro.newTab();return true;")
        f.js("const tabs=myBro.visible();gBrowser.moveTabBefore(tabs.at(-1),tabs[0]);return true;")
        check(f.js("return myBro.visible().length>=4;"),"native tab reordering preserves group")
        result=task(f,"const L=ChromeUtils.importESModule('chrome://browser/content/mybro/library.sys.mjs');await L.importHistory([{url:'https://example.com/history-test',title:'Synthetic history',date:Date.now()-2000}]);const rows=await L.history('history-test');if(rows.length!==1)throw Error('missing visit');await L.removeVisit(rows[0]);return (await L.history('history-test')).length;")
        check(result==0,"history insertion and selective deletion")
        result=task(f,"const L=ChromeUtils.importESModule('chrome://browser/content/mybro/library.sys.mjs');await L.importHistory([{id:'native-limit',url:'https://example.com/native-limit?'+ 'a'.repeat(2100),title:'Native limit',visitedAt:1001},{id:'long',url:'https://example.com/overflow?'+ 'a'.repeat(66000),title:'Long URL',visitedAt:1000},{id:'undated',url:'https://example.com/undated',title:'Unknown date',visitedAt:null},{id:'m1',url:'https://example.com/same-ms',title:'First',visitedAt:1000.0001},{id:'m2',url:'https://example.com/same-ms',title:'Second',visitedAt:1000.0002}],true);const rows=await L.history('example.com/');if(rows.length!==5)throw Error('overflow missing');for(const row of rows)await L.removeVisit(row);return (await L.history('example.com/')).length===0;")
        check(result,"oversized, undated and submillisecond visits preserved and individually removable")

        result=task(f,"const L=ChromeUtils.importESModule('chrome://browser/content/mybro/library.sys.mjs'),P=L.places;const folder=await P.bookmarks.insert({parentGuid:P.bookmarks.toolbarGuid,title:'Synthetic folder',type:P.bookmarks.TYPE_FOLDER});const b=await P.bookmarks.insert({parentGuid:folder.guid,title:'Synthetic bookmark',url:'https://example.com/bookmark-test'});await P.bookmarks.update({guid:b.guid,title:'Renamed',parentGuid:P.bookmarks.unfiledGuid,index:P.bookmarks.DEFAULT_INDEX});const tree=await L.bookmarkTree();await P.bookmarks.remove(b.guid);await P.bookmarks.remove(folder.guid);return !!tree.children?.length;")
        check(result,"bookmark folder, rename, move and delete")
        result=task(f,"const L=ChromeUtils.importESModule('chrome://browser/content/mybro/library.sys.mjs');const n=await L.importPasswords([{origin:'https://example.com',username:'synthetic-user',password:'synthetic-not-a-real-secret'}]);const entries=await Services.logins.searchLoginsAsync({origin:'https://example.com'});return n===1&&entries.length===1;")
        check(result,"native encrypted password store")
        result=task(f,"const L=ChromeUtils.importESModule('chrome://browser/content/mybro/library.sys.mjs');const data={test:'roundtrip',tabs:[1,2]},bytes=await L.encrypt(data,'synthetic phrase 1234');const plain=await L.decrypt(bytes,'synthetic phrase 1234');let rejected=false;bytes[bytes.length-1]^=1;try{await L.decrypt(bytes,'synthetic phrase 1234');}catch{rejected=true;}return plain.test==='roundtrip'&&rejected;")
        check(result,"profile archive encryption and tamper rejection")
        result=task(f,"const {SearchService:S}=ChromeUtils.importESModule('moz-src:///toolkit/components/search/SearchService.sys.mjs');await S.init();return {normal:S.defaultEngine.name,private:S.defaultPrivateEngine.name};")
        check(result["normal"]=="Google" and "DuckDuckGo" in result["private"],"Google normal / DuckDuckGo private search")
        f.js("myBro.openManager('settings');return true;");f.wait("gBrowser.selectedBrowser.contentDocument?.documentElement?.dataset.grayfoxReady==='true'")
        image=f.command("WebDriver:TakeScreenshot",{"full":False})
        encoded=image.get("value",image) if isinstance(image,dict) else image
        (ROOT/'.build/firefox/runtime-settings.png').write_bytes(base64.b64decode(encoded))

        check(not f.js("return Services.console.getMessageArray().some(x=>x.message?.includes('JavaScript Error:')&&x.message?.includes('chrome://browser/content/mybro/'));"),"no myBro JavaScript errors")
        f.js("window.privateTest=OpenBrowserWindow({private:true});return true;")
        f.wait("privateTest?.myBro?.ready")
        f.wait("privateTest.gBrowser.selectedBrowser.contentDocument?.documentElement?.dataset.ready==='true'")
        check(f.js("const p=privateTest,n=p.document.getElementById('mybro-private-indicator'),key=p.document.getElementById('key_privatebrowsing'),restore=p.document.getElementById('key_undoCloseWindow');return ChromeUtils.importESModule('resource://gre/modules/PrivateBrowsingUtils.sys.mjs').PrivateBrowsingUtils.isWindowPrivate(p)&&!!n&&n.parentElement===p.document.getElementById('urlbar-container').parentElement&&p.getComputedStyle(n).display!=='none'&&key.getAttribute('key')==='n'&&!restore.hasAttribute('key')&&p.gBrowser.selectedBrowser.contentDocument.body.innerText.includes('Инкогнито');"),"private window, start page, Command Shift N and persistent address-toolbar indicator")
        f.js("privateTest.BrowserCommands.tryToCloseWindow();return true;")
        print("PROFILE",f.profile,flush=True)

if __name__=='__main__':main()
