async (page) => {
  const source = await (await page.request.get(new URL('/MyBroLoginFieldsChild.sys.mjs', page.url()).href)).text();
  await page.setContent('<form><input id="username" name="username" type="login" autocomplete="email"><input type="password" value="synthetic"></form><input name="search">');
  await page.evaluate(source => {
    const Actor = new Function('JSWindowActorChild', source.replace('export class', 'class') + '; return MyBroLoginFieldsChild;')(class {});
    window.actor = new Actor(); actor.document = document; actor.contentWindow = window;
    actor.handleEvent();
  }, source);
  const check = (ok, label) => { if (!ok) throw new Error(label); };
  check(await page.locator('#username').getAttribute('type') === 'text', 'Nonstandard login type must become a standard text input');
  check(await page.locator('#username').getAttribute('autocomplete') === 'username', 'Native manager must receive the username hint');
  check(await page.locator('[type=password]').inputValue() === 'synthetic' && await page.locator('[name=search]').getAttribute('autocomplete') === null, 'Passwords and unrelated fields must remain untouched');
  await page.locator('#username').evaluate(input => input.replaceWith(Object.assign(document.createElement('input'), {id:'username',name:'username',type:'login'})));
  await page.waitForFunction(() => document.querySelector('#username').getAttribute('type') === 'text');
  await page.evaluate(() => actor.didDestroy());
  return {passed:4};
}
