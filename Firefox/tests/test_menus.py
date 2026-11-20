"""Native menu activation and favicon spacing on a disposable profile."""
import base64
import time
from runtime import Firefox, ROOT
from test_runtime import check


def tab_menu(f):
    f.js("const t=window.menuTestTab,r=t.getBoundingClientRect();t.dispatchEvent(new MouseEvent('contextmenu',{bubbles:true,cancelable:true,screenX:window.screenX+r.x+20,screenY:window.screenY+r.y+30}));return true;")
    f.wait("document.getElementById('mybro-tab-context').state==='open'")


def activate(f, popup, label):
    f.js("const p=document.getElementById(arguments[0]),item=[...p.children].find(n=>n.getAttribute('label')===arguments[1]);if(!item||item.disabled)throw Error('Unavailable: '+arguments[1]);p.activateItem(item);return true;",[popup,label])
    f.wait("document.getElementById("+repr(popup)+").state==='closed'")


def main():
    with Firefox() as f:
        f.wait('window.myBro?.ready')
        f.js("myBro.write('theme','dark');const initial=[...gBrowser.tabs];window.menuTestTab=myBro.newTab();for(const t of initial)gBrowser.removeTab(t,{animate:false});menuTestTab.label='Example title';gBrowser.setIcon(menuTestTab,'chrome://browser/content/mybro/AppIcon.png');myBro.newTab();myBro.newTab();gBrowser.selectedTab=menuTestTab;return true;")
        time.sleep(.3)
        tab_menu(f)
        check(f.js("const p=document.getElementById('mybro-tab-context');return [...p.children].filter(n=>['Новая вкладка','Обновить','Дублировать','Закрепить вкладку','Отключить звук на вкладке','Закрыть вкладку','Закрыть другие вкладки','Закрыть вкладки справа','Настройки'].includes(n.getAttribute('label'))).every(n=>!n.disabled);"),
              'available tab commands are enabled in the native menu')
        check(f.js("return [...document.getElementById('mybro-tab-context').children].find(n=>n.getAttribute('label')==='Закрыть вкладки слева').disabled;"),
              'closing tabs on an empty side stays disabled')
        activate(f,'mybro-tab-context','Дублировать')
        f.wait('gBrowser.tabs.length===4')
        check(True,'native menu activation duplicates a tab')
        f.js('window.menuTestTab=gBrowser.selectedTab;return true;')
        tab_menu(f);activate(f,'mybro-tab-context','Закрепить вкладку')
        f.wait('menuTestTab.pinned')
        tab_menu(f);activate(f,'mybro-tab-context','Открепить вкладку')
        f.wait('!menuTestTab.pinned')
        check(True,'pin and unpin actions work through the menu')
        tab_menu(f);activate(f,'mybro-tab-context','Отключить звук на вкладке')
        f.wait('menuTestTab.linkedBrowser.audioMuted')
        tab_menu(f);activate(f,'mybro-tab-context','Включить звук на вкладке')
        f.wait('!menuTestTab.linkedBrowser.audioMuted')
        check(True,'mute and unmute actions work through the menu')
        tab_menu(f);activate(f,'mybro-tab-context','Закрыть вкладку')
        f.wait('gBrowser.tabs.length===3')
        f.js('window.menuTestTab=gBrowser.selectedTab;return true;')
        tab_menu(f);activate(f,'mybro-tab-context','Открыть закрытую вкладку')
        f.wait('gBrowser.tabs.length===4')
        check(True,'close and reopen actions work through the menu')
        f.js("PanelUI.show();return true;")
        f.wait("document.getElementById('appMenu-popup').state==='open'")
        check(f.js("return !document.getElementById('mybro-menu');"),
              'the native application panel opens without a duplicate myBro menu')
        f.js("PanelUI.hide();return true;")
        f.wait("document.getElementById('appMenu-popup').state==='closed'")
        f.js("myBro.write('groups',[{id:'a',name:'Alpha',color:'blue'},{id:'b',name:'Beta',color:'green'}]);myBro.selectGroup('a');return true;")
        time.sleep(.2)
        f.js("document.getElementById('mybro-group-menu').click();return true;")
        f.wait("document.getElementById('mybro-groups-popup').state==='open'")
        activate(f,'mybro-groups-popup','Beta')
        f.wait("myBro.current==='b'")
        check(True,'group dropdown selection is enabled and switches groups')
        f.js("menuTestTab=gBrowser.selectedTab;menuTestTab.label='Example title';gBrowser.setIcon(menuTestTab,'chrome://browser/content/mybro/AppIcon.png');return true;")
        time.sleep(.2)
        check(f.js("const t=menuTestTab,icon=t.querySelector('.tab-icon-stack').getBoundingClientRect(),text=t.querySelector('.tab-label-container').getBoundingClientRect();return text.left-icon.right>=8;"),
              'normal-width tabs separate the title and favicon by 8px')
        element=f.command('WebDriver:FindElement',{'using':'css selector','value':'#tabbrowser-tabs'})
        value=element.get('value',element)
        shot=f.command('WebDriver:TakeScreenshot',{'id':next(iter(value.values())),'full':False})
        (ROOT/'.build/firefox/tab-spacing.png').write_bytes(base64.b64decode(shot.get('value',shot)))


if __name__=='__main__':
    main()
