"""New public identity with the existing browser/profile compatibility IDs."""
import os
import plistlib
from pathlib import Path
import runtime


def main():
    os.environ['MOZ_HEADLESS'] = '1'
    info = plistlib.loads((runtime.APP/'Contents/Info.plist').read_bytes())
    assert info['CFBundleName'] == info['CFBundleDisplayName'] == 'GrayFox', info['CFBundleName']
    assert info['CFBundleIdentifier'] == 'org.mybro.firefox'
    assert (runtime.APP/'Contents/Resources'/info['CFBundleIconFile']).read_bytes() == (runtime.ROOT/'Firefox/branding/GrayFox.icns').read_bytes()
    with runtime.Firefox() as f:
        f.wait('window.myBro?.ready')
        state = f.js("return {name:Services.appinfo.name,profileRoot:Services.dirsvc.get('DefProfRt',Ci.nsIFile).path,profile:Services.dirsvc.get('ProfD',Ci.nsIFile).path};")
        assert state['name'] == 'GrayFox', state
        assert state['profileRoot'] == str(Path.home()/'Library/Application Support/myBro Firefox/Profiles'), state
        assert state['profile'] == str(f.profile), state
        f.wait("gBrowser.selectedBrowser.contentDocument?.querySelector('h1')?.textContent==='GrayFox'")
        print('PASS public GrayFox identity, generated macOS icon, existing profile root and start-page title', flush=True)


if __name__ == '__main__':
    main()
