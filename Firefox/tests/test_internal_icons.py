"""Search control and real tab favicons, with an isolated Gecko profile."""
import os
from runtime import Firefox


def main():
    os.environ['MOZ_HEADLESS'] = '1'
    icons = {
        'settings': 'chrome://global/skin/icons/settings.svg',
        'bookmarks': 'chrome://global/skin/icons/folder.svg',
        'downloads': 'chrome://browser/skin/downloads/downloads.svg',
        'history': 'chrome://browser/skin/history.svg',
        'passwords': 'chrome://browser/skin/login.svg',
    }
    with Firefox() as f:
        profile = f.profile
        f.wait('window.myBro?.ready')
        f.js("Services.prefs.setIntPref('browser.startup.page',3);")
        f.wait("gBrowser.selectedBrowser.contentDocument?.querySelector('.search button')")
        search = f.js("const b=gBrowser.selectedBrowser.contentDocument.querySelector('.search button'),i=b.querySelector('.search-icon');return {text:b.textContent,name:b.getAttribute('aria-label'),width:i&&getComputedStyle(i).width,mask:i&&getComputedStyle(i).maskImage};")
        assert search['text'] == '' and search['name'] == 'Поиск', search
        assert search['width'] == '20px' and 'search-glass.svg' in search['mask'], search
        print('PASS accessible vector magnifier at 20px', flush=True)
        for view, icon in icons.items():
            if view == 'passwords':
                f.js("myBro.nativePage('about:logins');")
                url = 'about:logins'
            else:
                f.js('myBro.openManager(arguments[0]);', [view])
                url = 'about:preferences#grayfox' if view == 'settings' else 'about:mybro?view=' + view
            f.wait('gBrowser.currentURI.spec.startsWith(' + repr(url) + ')')
            f.wait('gBrowser.selectedTab.getAttribute("image")===' + repr(icon))
            f.wait('getComputedStyle(gBrowser.selectedTab.querySelector(".tab-icon-image")).filter==="none"')
            f.js('BrowserCommands.reload();')
            f.wait('!gBrowser.selectedTab.hasAttribute("busy")')
            f.wait('gBrowser.selectedTab.getAttribute("image")===' + repr(icon))
            print('PASS ' + view + ' tab icon after navigation and reload', flush=True)
        for theme, color in [('light', 'rgb(32, 32, 32)'), ('dark', 'rgb(238, 238, 238)')]:
            f.js("myBro.write('theme',arguments[0]);", [theme])
            f.wait('getComputedStyle(gBrowser.selectedTab.querySelector(".tab-icon-image")).fill===' + repr(color))
        print('PASS section icons follow light and dark theme colors', flush=True)
        f.js("window.webTab=gBrowser.addTrustedTab('about:blank',{inBackground:true});gBrowser.setIcon(webTab,'chrome://browser/content/mybro/AppIcon.png');myBro.refresh();")
        assert f.js("return !webTab.hasAttribute('mybro-page-icon')&&webTab.getAttribute('image').endsWith('/AppIcon.png');")
        print('PASS unrelated tab icon preserved', flush=True)
    with Firefox(profile) as f:
        f.wait('window.myBro?.ready')
        for icon in icons.values():
            f.wait('Array.from(gBrowser.tabs).some(t=>t.getAttribute("image")===' + repr(icon) + ')')
        print('PASS section icons restored without activating background tabs', flush=True)


if __name__ == '__main__':
    main()
