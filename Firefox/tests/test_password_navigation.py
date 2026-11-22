"""Real native password manager and shared chrome navigation, synthetic profile only."""
import base64
import os
from runtime import Firefox, ROOT


def main():
    os.environ['MOZ_HEADLESS'] = '1'
    with Firefox() as f:
        f.wait('window.myBro?.ready')
        result = f.async_js("const done=arguments[arguments.length-1];ChromeUtils.importESModule('chrome://browser/content/mybro/library.sys.mjs').importPasswords([{origin:'https://example.invalid',username:'synthetic-user',password:'synthetic-password'}]).then(count=>done(count));")
        assert result == 1
        f.js("myBro.nativePage('about:logins');return true;")
        f.wait("gBrowser.currentURI.spec.startsWith('about:logins')")
        assert f.js("return !!document.getElementById('mybro-passwords-navigation');"), 'Password manager must retain shared navigation'
        f.wait("!document.getElementById('mybro-passwords-navigation').hidden")
        state = f.js("const n=document.getElementById('mybro-passwords-navigation'),r=n.getBoundingClientRect(),b=document.getElementById('browser').getBoundingClientRect();return {labels:[...n.children].map(x=>x.textContent),active:n.querySelector('[aria-current=page]').textContent,height:r.height,above:r.bottom<=b.top+1};")
        assert state['labels'] == ['Мой профиль','Закладки','Загрузки','История','Пароли','Расширения','Настройки'], state
        assert state['active'] == 'Пароли' and state['height'] > 0 and state['above'], state
        print('PASS: Passwords section and shared navigation above native manager', flush=True)
        f.command('Marionette:SetContext', {'value':'content'})
        f.command('WebDriver:SwitchToWindow', {'handle':f.command('WebDriver:GetWindowHandles')[-1]})
        f.wait("document.querySelector('login-list')?.shadowRoot?.querySelector('[data-guid]')?.shadowRoot?.textContent.includes('example.invalid')")
        f.wait("document.querySelector('login-item')?.shadowRoot?.querySelector(\"input[name='username']\")?.value==='synthetic-user'")
        assert f.js("const r=document.querySelector('login-item').shadowRoot;return !!r.querySelector('edit-button')&&!!r.querySelector('delete-button')&&!!document.querySelector('login-list').shadowRoot.querySelector('create-login-button');")
        print('PASS: native saved login list and add/edit/delete controls are present', flush=True)
        f.command('Marionette:SetContext', {'value':'chrome'})
        screenshot = f.command('WebDriver:TakeScreenshot', {'full':False})
        encoded = screenshot.get('value', screenshot) if isinstance(screenshot, dict) else screenshot
        (ROOT/'.build/firefox/passwords-navigation.png').write_bytes(base64.b64decode(encoded))
        f.js("document.getElementById('mybro-passwords-navigation').lastElementChild.click();return true;")
        f.wait("gBrowser.currentURI.spec==='about:preferences#grayfox'")
        f.wait("document.getElementById('mybro-passwords-navigation').hidden")
        print('PASS: returning to Settings hides the extra chrome navigation', flush=True)


if __name__ == '__main__':
    main()
