"""Overflow geometry, overlay hit targets and the shipped macOS icon."""
import base64
import plistlib
import time
from runtime import Firefox, ROOT, APP


def main():
    failures = []

    def check(ok, label):
        print(('PASS ' if ok else 'FAIL ') + label, flush=True)
        if not ok:
            failures.append(label)

    info = plistlib.loads((APP / 'Contents/Info.plist').read_bytes())
    icon = (ROOT / 'Firefox/branding/GrayFox.icns').read_bytes()
    check('CFBundleIconName' not in info and
          (APP / 'Contents/Resources' / info['CFBundleIconFile']).read_bytes() == icon and
          (APP / 'Contents/Resources/firefox.icns').read_bytes() == icon,
          'macOS and runtime icon both use Bro')

    with Firefox() as f:
        f.wait('window.myBro?.ready')
        f.js("""window.resizeTo(1320,850);myBro.write('theme','dark');
          myBro.write('groups',[{id:'a',name:'My',color:'red'},{id:'b',name:'VPS',color:'orange'},
            {id:'c',name:'SRV',color:'blue'},{id:'d',name:'GM',color:'green'}]);
          for(let i=0;i<53;i++){
            const tab=gBrowser.addTrustedTab('about:blank',{inBackground:true});
            myBro.setGroup(tab,'a');tab.label='Example '+i;
            gBrowser.setIcon(tab,'chrome://browser/content/mybro/AppIcon.png');
          }
          myBro.selectGroup('a');window.strip=document.getElementById('tabbrowser-arrowscrollbox');
          window.stripMetrics=()=>{
            const rect=n=>{const r=n.getBoundingClientRect();return {x:r.x,y:r.y,w:r.width,h:r.height};};
            const toolbar=rect(document.getElementById('TabsToolbar')),viewport=rect(strip);
            const arrows=['scrollbutton-up','scrollbutton-down'].map(id=>{
              const node=strip.shadowRoot.getElementById(id),r=rect(node),style=getComputedStyle(node);
              const covers=[r.y+1,r.y+r.h-1].every(y=>
                strip.shadowRoot.elementFromPoint(r.x+r.w/2,y)?.closest('toolbarbutton')===node);
              return {...r,opacity:+style.opacity,background:style.backgroundColor,covers};
            });
            const tabs=myBro.visible().map(t=>({tab:rect(t),background:rect(t.querySelector('.tab-background')),
              icon:rect(t.querySelector('.tab-icon-stack'))}));
            return {toolbar,viewport,arrows,tabs,scroll:strip.scrollbox.scrollLeft};
          };return true;""")
        f.wait('strip.hasAttribute("overflowing")')
        time.sleep(.4)
        initial = f.js('return stripMetrics();')
        check(all(abs(t['tab']['y']-initial['toolbar']['y'])<.5 and t['tab']['h']==36 and
                  t['background']['h']==30 and t['icon']['h']==16 for t in initial['tabs']),
              '53 compact tabs and favicons stay inside the 36px row')
        widths = []
        for position, expected in [('start',[0,1]),('middle',[1,1]),('end',[1,0]),('start',[0,1])]:
            # Native selection restoration may otherwise scroll a selected offscreen tab back into view.
            f.js("const members=myBro.visible(),place=arguments[0];gBrowser.selectedTab=members[place==='end'?members.length-1:place==='middle'?Math.floor(members.length/2):0];const max=strip.scrollbox.scrollWidth-strip.scrollbox.clientWidth;strip.scrollbox.scrollTo({left:place==='end'?strip.scrollbox.scrollWidth:place==='middle'?max/2:0,behavior:'instant'});return true;",[position])
            f.wait("stripMetrics().arrows.map(a=>a.opacity).join(',')==='"+','.join(map(str,expected))+"'",seconds=3)
            m = f.js('return stripMetrics();')
            widths.append((m['viewport']['x'],m['viewport']['w']))
            check([a['opacity'] for a in m['arrows']]==expected,position+' arrow visibility')
            check(all(a['h']==m['toolbar']['h'] and abs(a['y']-m['toolbar']['y'])<.5 and
                      a['background']=='rgb(31, 31, 31)' and a['covers']
                      for a in m['arrows'] if a['opacity']==1),
                  position+' arrows cover and intercept the full row height')
            if position=='middle':
                shot=f.command('WebDriver:TakeScreenshot',{'full':False})
                (ROOT/'.build/firefox/overflow-verified.png').write_bytes(base64.b64decode(shot.get('value',shot) if isinstance(shot,dict) else shot))
        check(len(set(widths))==1,'edge fades never resize or move the tab viewport')
        f.js('for(const tab of myBro.visible().slice(13))gBrowser.removeTab(tab,{animate:false});return true;')
        time.sleep(.4)
        medium=f.js('return stripMetrics();')
        check(24<medium['tabs'][0]['tab']['w']<158 and all(a['opacity']==0 for a in medium['arrows']),
              'tabs widen gradually when fewer tabs fit without scrolling')
        f.js('for(const tab of myBro.visible().slice(3))gBrowser.removeTab(tab,{animate:false});return true;')
        time.sleep(.4)
        check(f.js('return stripMetrics().tabs.every(t=>t.tab.w===158&&t.tab.h===36);'),
              'few tabs keep the same height at their normal width')
        f.js("for(const tab of myBro.visible())tab.linkedBrowser.loadURI(Services.io.newURI('about:mybro?view=history'),{triggeringPrincipal:Services.scriptSecurityManager.getSystemPrincipal()});return true;")
        f.wait("myBro.visible().every(t=>t.linkedBrowser.contentDocument?.documentElement?.dataset.ready==='true')")
        point=f.js("window.closedLeft=myBro.visible()[0];window.following=myBro.visible()[1];gBrowser.selectedTab=closedLeft;window.closedLeftX=closedLeft.getBoundingClientRect().x;const r=closedLeft.getBoundingClientRect();return {x:r.x+r.width/2,y:r.y+r.height/2};")
        f.command('WebDriver:PerformActions',{'actions':[{'type':'pointer','id':'mouse','parameters':{'pointerType':'mouse'},'actions':[{'type':'pointerMove','x':round(point['x']),'y':round(point['y']),'duration':0}]}]})
        f.wait('closedLeft.matches(":hover")')
        point=f.js("const r=closedLeft.querySelector('.tab-close-button').getBoundingClientRect();return {x:r.x+r.width/2,y:r.y+r.height/2};")
        f.command('WebDriver:PerformActions',{'actions':[{'type':'pointer','id':'mouse','parameters':{'pointerType':'mouse'},'actions':[{'type':'pointerMove','x':round(point['x']),'y':round(point['y']),'duration':0},{'type':'pointerDown','button':0},{'type':'pointerUp','button':0}]}]})
        f.command('WebDriver:ReleaseActions')
        time.sleep(.5)
        packed=f.js('return !closedLeft.isConnected&&Math.abs(following.getBoundingClientRect().x-closedLeftX)<.5;')
        check(packed,'closing the left tab by its X removes it and shifts its neighbour left')
        if packed:
            f.js("window.contextTarget=myBro.visible().at(-1);gBrowser.selectedTab=contextTarget;const r=contextTarget.getBoundingClientRect();contextTarget.dispatchEvent(new MouseEvent('contextmenu',{bubbles:true,cancelable:true,screenX:window.screenX+r.x+20,screenY:window.screenY+r.y+30}));return true;")
            f.wait("document.getElementById('mybro-tab-context').state==='open'")
            f.js("const p=document.getElementById('mybro-tab-context');p.activateItem([...p.children].find(n=>n.getAttribute('label')==='Закрыть вкладки слева'));return true;")
            f.wait('myBro.visible().length===1')
            time.sleep(.3)
            check(f.js('return Math.abs(contextTarget.getBoundingClientRect().x-strip.getBoundingClientRect().x)<.5;'),
                  'closing tabs on the left through the menu leaves no gap')
            f.js('myBro.reopenClosed();return true;');f.wait('myBro.visible().length===2')
            time.sleep(.3)
            f.js("myBro.selectGroup('b');myBro.selectGroup('a');return true;");time.sleep(.3)
            check(f.js('const tabs=myBro.visible(),a=tabs[0].getBoundingClientRect(),b=tabs[1].getBoundingClientRect();return Math.abs(a.x-strip.getBoundingClientRect().x)<.5&&Math.abs(b.x-a.right)<.5;'),
                  'reopening and changing groups keep tabs packed without phantom slots')
    assert not failures, '; '.join(failures)


if __name__=='__main__':
    main()
