"""Sound indicators must fit beside favicons in crowded and pinned tabs."""
import os
import time
from runtime import Firefox


def main():
    os.environ['MOZ_HEADLESS'] = '1'
    with Firefox() as f:
        f.wait('window.myBro?.ready')
        f.js("window.resizeTo(950,650);for(let i=0;i<55;i++){const t=gBrowser.addTrustedTab('about:blank',{inBackground:true});gBrowser.setIcon(t,'chrome://browser/content/mybro/AppIcon.png');}window.audioTab=gBrowser.tabs[1];gBrowser.selectedTab=audioTab;")
        f.wait("Array.from(gBrowser.tabs).every(t=>!t.hasAttribute('busy'))")
        time.sleep(.3)
        baseline = f.js('return audioTab.getBoundingClientRect().width;')
        for pinned in (False, True):
            if pinned:
                f.js('gBrowser.pinTab(audioTab);')
            for state in ('soundplaying', 'muted', 'activemedia-blocked'):
                f.js("audioTab.setAttribute(arguments[0],'true');", [state])
                time.sleep(.15)
                geometry = f.js("const t=audioTab,r=n=>{const v=n.getBoundingClientRect();return {left:v.left,right:v.right,width:v.width};};return {tab:r(t),icon:r(t.querySelector('.tab-icon-image')),audio:r(t.audioButton),height:t.getBoundingClientRect().height};")
                assert geometry['tab']['width'] >= baseline + 20, geometry
                assert geometry['icon']['right'] + 3 <= geometry['audio']['left'], geometry
                assert geometry['icon']['left'] >= geometry['tab']['left'] and geometry['audio']['right'] <= geometry['tab']['right'], geometry
                assert geometry['audio']['width'] >= 16 and geometry['height'] == 36, geometry
                f.js('audioTab.removeAttribute(arguments[0]);', [state])
            print('PASS sound/mute/blocked icons fit ' + ('pinned' if pinned else 'crowded') + ' tabs', flush=True)
        f.js('gBrowser.unpinTab(audioTab);')
        f.wait('audioTab.getBoundingClientRect().width<=' + str(baseline + 1))
        print('PASS silent tab returns to its original compact width', flush=True)


if __name__ == '__main__':
    main()
