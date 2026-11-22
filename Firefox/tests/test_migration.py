"""Legacy data transfer, encrypted archive and restart without touching real profiles."""
import time
from runtime import Firefox
from test_runtime import task,check


def main():
    now=time.time()-978307200
    data={'browser':{'tabs':[{'page':{'title':'A','url':'https://example.com/a'},'group':'Работа','pinned':True},{'page':{'title':'B','url':'https://example.com/b'},'group':'Личное'}],'selected':1,'groups':['Работа','Личное'],'groupTints':{'Работа':'Красный','Личное':'Зелёный'},'bookmarks':[],'bookmarkFolders':[{'id':'child','parentID':'parent','name':'Child','pages':[{'url':'https://example.com/b','title':'Book'}]},{'id':'parent','name':'Parent','pages':[]}],'history':[{'url':'https://example.com/old','title':'Old history','visitedAt':now-60}],'closed':[{'page':{'title':'Old closed','url':'https://example.com/older'},'group':'Работа','closedAt':now-60,'closedIndex':0},{'page':{'title':'Closed','url':'https://example.com/closed'},'group':'Работа','closedAt':now,'closedIndex':0}]},'passwords':[{'origin':{'url':'https://example.com'},'username':'fixture-user','password':'fixture-password'}],'preferences':{'browser-theme':'dark','password-autofill':True,'default-page-zoom':110},'downloads':[]}
    with Firefox() as f:
        profile=f.profile;f.wait('window.myBro?.ready')
        result=task(f,"const L=ChromeUtils.importESModule('chrome://browser/content/mybro/library.sys.mjs');return await L.importLegacy(arguments[0],window,{replaceSession:true});",[data])
        check(result['tabs']==2 and result['groups']==2 and result['passwords']==1 and result['bookmarks']==1,'legacy tabs/groups/passwords/bookmarks import')
        f.wait("gBrowser.tabs.length===2&&gBrowser.currentURI.spec==='https://example.com/b'")
        check(f.js("return myBro.groups().length===2&&myBro.groups()[0].color==='red'&&myBro.groupOf(gBrowser.selectedTab)===myBro.groups()[1].id;"),'legacy selection, group color and native session')
        check(task(f,"const L=ChromeUtils.importESModule('chrome://browser/content/mybro/library.sys.mjs');return (await L.history('example.com/old')).length;")==1,'legacy history timestamp conversion')
        result=task(f,"const L=ChromeUtils.importESModule('chrome://browser/content/mybro/library.sys.mjs');const p=await L.exportProfile(window),bytes=await L.encrypt(p,'fixture archive phrase'),decoded=await L.decrypt(bytes,'fixture archive phrase');return decoded.session.windows[0].tabs.length===2&&decoded.passwords.length===1;")
        check(result,'native profile encrypted export roundtrip')
        check(task(f,"const L=ChromeUtils.importESModule('chrome://browser/content/mybro/library.sys.mjs');try{await L.importProfile({format:'mybro-gecko-1',groups:[],session:{windows:[{tabs:[{entries:[{url:'javascript:alert(1)'}]}]}]}},window);return false;}catch{return true;}"),'unsafe imported navigation is rejected')
        time.sleep(1)
    with Firefox(profile) as f:
        f.wait('window.myBro?.ready');time.sleep(.8)
        check(f.js("return gBrowser.tabs.length===2&&myBro.groups().length===2;"),'migrated session and groups survive a restart')
        check(task(f,"return (await Services.logins.getAllLogins()).length;")==1,'native passwords survive a restart')
        check(f.js("return ChromeUtils.importESModule('moz-src:///browser/components/sessionstore/SessionStore.sys.mjs').SessionStore.getClosedTabCountForWindow(window);")>=1,'closed legacy tabs survive a restart')
        f.js("myBro.openManager('settings');return true;");f.wait("gBrowser.selectedBrowser.contentDocument?.documentElement?.dataset.grayfoxReady==='true'")
    with Firefox(profile) as f:
        f.wait('window.myBro?.ready')
        f.wait("gBrowser.currentURI.spec==='about:preferences#grayfox'&&gBrowser.selectedBrowser.contentDocument?.documentElement?.dataset.grayfoxReady==='true'")
        check(not f.js("return gBrowser.selectedBrowser.contentDocument.getElementById('grayfox-settings-notice').textContent;"),'active internal page survives browser startup ordering')
        f.js("myBro.reopenClosed();return true;");f.wait("gBrowser.currentURI.spec==='https://example.com/closed'")
        check(True,'last closed legacy tab is restored first')


if __name__=='__main__':main()
