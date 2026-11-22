"""The existing application menu must open the same sections as GrayFox navigation."""
import os
from runtime import Firefox


def main():
    os.environ['MOZ_HEADLESS'] = '1'
    routes = {
        'history': 'about:mybro?view=history',
        'bookmarks': 'about:mybro?view=bookmarks',
        'downloads': 'about:mybro?view=downloads',
        'passwords': 'about:logins',
        'extensions-themes': 'about:addons',
        'settings': 'about:preferences#grayfox',
    }
    with Firefox() as f:
        f.wait('window.myBro?.ready')
        for item, url in routes.items():
            f.js('PanelUI.show();')
            f.wait("document.getElementById('appMenu-popup').state==='open'")
            if item == 'history':
                assert f.js("return document.getElementById('appMenu-history-button').label;") == 'История браузера'
            f.js('document.getElementById(arguments[0]).click();', ['appMenu-' + item + '-button'])
            f.wait('gBrowser.currentURI.spec===' + repr(url))
            f.wait("document.getElementById('appMenu-popup').state==='closed'")
            assert f.js("return Array.from(Services.wm.getEnumerator('navigator:browser')).length;") == 1
            print('PASS application menu routes ' + item + ' to ' + url, flush=True)
        f.js("document.getElementById('Tools:Downloads').doCommand();")
        f.wait("gBrowser.currentURI.spec==='about:mybro?view=downloads'")
        print('PASS download command uses GrayFox downloads', flush=True)


if __name__ == '__main__':
    main()
