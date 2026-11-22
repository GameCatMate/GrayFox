"""Native settings toggles remain visible and save their state in both themes."""
import re
import time
from runtime import Firefox


def color(value):
    values=[float(x) for x in re.findall(r'[\d.]+',value)]
    assert len(values)==3 or values[3]==1, 'transparent switch color: '+value
    return values[:3]


def luminance(rgb):
    linear=[v/255/12.92 if v/255<=.04045 else ((v/255+.055)/1.055)**2.4 for v in rgb]
    return sum(a*b for a,b in zip(linear,[.2126,.7152,.0722]))


def main():
    with Firefox() as f:
        f.wait('window.myBro?.ready')
        f.js("myBro.nativePage('about:preferences#home');")
        f.wait("gBrowser.selectedBrowser.contentDocument?.querySelector('#webSearch')?.shadowRoot?.querySelector('button')")
        for theme in ['dark','light']:
            f.js("myBro.write('theme',arguments[0]);",[theme])
            backgrounds=[]
            for pressed in [True,False]:
                f.js("const t=gBrowser.selectedBrowser.contentDocument.querySelector('#webSearch');if(t.pressed!==arguments[0])t.shadowRoot.querySelector('button').click();",[pressed])
                f.wait("Services.prefs.getBoolPref('browser.newtabpage.activity-stream.showSearch')==="+str(pressed).lower())
                time.sleep(.15)
                styles=f.js("const w=gBrowser.selectedBrowser.contentWindow,t=w.document.querySelector('#webSearch'),b=t.shadowRoot.querySelector('button'),s=w.getComputedStyle(b),p=w.getComputedStyle(b,'::before');return {track:s.backgroundColor,dot:p.backgroundColor,width:parseFloat(p.width),height:parseFloat(p.height),translate:p.translate,pressed:b.getAttribute('aria-pressed')};")
                track,dot=color(styles['track']),color(styles['dot'])
                lum=sorted([luminance(track),luminance(dot)])
                assert (lum[1]+.05)/(lum[0]+.05)>=3, styles
                assert styles['width']>0 and styles['height']>0 and styles['pressed']==str(pressed).lower(),styles
                assert (styles['translate']!='0px')==pressed,styles
                backgrounds.append(styles['track'])
            assert backgrounds[0]!=backgrounds[1], backgrounds
            print('PASS '+theme+' toggles have visible knobs, distinct tracks and persist changes',flush=True)


if __name__=='__main__':
    main()
