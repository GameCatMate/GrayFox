"""Unified settings retain Gecko controls and unique GrayFox options."""
from runtime import Firefox


def main():
    with Firefox() as f:
        f.wait('window.myBro?.ready')
        f.js("myBro.openManager('settings');")
        f.wait("gBrowser.currentURI.spec.startsWith('about:preferences')")
        f.wait("gBrowser.selectedBrowser.contentDocument?.documentElement?.dataset.grayfoxReady==='true'")
        assert f.js("const d=gBrowser.selectedBrowser.contentDocument;return d.querySelectorAll('#navigation').length===1&&d.querySelectorAll('#grayfox-settings').length===1;")
        assert f.js("const d=gBrowser.selectedBrowser.contentDocument;return d.querySelector('#grayfox-settings-sidebar').contains(d.querySelector('#searchInput'));"), 'settings search belongs in the compact sidebar'
        assert f.js("const w=gBrowser.selectedBrowser.contentWindow;return [...w.document.querySelectorAll('.grayfox-card')].every(n=>w.getComputedStyle(n).backgroundColor==='rgba(0, 0, 0, 0)');"), 'settings use one surface instead of nested cards'
        for pane in ['Grayfox', 'Search', 'Privacy', 'PasswordsAutofill', 'Appearance', 'Downloads', 'TabsBrowsing', 'Accessibility', 'Languages', 'PermissionsData', 'Sync']:
            f.js("gBrowser.selectedBrowser.contentWindow.gotoPref(arguments[0]);", ['pane'+pane])
            f.wait("gBrowser.selectedBrowser.contentDocument.querySelector('[data-category=pane"+pane+"]:not([hidden])')")
            assert f.js("const d=gBrowser.selectedBrowser.contentDocument,b=[...d.querySelectorAll('#grayfox-settings-sidebar button[data-view]')];return new Set(b.map(n=>n.dataset.view)).size===b.length&&b.every(n=>n.textContent.trim());")
        print('PASS all native settings categories and a single GrayFox pane are reachable', flush=True)
        f.js("gBrowser.selectedBrowser.contentWindow.gotoPref('panePrivacy');")
        f.wait("gBrowser.selectedBrowser.contentDocument.querySelector('setting-pane[data-category=panePrivacy] moz-card')")
        assert f.js("const w=gBrowser.selectedBrowser.contentWindow;return [...w.document.querySelectorAll('setting-pane[data-category=panePrivacy] moz-card')].every(n=>w.getComputedStyle(n).borderTopWidth==='0px'&&w.getComputedStyle(n).boxShadow==='none');"), 'native settings cards have no decorative frames or shadows'
        f.js("gBrowser.selectedBrowser.contentWindow.gotoPref('paneGrayfox');")
        f.wait("gBrowser.selectedBrowser.contentDocument.querySelector('#grayfox-settings:not([hidden])')")
        f.js("gBrowser.selectedBrowser.contentDocument.querySelector('[data-grayfox-pref=startClock]').click();")
        assert f.js("return myBro.read('startClock',false);")
        f.js("const d=gBrowser.selectedBrowser.contentDocument;d.querySelector('[data-grayfox-pref=startClock]').click();")
        assert not f.js("return myBro.read('startClock',false);")
        assert f.js("const w=gBrowser.selectedBrowser.contentWindow;return [...w.document.querySelectorAll('.grayfox-setting')].every(n=>n.getBoundingClientRect().height<=40);")
        f.js("Services.prefs.lockPref('mybro.startClock');")
        f.wait("gBrowser.selectedBrowser.contentDocument.querySelector('[data-grayfox-pref=startClock]').disabled")
        f.js("Services.prefs.unlockPref('mybro.startClock');")
        f.js("const w=gBrowser.selectedBrowser.contentWindow;w.gSearchResultsPane.searchInput.value='Плитки закладок';w.gSearchResultsPane.searchInput.dispatchEvent(new w.Event('input',{bubbles:true}));")
        f.wait("gBrowser.selectedBrowser.contentDocument.querySelector('#grayfox-settings:not([hidden])')&&gBrowser.selectedBrowser.currentURI.spec.includes('searchResults')")
        print('PASS existing GrayFox preferences save and participate in native search', flush=True)
        f.js("gBrowser.selectedBrowser.contentWindow.gotoPref('paneConnectionSecurity');")
        f.wait("gBrowser.selectedBrowser.contentDocument.querySelector('#connectionSettings')")
        f.js("gBrowser.selectedBrowser.contentDocument.querySelector('#connectionSettings').click();")
        f.wait("gBrowser.selectedBrowser.contentWindow.gSubDialog._topDialog?._frame?.contentDocument?.documentURI.includes('connection.xhtml')")
        f.js("gBrowser.selectedBrowser.contentWindow.gSubDialog._topDialog.close();")
        print('PASS native proxy dialog opens within the unified settings', flush=True)
        f.js("const cps=Cc['@mozilla.org/content-pref/service;1'].getService(Ci.nsIContentPrefService2);cps.setGlobal('browser.content.full-zoom',1.1,Cu.createLoadContext());")
        f.wait("myBro.read('pageZoom',100)===110")
        print('PASS native default zoom and GrayFox reset zoom stay in sync', flush=True)
        f.js("gBrowser.selectedBrowser.contentWindow.gotoPref('paneGrayfox');")
        for width in [1600, 1000, 750, 480]:
            f.js('window.resizeTo(arguments[0],800);', [width])
            f.wait("gBrowser.selectedBrowser.contentDocument.documentElement.scrollWidth<=gBrowser.selectedBrowser.contentWindow.innerWidth+1")
        print('PASS unified settings fit wide and narrow windows', flush=True)
        count=f.js('return gBrowser.tabs.length;')
        f.js("myBro.openManager('settings');")
        assert f.js('return gBrowser.tabs.length;')==count
        print('PASS opening settings again reuses the existing tab', flush=True)
        f.js("gBrowser.selectedBrowser.loadURI(Services.io.newURI('about:mybro?view=settings'),{triggeringPrincipal:Services.scriptSecurityManager.getSystemPrincipal()});")
        f.wait("gBrowser.currentURI.spec==='about:preferences#grayfox'&&gBrowser.selectedBrowser.contentDocument?.documentElement?.dataset.grayfoxReady==='true'")
        print('PASS legacy settings URL opens the same unified page', flush=True)


if __name__ == '__main__':
    main()
