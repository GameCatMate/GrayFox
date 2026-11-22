"""Render shared browser branding through Gecko, without using a real profile."""
import base64
import hashlib
import os
import time
from runtime import Firefox, ROOT


def main():
    os.environ['MOZ_HEADLESS'] = '1'
    with Firefox() as f:
        f.wait('window.myBro?.ready')
        digest = f.async_js("const done=arguments[arguments.length-1];fetch('chrome://browser/content/mybro/AppIcon.png').then(r=>r.arrayBuffer()).then(b=>crypto.subtle.digest('SHA-256',b)).then(b=>done([...new Uint8Array(b)].map(n=>n.toString(16).padStart(2,'0')).join('')));")
        assert digest == hashlib.sha256((ROOT/'Firefox/branding/GrayFox.png').read_bytes()).hexdigest()
        resources = ['chrome://branding/content/icon16.png', 'chrome://branding/content/icon32.png',
                     'chrome://branding/content/icon48.png', 'chrome://branding/content/icon64.png',
                     'chrome://branding/content/icon128.png', 'chrome://branding/content/about-logo.png',
                     'chrome://branding/content/about-logo@2x.png', 'chrome://branding/content/about-logo-private.png',
                     'chrome://branding/content/about-logo.svg', 'chrome://browser/skin/sidebar/firefox.svg',
                     'chrome://browser/skin/window-firefox.svg', 'chrome://browser/content/logos/share-firefox.svg']
        rendered = f.async_js("""const done=arguments[arguments.length-1];(async()=>{
          const results=[],reference=new Image();reference.src='chrome://browser/content/mybro/AppIcon.png';await reference.decode();
          const canvas=document.createElementNS('http://www.w3.org/1999/xhtml','canvas');canvas.width=16;canvas.height=16;
          const context=canvas.getContext('2d');context.drawImage(reference,0,0,16,16);
          const expected=context.getImageData(0,0,16,16).data;
          for(const url of arguments[0]) {
            const image=new Image();image.src=url;await image.decode();
            context.clearRect(0,0,16,16);context.drawImage(image,0,0,16,16);
            const actual=context.getImageData(0,0,16,16).data;
            results.push({url,difference:actual.reduce((sum,n,i)=>sum+Math.abs(n-expected[i]),0)/actual.length});
          }
          return results;
        })().then(done).catch(error=>done({error:String(error)}));""", [resources])
        assert isinstance(rendered,list), rendered
        for result in rendered:
            assert result['difference'] < 20, result
        print('PASS native shared PNG/SVG icons render the generated GrayFox logo', flush=True)
        for name in ['about-wordmark.svg', 'firefox-wordmark.svg']:
            text = f.async_js("const done=arguments[arguments.length-1];fetch('chrome://branding/content/'+arguments[0]).then(r=>r.text()).then(done);", [name])
            assert '>GrayFox<' in text and '>Firefox<' not in text, name
        print('PASS internal wordmarks use GrayFox', flush=True)
        f.js("myBro.nativePage('about:preferences#home');")
        f.wait("gBrowser.selectedBrowser.contentWindow?.createDefaultBrowserConfig")
        assert f.js("return gBrowser.selectedBrowser.contentWindow.createDefaultBrowserConfig().items.every(n=>n.controlAttrs.imagesrc==='chrome://browser/content/mybro/AppIcon.png'&&n.controlAttrs.imagedisplay==='padded');"), 'both default-browser states must use the GrayFox logo without cropping'
        f.wait("gBrowser.selectedBrowser.contentDocument.querySelector('#isDefaultPane,#isNotDefaultPane')?.shadowRoot?.querySelector('img')?.complete")
        print('PASS default-browser settings use GrayFox in both states', flush=True)
        # Capture inside the window while the native modal blocks WebDriver commands.
        f.js("""window.brandDialogResult=null;
          const shell=getShellService();shell.doesAppNeedPin=async()=>false;shell.doesAppNeedStartMenuPin=async()=>false;
          ChromeUtils.importESModule('moz-src:///browser/components/DefaultBrowserCheck.sys.mjs').DefaultBrowserCheck.prompt(window);
          setTimeout(()=>{
            const frames=[...document.querySelectorAll('browser,iframe')];
            const frame=frames.find(n=>n.contentDocument?.documentURI?.includes('commonDialog'));
            const d=frame?.contentDocument;
            const icons=d?[...d.querySelectorAll('*')].filter(n=>getComputedStyle(n).backgroundImage.includes('branding/content/icon')):[];
            window.brandDialogResult={loaded:!!d,icons:icons.length,screenshot:null,frames:frames.map(n=>n.contentDocument?.documentURI)};
            const canvas=document.createElementNS('http://www.w3.org/1999/xhtml','canvas');canvas.width=innerWidth;canvas.height=innerHeight;
            const context=canvas.getContext('2d');
            if(context.drawWindow){context.drawWindow(window,0,0,innerWidth,innerHeight,'rgb(255,255,255)');brandDialogResult.screenshot=canvas.toDataURL('image/png').split(',')[1];}
          },700);""")
        time.sleep(1)
        f.command('WebDriver:DismissAlert')
        dialog = f.js('return window.brandDialogResult;')
        assert dialog['loaded'] and dialog['icons'], {k:v for k,v in dialog.items() if k!='screenshot'}
        if dialog['screenshot']:
            (ROOT/'.build/firefox/branded-default-dialog.png').write_bytes(base64.b64decode(dialog['screenshot']))
        print('PASS native default-browser prompt uses the shared branded icon; dismissed without changing defaults', flush=True)


if __name__ == '__main__':
    main()
