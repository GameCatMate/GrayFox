async (page) => {
  const check = (value, message) => { if (!value) throw Error(message); };
  const base = new URL(page.url()).origin;
  await page.goto(base + '/bookmarks.html?view=bookmarks');
  await page.waitForFunction(() => document.documentElement.dataset.ready === 'true');
  const expected = ['Мой профиль', 'Закладки', 'Загрузки', 'История', 'Пароли', 'Расширения', 'Настройки'];
  check(JSON.stringify(await page.locator('#navigation button').allTextContents()) === JSON.stringify(expected), 'All internal pages must share navigation without Notes');
  await page.goto(base + '/bookmarks.html?view=notes');
  await page.waitForFunction(() => document.documentElement.dataset.ready === 'true');
  check(await page.title() === 'Новая вкладка' && await page.locator('textarea').count() === 0, 'Old Notes tabs must show the new tab page');
  await page.goto(base + '/addons.html');
  await page.waitForSelector('#navigation button');
  check(JSON.stringify(await page.locator('#navigation button').allTextContents()) === JSON.stringify(expected), 'Native Add-ons must retain the same navigation');
  check(await page.locator('#navigation .active').innerText() === 'Расширения', 'Extensions must be the selected section');
  check(await page.locator('#full').isVisible(), 'Native extension controls must remain visible');
  const layouts = [];
  for (const width of [1600, 1280, 720, 480]) {
    await page.setViewportSize({ width, height: 800 });
    const size = await page.evaluate(() => ({ width: innerWidth, content: document.documentElement.scrollWidth,
      left: document.querySelector('#sidebar').getBoundingClientRect().left,
      right: innerWidth - document.querySelector('#main').getBoundingClientRect().right - parseFloat(getComputedStyle(document.documentElement).getPropertyValue('--main-margin-end')) }));
    check(size.width === size.content, 'Navigation must not overflow at ' + width); layouts.push(size);
    check(Math.abs(size.left - size.right) <= 1, 'Extensions layout must have equal outer margins at ' + width);
  }
  for (const name of expected) await page.getByRole('button', { name, exact: true }).click();
  check(await page.evaluate(() => JSON.stringify(navigationCalls) === JSON.stringify([['manager','profile'],['manager','bookmarks'],['manager','downloads'],['manager','history'],['native','about:logins'],['native','about:addons'],['manager','settings']])), 'Each section must use its existing browser action');
  await page.goto(base + '/addons.html?private=1');
  await page.waitForSelector('#navigation button');
  check(await page.locator('#navigation').innerText().then(text => !text.includes('Мой профиль') && !text.includes('История') && !text.includes('Заметки')), 'Native navigation must preserve private-mode restrictions');
  return { passed: true, layouts, checked: ['shared navigation', 'removed Notes', 'old Notes tab', 'native extension content', 'navigation actions', 'private mode'] };
}
