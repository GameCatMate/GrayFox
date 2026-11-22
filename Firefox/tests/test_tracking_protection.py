"""The Off level changes actual ETP preferences and survives a restart."""
from runtime import Firefox


def open_levels(f):
    f.js("myBro.nativePage('about:preferences#etp');")
    f.wait("gBrowser.selectedBrowser.contentDocument?.querySelector('#contentBlockingCategoryRadioGroup')")


def choose(f, level):
    f.js("const n=gBrowser.selectedBrowser.contentDocument.getElementById(arguments[0]);if(n.disabled)throw Error('Level disabled');n.shadowRoot.querySelector('input').click();", ['etpLevel'+level.capitalize()])
    f.wait("gBrowser.selectedBrowser.contentDocument.querySelector('#contentBlockingCategoryRadioGroup').value==="+repr(level))


def main():
    with Firefox() as f:
        profile=f.profile
        f.wait('window.myBro?.ready');open_levels(f)
        assert f.js("return !!gBrowser.selectedBrowser.contentDocument.getElementById('etpLevelOff');"), 'Off level is missing'
        f.js("window.etpOriginal=Services.prefs.getBoolPref('browser.safebrowsing.malware.enabled');")
        choose(f,'off')
        assert f.js("return !Services.prefs.getBoolPref('privacy.trackingprotection.enabled')&&!Services.prefs.getBoolPref('privacy.trackingprotection.pbmode.enabled')&&!Services.prefs.getBoolPref('privacy.trackingprotection.fingerprinting.enabled')&&!Services.prefs.getBoolPref('privacy.fingerprintingProtection.pbmode')&&Services.prefs.getIntPref('network.cookie.cookieBehavior')===0&&Services.prefs.getIntPref('network.cookie.cookieBehavior.pbmode')===0&&Services.prefs.getStringPref('browser.contentblocking.category')==='custom';")
        assert f.js("return Services.prefs.getBoolPref('browser.safebrowsing.malware.enabled')===etpOriginal;")
        f.js("gBrowser.selectedBrowser.contentWindow.gotoPref('panePrivacy');")
        f.wait("gBrowser.selectedBrowser.contentDocument.querySelector('#etpStatusItem')?.getAttribute('label')==='Отключена'")
        f.wait("gBrowser.selectedBrowser.contentDocument.querySelector('security-privacy-card')?.shadowRoot?.textContent.includes('Защита от отслеживания отключена')")
        print('PASS Off disables tracking and cookie blocking in normal/private modes and updates the summary',flush=True)
    with Firefox(profile) as f:
        f.wait('window.myBro?.ready');open_levels(f)
        f.wait("gBrowser.selectedBrowser.contentDocument.querySelector('#contentBlockingCategoryRadioGroup').value==='off'")
        choose(f,'standard')
        assert f.js("return Services.prefs.getBoolPref('privacy.trackingprotection.pbmode.enabled')&&Services.prefs.getIntPref('network.cookie.cookieBehavior')!==0;")
        choose(f,'off');choose(f,'strict')
        assert f.js("return Services.prefs.getBoolPref('privacy.trackingprotection.enabled');")
        choose(f,'custom')
        f.js("Services.prefs.setBoolPref('privacy.trackingprotection.cryptomining.enabled',false);")
        expected=f.js("return {tracking:Services.prefs.getBoolPref('privacy.trackingprotection.enabled'),crypto:Services.prefs.getBoolPref('privacy.trackingprotection.cryptomining.enabled'),cookies:Services.prefs.getIntPref('network.cookie.cookieBehavior')};")
        choose(f,'off');choose(f,'custom')
        assert f.js("return {tracking:Services.prefs.getBoolPref('privacy.trackingprotection.enabled'),crypto:Services.prefs.getBoolPref('privacy.trackingprotection.cryptomining.enabled'),cookies:Services.prefs.getIntPref('network.cookie.cookieBehavior')};")==expected
        print('PASS Off persists, standard/strict re-enable ETP, and custom restores previous choices',flush=True)
        choose(f,'standard')
        f.js("Services.prefs.lockPref('privacy.trackingprotection.enabled');")
        f.wait("gBrowser.selectedBrowser.contentDocument.getElementById('etpLevelOff').disabled")
        assert f.js("try{ChromeUtils.importESModule('chrome://browser/content/mybro/tracking-protection.sys.mjs').TrackingProtection.select('off');return false;}catch{return Services.prefs.getStringPref('browser.contentblocking.category')==='standard';}")
        f.js("Services.prefs.unlockPref('privacy.trackingprotection.enabled');")
        print('PASS a locked ETP preference prevents partial disabling',flush=True)
        choose(f,'off')
        f.js("Services.prefs.setStringPref('mybro.etpPreviousPreferences','invalid JSON');")
        choose(f,'custom')
        assert f.js("return Services.prefs.getBoolPref('privacy.trackingprotection.pbmode.enabled')&&Services.prefs.getIntPref('network.cookie.cookieBehavior')!==0;")
        print('PASS a damaged saved configuration restores native defaults',flush=True)


if __name__=='__main__':
    main()
