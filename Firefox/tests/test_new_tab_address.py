"""Native empty address bar and immediate typing on myBro's start page."""
import os
import base64
from runtime import Firefox, ROOT


def main():
    os.environ['MOZ_HEADLESS'] = '1'
    with Firefox() as f:
        f.wait('window.myBro?.ready')
        f.wait("gBrowser.currentURI.spec==='about:mybro?view=start'")
        f.wait("gURLBar.value===''")
        assert f.js("return isInitialPage('about:mybro?view=start')&&!isInitialPage('about:mybro?view=settings')&&!isInitialPage('https://example.invalid/');")
        print('PASS startup page has an empty native address bar', flush=True)
        f.js('Services.prefs.setBoolPref("browser.search.suggest.enabled",false);Services.prefs.setBoolPref("browser.urlbar.suggest.searches",false);')
        for action in ('myBro.newTab()', 'document.getElementById("cmd_newNavigatorTab").doCommand()', 'plus button'):
            before = f.js('return gBrowser.tabs.length;')
            if action == 'plus button':
                point = f.js('const r=document.getElementById("tabs-newtab-button").getBoundingClientRect();return {x:Math.round(r.x+r.width/2),y:Math.round(r.y+r.height/2)};')
                f.command('WebDriver:PerformActions', {'actions':[dict(type='pointer', id='mouse', parameters=dict(pointerType='mouse'), actions=[dict(type='pointerMove', duration=0, **point), dict(type='pointerDown', button=0), dict(type='pointerUp', button=0)])]})
            else:
                f.js(action + ';')
            f.wait(f'gBrowser.tabs.length==={before+1}')
            assert f.js("return gURLBar.value===''&&document.activeElement===gURLBar.inputField;"), action
            if action == 'myBro.newTab()':
                shot = f.command('WebDriver:TakeScreenshot', {'full':False})
                data = shot.get('value',shot) if isinstance(shot,dict) else shot
                (ROOT/'.build/firefox/empty-new-tab.png').write_bytes(base64.b64decode(data))
            actions = []
            for char in 'mybro sample':
                actions.extend([dict(type='keyDown', value=char), dict(type='keyUp', value=char)])
            f.command('WebDriver:PerformActions', {'actions':[dict(type='key', id='keyboard', actions=actions)]})
            f.wait("gBrowser.currentURI.spec==='about:mybro?view=start'&&gURLBar.value==='mybro sample'")
            f.command('WebDriver:ReleaseActions')
            print('PASS immediate typing without about: prefix: ' + action, flush=True)
        f.js("myBro.openManager('settings');")
        f.wait("gBrowser.currentURI.spec==='about:preferences#grayfox'")
        f.js('gURLBar.blur();gURLBar.setURI();')
        assert f.js("return gURLBar.value==='about:preferences#grayfox';")
        f.js('myBro.newTab();')
        f.wait("gBrowser.currentURI.spec==='about:mybro?view=start'&&gURLBar.value===''")
        f.js('window.normalTest=OpenBrowserWindow();')
        f.wait('normalTest.myBro?.ready')
        f.wait("normalTest.gBrowser.currentURI.spec==='about:mybro?view=start'&&normalTest.gURLBar.value===''")
        f.js('normalTest.close();')
        print('PASS internal page addresses remain visible and new windows start empty', flush=True)
        f.js('window.privateTest=OpenBrowserWindow({private:true});')
        f.wait('privateTest.myBro?.ready')
        f.wait("privateTest.gBrowser.currentURI.spec==='about:mybro?view=start'&&privateTest.gURLBar.value===''")
        f.js('privateTest.myBro.newTab();')
        f.wait("privateTest.gURLBar.value===''&&privateTest.document.activeElement===privateTest.gURLBar.inputField")
        f.js('privateTest.close();')
        print('PASS private new windows and tabs also have an empty focused address bar', flush=True)


if __name__ == '__main__':
    main()
