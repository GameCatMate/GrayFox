"""Compact native password UI and CRUD, using disposable synthetic logins only."""
import base64
import os
import time
from runtime import Firefox, ROOT


def main():
    os.environ['MOZ_HEADLESS'] = '1'
    with Firefox() as f:
        f.wait('window.myBro?.ready')
        fixtures = [dict(origin=f'https://site-{i:02}.example.invalid',
                         username=f'user-{i}@example.invalid', password='synthetic-password')
                    for i in range(30)]
        fixtures.append(dict(origin='https://' + 'long-subdomain.' * 5 + 'special.example.invalid:8443',
                             username='long-username-' * 12 + '@example.invalid', password='synthetic-password'))
        count = f.async_js("const done=arguments[arguments.length-1];ChromeUtils.importESModule('chrome://browser/content/mybro/library.sys.mjs').importPasswords(arguments[0]).then(done);", [fixtures])
        assert count == 31
        # Only this disposable test profile skips OS prompts; the shipped pref is untouched.
        f.js("Services.prefs.setBoolPref('signon.management.page.os-auth.enabled',false);myBro.nativePage('about:logins');")
        f.wait("gBrowser.currentURI.spec.startsWith('about:logins')")
        f.command('Marionette:SetContext', {'value':'content'})
        f.command('WebDriver:SwitchToWindow', {'handle':f.command('WebDriver:GetWindowHandles')[-1]})
        f.wait("document.querySelector('login-list')?.shadowRoot?.querySelector('[data-guid]')?.shadowRoot")
        f.js("window.testList=document.querySelector('login-list').shadowRoot;window.testItem=document.querySelector('login-item').shadowRoot;window.testFilter=testList.querySelector('login-filter').shadowRoot.querySelector('input');testFilter.value='special';testFilter.dispatchEvent(new Event('input',{bubbles:true,composed:true}));")
        f.wait("[...testList.querySelectorAll('[data-guid]')].filter(n=>!n.hidden).length===1")
        f.js("[...testList.querySelectorAll('[data-guid]')].find(n=>!n.hidden).click();")
        f.wait("testItem.querySelector('input[name=username]').value.startsWith('long-username-')")

        for width in (1280, 800, 480):
            f.command('Marionette:SetContext', {'value':'chrome'})
            f.js('window.resizeTo(arguments[0],850);', [width])
            time.sleep(.3)
            f.command('Marionette:SetContext', {'value':'content'})
            geometry = f.js("""const r=n=>{const v=n.getBoundingClientRect();return {x:v.x,y:v.y,w:v.width,h:v.height,right:v.right};};
              const row=[...testList.querySelectorAll('[data-guid]')].find(n=>!n.hidden).shadowRoot.querySelector('list-item').shadowRoot.querySelector('li');
              return {viewport:innerWidth,scroll:document.documentElement.scrollWidth,row:r(row),
                list:r(document.querySelector('login-list')),item:r(document.querySelector('login-item')),
                grid:r(testItem.querySelector('.detail-grid')),formScroll:testItem.querySelector('form').scrollWidth,
                form:r(testItem.querySelector('form')),sync:getComputedStyle(document.querySelector('fxaccounts-button')).display};""")
            assert geometry['scroll'] <= geometry['viewport'], geometry
            assert geometry['row']['h'] <= 40, geometry
            assert geometry['grid']['w'] <= 560, geometry
            assert geometry['formScroll'] <= geometry['form']['w'] + 1, geometry
            assert geometry['item']['right'] <= geometry['viewport'] and geometry['item']['w'] > 200, geometry
            assert geometry['sync'] == 'none', geometry
            if width > 540:
                assert geometry['item']['x'] >= geometry['list']['right'], geometry
            else:
                assert geometry['item']['y'] > geometry['list']['y'], geometry
            f.command('Marionette:SetContext', {'value':'chrome'})
            shot = f.command('WebDriver:TakeScreenshot', {'full':False})
            data = shot.get('value',shot) if isinstance(shot,dict) else shot
            (ROOT/f'.build/firefox/password-layout-{width}.png').write_bytes(base64.b64decode(data))
            f.command('Marionette:SetContext', {'value':'content'})
            print(f'PASS compact password layout at {width}px with long URL/username', flush=True)

        f.js("testItem.querySelector('edit-button').shadowRoot.querySelector('button').click();")
        f.wait("document.querySelector('login-item').hasAttribute('data-editing')")
        f.js("const input=testItem.querySelector('input[name=username]');input.value='edited@example.invalid';input.dispatchEvent(new Event('input',{bubbles:true}));testItem.querySelector('.save-changes-button').click();")
        f.wait("!document.querySelector('login-item').hasAttribute('data-editing')&&testItem.querySelector('input[name=username]').value==='edited@example.invalid'")
        print('PASS native editing and saving from narrow layout', flush=True)
        f.js("testList.querySelector('create-login-button').shadowRoot.querySelector('button').click();")
        f.wait("document.querySelector('login-item').hasAttribute('data-is-new-login')")
        f.js("for(const [name,value] of Object.entries({origin:'https://created.example.invalid',username:'created-user',password:'synthetic-new-password'})){const field=testItem.querySelector('input[name='+name+']');field.value=value;field.dispatchEvent(new Event('input',{bubbles:true}));}testItem.querySelector('.save-changes-button').click();")
        f.wait("!document.querySelector('login-item').hasAttribute('data-is-new-login')&&testItem.querySelector('input[name=username]').value==='created-user'")
        f.js("testItem.querySelector('delete-button').shadowRoot.querySelector('button').click();")
        f.wait("!document.querySelector('confirmation-dialog').hidden")
        f.js("document.querySelector('confirmation-dialog').shadowRoot.querySelector('.confirm-button').click();")
        f.wait("testList.querySelectorAll('login-list-item[data-guid]').length===31")
        f.command('Marionette:SetContext', {'value':'chrome'})
        stored = f.async_js("const done=arguments[arguments.length-1];Services.logins.getAllLogins().then(logins=>done({count:logins.length,edited:logins.some(l=>l.username==='edited@example.invalid'),created:logins.some(l=>l.origin==='https://created.example.invalid')}));")
        assert stored == dict(count=31, edited=True, created=False), stored
        print('PASS native creation, confirmation and deletion; edited login persisted', flush=True)


if __name__ == '__main__':
    main()
