"""Settings icon selects open as one opaque menu over their trigger."""
import base64
from pathlib import Path
import time
from runtime import Firefox


def main():
    for theme, width in [('dark', 1280), ('light', 700)]:
        with Firefox() as f:
            f.wait('window.myBro?.ready')
            f.command('WebDriver:SetWindowRect', {'width': width, 'height': 900})
            time.sleep(1)
            f.js("myBro.write('theme',arguments[0]);Services.prefs.setBoolPref('browser.search.separatePrivateDefault.featureGate',true);Services.prefs.setBoolPref('browser.search.separatePrivateDefault.enabled',true);myBro.nativePage('about:preferences#search');", [theme])
            f.wait("gBrowser.selectedBrowser.contentDocument?.getElementById('defaultPrivateEngine')?.shadowRoot?.querySelector('.panel-trigger')")
            panels = native = 0
            categories = f.js("return [...gBrowser.selectedBrowser.contentDocument.querySelectorAll('#grayfox-settings-sidebar button[data-view]')].map(n=>n.dataset.view);")
            for category in categories:
                f.js("gBrowser.selectedBrowser.contentWindow.gotoPref(arguments[0]);", [category])
                time.sleep(.3)
                count = f.js("const w=gBrowser.selectedBrowser.contentWindow;w.testSelects=[...w.document.querySelectorAll('moz-select')].filter(n=>n.getBoundingClientRect().width>0);return w.testSelects.length;")
                for index in range(count):
                    panel = f.js("const w=gBrowser.selectedBrowser.contentWindow;w.testSelect=w.testSelects[arguments[0]];w.testSelect.scrollIntoView({block:'center'});return w.testSelect.usePanelList;", [index])
                    if not panel:
                        assert f.js("return !!gBrowser.selectedBrowser.contentWindow.testSelect.shadowRoot.querySelector('select');")
                        native += 1
                        continue
                    panels += 1
                    point = f.js("const w=gBrowser.selectedBrowser.contentWindow,r=w.testSelect.shadowRoot.querySelector('.panel-trigger').getBoundingClientRect(),b=gBrowser.selectedBrowser.getBoundingClientRect();return {x:Math.round(b.x+r.x+r.width/2),y:Math.round(b.y+r.y+r.height/2)};")
                    f.command('WebDriver:PerformActions', {'actions': [{'type': 'pointer', 'id': 'mouse', 'parameters': {'pointerType': 'mouse'}, 'actions': [
                        {'type': 'pointerMove', 'duration': 0, 'origin': 'viewport', **point},
                        {'type': 'pointerDown', 'button': 0}, {'type': 'pause', 'duration': 350 if index % 2 else 0}, {'type': 'pointerUp', 'button': 0},
                    ]}]})
                    f.wait("(()=>{const p=gBrowser.selectedBrowser.contentWindow.testSelect.shadowRoot.querySelector('panel-list');return p.open&&!p.hasAttribute('showing')&&p.matches(':popover-open')})()")
                    result = f.js("const w=gBrowser.selectedBrowser.contentWindow,n=w.testSelect,p=n.shadowRoot.querySelector('panel-list'),s=n.shadowRoot.querySelector('.select-wrapper');return {field:s.getBoundingClientRect().toJSON(),menu:p.getBoundingClientRect().toJSON(),opacity:w.getComputedStyle(s).opacity,bg:w.getComputedStyle(p).backgroundColor,width:w.innerWidth,height:w.innerHeight};")
                    a, b = result['field'], result['menu']
                    assert result['opacity'] == '0' and result['bg'] not in ['transparent', 'rgba(0, 0, 0, 0)'], result
                    assert b['top'] <= a['top']+1 and b['bottom'] >= a['bottom']-1, result
                    assert b['left'] <= a['left']+1 and b['right'] >= a['right']-1, result
                    assert b['top'] >= 0 and b['bottom'] <= result['height']+1 and b['right'] <= result['width']+1, result
                    if category == 'paneSearch' and index == 0:
                        shot = f.command('WebDriver:TakeScreenshot', {'full': False})
                        shot = shot.get('value', shot) if isinstance(shot, dict) else shot
                        Path('.build/firefox/single-select-'+theme+'.png').write_bytes(base64.b64decode(shot))
                    f.js("const w=gBrowser.selectedBrowser.contentWindow;w.testSelect.shadowRoot.querySelector('panel-list').dispatchEvent(new w.KeyboardEvent('keydown',{key:'Escape',bubbles:true,composed:true}));")
                    f.wait("!gBrowser.selectedBrowser.contentWindow.testSelect.shadowRoot.querySelector('panel-list').open")
                    assert f.js("const w=gBrowser.selectedBrowser.contentWindow,n=w.testSelect;return w.getComputedStyle(n.shadowRoot.querySelector('.select-wrapper')).opacity==='1';")
            assert panels >= 2 and native >= 10, (panels, native)
            print(f'PASS {theme} {width}: {len(categories)} categories, {panels} single icon menus, {native} native selects, Escape restores triggers', flush=True)
            f.js("gBrowser.selectedBrowser.contentWindow.gotoPref('paneSearch');")
            for control in ['defaultEngineNormal', 'defaultPrivateEngine']:
                f.js("const w=gBrowser.selectedBrowser.contentWindow;w.testSelect=w.document.getElementById(arguments[0]);const b=w.testSelect.shadowRoot.querySelector('.panel-trigger');w.testSelect.scrollIntoView({block:'center'});b.focus();b.dispatchEvent(new w.KeyboardEvent('keydown',{key:'ArrowDown',bubbles:true}));", [control])
                f.wait("gBrowser.selectedBrowser.contentWindow.testSelect.shadowRoot.querySelector('panel-list').matches(':popover-open')")
                value = f.js("const p=gBrowser.selectedBrowser.contentWindow.testSelect.shadowRoot.querySelector('panel-list'),item=p.querySelector('panel-item:not([selected]):not([disabled])');const value=item.value;item.shadowRoot.querySelector('button').click();return value;")
                f.wait("!gBrowser.selectedBrowser.contentWindow.testSelect.shadowRoot.querySelector('panel-list').open")
                assert f.js("return gBrowser.selectedBrowser.contentWindow.testSelect.value;") == value
                assert f.js("const n=gBrowser.selectedBrowser.contentWindow.testSelect;return n.shadowRoot.activeElement===n.shadowRoot.querySelector('.panel-trigger');"), 'keyboard focus returns to the select'
            print('PASS keyboard opening, selection and focus return for normal/private engines', flush=True)


if __name__ == '__main__':
    main()
