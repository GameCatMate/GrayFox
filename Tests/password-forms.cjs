const assert = require('node:assert/strict');

module.exports = async function testPasswordForms(page, source) {
  const script = source.split('static let script = #"""')[1].split('"""#')[0];
  const origin = 'https://mybro-login-fixture.example';
  const passed = [];
  async function fixture(name, html, check, accounts = ['fixture-user']) {
    const p = await page.context().newPage();
    try {
      await p.route(`${origin}/**`, route => route.fulfill({contentType: 'text/html', body: html}));
      await p.addInitScript(({accounts}) => {
        window.requests = [];
        window.webkit = {messageHandlers: {myBroPasswords: {postMessage: async body => {
          window.requests.push(body);
          if (body.operation === 'accounts') return accounts;
          if (body.operation === 'fill') {
            const user = body.username || (accounts.length === 1 ? accounts[0] : null);
            return user && accounts.includes(user) ? {username: user, password: 'fixture-password'} : null;
          }
          return null;
        }}}};
      }, {accounts});
      await p.goto(origin + '/login');
      await p.evaluate(script);
      await check(p);
      passed.push(name);
    } finally { await p.close(); }
  }
  const filled = p => p.waitForFunction(() => document.querySelector('#pass')?.value === 'fixture-password', null, {timeout: 2500});
  const untouched = async p => {
    await p.waitForTimeout(350);
    assert.equal(await p.locator('#pass').inputValue(), '');
    assert.equal(await p.evaluate(() => requests.some(r => r.operation === 'fill')), false);
  };
  await fixture('username first (EasyDocs)', '<form action="#"><input id="username" name="username" autocomplete="email"><button>Далее</button></form>', async p => {
    await p.waitForFunction(() => document.querySelector('#username').value === 'fixture-user', null, {timeout: 2500});
    assert.equal(await p.evaluate(() => requests.some(r => r.operation === 'fill')), false);
    await p.evaluate(() => {document.querySelector('form').innerHTML = '<input id="pass" type="password" autocomplete="current-password"><button>Войти</button>';});
    await filled(p);
  });
  await fixture('formless username first (Bitrix)', '<div><h2>Войти</h2><input id="login" autocomplete="username"><button>Продолжить</button></div>', async p => {
    await p.waitForFunction(() => document.querySelector('#login').value === 'fixture-user', null, {timeout: 2500});
    await p.evaluate(() => {document.querySelector('#login').remove(); document.querySelector('div').insertAdjacentHTML('beforeend', '<input id="pass" type="password">');});
    await filled(p);
  });
  await fixture('ordinary login', '<form><input id="user"><input id="pass" type="password"></form>', filled);
  await fixture('formless login', '<div><input id="user" name="login"><input id="pass" type="password"></div>', filled);
  await fixture('password-only login', '<form><input id="pass" type="password"></form>', filled);
  await fixture('read-only username', '<form><input id="user" value="fixture-user" readonly><input id="pass" type="password"></form>', filled);
  await fixture('hidden username selects the right account', '<form><input type="hidden" autocomplete="username" value="fixture-user"><input id="pass" type="password"></form>', filled, ['fixture-user', 'other-user']);
  await fixture('framework-controlled input', `<form><input id="user"><input id="pass" type="password"></form><script>
    window.model = '';
    const input = document.querySelector('#pass');
    const native = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value');
    Object.defineProperty(input, 'value', {get() {return native.get.call(this)}, set(value) {native.set.call(this, value); window.ownSetter = true;}});
    input.addEventListener('input', () => {window.model = input.value;});
  </script>`, async p => {await filled(p); assert.equal(await p.evaluate(() => window.model), 'fixture-password'); assert.equal(await p.evaluate(() => !!window.ownSetter), false);});
  await fixture('late password field', '<form><input id="user"></form>', async p => {
    await p.evaluate(() => {document.querySelector('form').insertAdjacentHTML('beforeend', '<input id="pass" type="password">');});
    await filled(p);
  });
  await fixture('multiple accounts require a choice', '<form><input id="user" autocomplete="username"><input id="pass" type="password"></form>', async p => {
    await p.locator('#user').click();
    await p.waitForFunction(() => !!document.querySelector('[data-mybro-passwords]'), null, {timeout: 2500});
    assert.equal(await p.locator('#pass').inputValue(), '');
    await p.locator('#user').press('ArrowDown');
    await p.keyboard.press('Enter');
    await filled(p);
    assert.equal(await p.locator('#user').inputValue(), 'fixture-user');
  }, ['fixture-user', 'other-user']);
  await fixture('typed password is preserved', '<form><input id="user"><input id="pass" type="password" value="typed-by-user"></form>', async p => {
    await p.waitForTimeout(350); assert.equal(await p.locator('#pass').inputValue(), 'typed-by-user');
  });
  await fixture('external form action is blocked', '<form action="https://different.example/session"><input id="user"><input id="pass" type="password"></form>', untouched);
  await fixture('external submit override is blocked', '<form><input id="user"><input id="pass" type="password"><button formaction="https://different.example/session">Войти</button></form>', untouched);
  await fixture('associated external submit override is blocked', '<form id="f"><input id="user"><input id="pass" type="password"></form><button form="f" formaction="https://different.example/session">Войти</button>', untouched);
  await fixture('read-only identity cannot be replaced by another account', '<form><input id="user" value="fixture" readonly><input id="pass" type="password"></form>', async p => {
    await p.locator('#pass').click();
    await p.waitForFunction(() => !!document.querySelector('[data-mybro-passwords]'), null, {timeout: 2500});
    await p.locator('#pass').press('ArrowDown');
    await p.keyboard.press('Enter');
    await untouched(p);
  });
  await fixture('registration is skipped', '<form><input id="user"><input id="pass" type="password" autocomplete="new-password"></form>', untouched);
  await fixture('password confirmation is skipped', '<form><input id="user"><input id="pass" type="password"><input type="password"></form>', untouched);
  await fixture('background retry', '<form><input id="user"><input id="pass" type="password"></form>', async p => {
    await filled(p);
    await p.evaluate(() => {document.querySelector('#pass').value = ''; globalThis.__myBroScanPasswords();});
    await filled(p);
  });
  return passed;
};

if (require.main === module) {
  (async () => {
    const {chromium} = require(process.env.MYBRO_PLAYWRIGHT || 'playwright');
    const {readFileSync} = require('node:fs');
    const {join} = require('node:path');
    const browser = await chromium.launch({headless: true});
    try {
      const page = await browser.newPage();
      const source = readFileSync(join(__dirname, '../Sources/PasswordForms.swift'), 'utf8');
      const passed = await module.exports(page, source);
      console.log(`${passed.length} password form scenarios passed`);
    } finally { await browser.close(); }
  })().catch(error => {console.error(error); process.exitCode = 1;});
}
