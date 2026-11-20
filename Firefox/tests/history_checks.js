async (page) => {
  const check = (ok, message) => { if (!ok) throw new Error(message); };
  await page.reload();
  await page.waitForFunction(() => document.documentElement.dataset.ready === 'true');
  const layouts = [];
  for (const width of [1280, 960, 720, 480]) {
    await page.setViewportSize({ width, height: 800 });
    const layout = await page.evaluate(() => {
      const pane = document.querySelector('.history-items');
      return { viewport: innerWidth, document: document.documentElement.scrollWidth,
        rowHeight: document.querySelector('.row').getBoundingClientRect().height,
        pane: pane?.clientWidth, paneContent: pane?.scrollWidth,
        paneHeight: pane?.clientHeight, scrollHeight: pane?.scrollHeight,
        bottom: pane?.getBoundingClientRect().bottom };
    });
    check(layout.document === width, 'History overflows the window at ' + width);
    check(layout.paneContent <= layout.pane && layout.bottom <= 800 && layout.scrollHeight > layout.paneHeight, 'History must scroll inside its pane at ' + width);
    check(layout.rowHeight === 32, 'History rows must be compact');
    layouts.push(layout);
  }
  await page.setViewportSize({ width: 1280, height: 800 });
  check(await page.locator('.history-row').count() === 1000, 'Initial page must retain the history limit');
  check(await page.locator('.day').count() >= 2, 'History must keep day separators');
  const search = page.getByRole('searchbox', { name: 'Поиск в истории' });
  const remove = page.getByRole('button', { name: 'Удалить выбранное', exact: true });
  const all = page.getByRole('checkbox', { name: 'Выбрать все показанные записи', exact: true });
  check(await remove.isDisabled(), 'Deletion must be disabled without a selection');
  await page.locator('[data-visit-id="2"] input').check();
  check(await all.evaluate(x => x.indeterminate), 'Select all must show a partial selection');
  await page.getByRole('button', { name: 'Показать ещё', exact: true }).click();
  check(await page.locator('.history-row').count() === 1041, 'Load more must append older visits');
  check(await page.locator('[data-visit-id="2"] input').isChecked(), 'Load more must preserve selection');
  await page.locator('[data-visit-id="extra:undated"] input').check();
  await remove.click();
  await page.waitForFunction(() => historyFixture.removed.length === 2);
  check(await page.evaluate(() => historyFixture.rows.some(x => x.id === 3) && !historyFixture.rows.some(x => x.id === 2)), 'Deleting a visit must preserve another visit to the same URL');
  check(await page.locator('[data-visit-id="extra:undated"]').count() === 0, 'Undated visits must be selectable and removable');
  await search.fill('article/10');
  await page.waitForFunction(() => document.querySelectorAll('.history-row').length === 48);
  await all.check();
  check(await page.locator('.history-row input:checked').count() === 48, 'Select all must select shown search results');
  await all.uncheck();
  check(await remove.isDisabled(), 'Clearing selection must disable deletion');
  await page.locator('.history-row input').first().check();
  await search.fill('repeated');
  await page.waitForFunction(() => document.querySelectorAll('.history-row').length === 1);
  check(await remove.isDisabled(), 'A new search must clear the previous selection');
  const beforeOpen = await page.evaluate(() => historyFixture.opened.length);
  await page.locator('.history-row .name').click();
  check(await page.evaluate(() => historyFixture.opened.length) === beforeOpen + 1, 'Clicking a history link must open it');
  await search.fill('slow');
  await page.waitForTimeout(200);
  await search.fill('repeated');
  await page.waitForTimeout(850);
  check(await page.locator('.history-row').count() === 1, 'A stale search must not overwrite newer results');
  await search.fill('');
  await page.waitForFunction(() => document.querySelectorAll('.history-row').length === 1039);
  await page.evaluate(() => { historyFixture.failId = 5; });
  await page.locator('[data-visit-id="4"] input').check();
  await page.locator('[data-visit-id="5"] input').check();
  await remove.click();
  await page.waitForFunction(() => document.getElementById('notice').textContent === 'Не удалось удалить запись');
  check(await page.locator('[data-visit-id="4"]').count() === 0 && await page.locator('[data-visit-id="5"] input').isChecked(), 'A partial deletion failure must retain the failed visit and its selection');
  await page.evaluate(() => { historyFixture.failId = null; });
  await remove.click();
  await page.waitForFunction(() => !historyFixture.rows.some(x => x.id === 5));
  check(await page.evaluate(() => historyFixture.removed.filter(id => id === 4).length) === 1, 'Retry must not delete an already removed visit again');
  const period = page.getByRole('combobox', { name: 'Период очистки', exact: true });
  for (const hours of ['1', '24', '168', '720', '2160', '8760', '0']) await period.selectOption(hours);
  await page.getByRole('button', { name: 'Очистить историю', exact: true }).click();
  check(await page.evaluate(() => historyFixture.cleared.length) === 0, 'Cancelling clear must preserve history');
  await page.evaluate(() => { historyFixture.confirm = true; });
  await period.selectOption('168');
  await page.getByRole('button', { name: 'Очистить cookies', exact: true }).click();
  check(await page.evaluate(() => historyFixture.cleared[0][0] === 'cookies' && Math.abs(historyFixture.cleared[0][1] - (Date.now() - 168 * 3600000)) < 5000), 'Cookie clearing must use the selected period');
  await period.selectOption('0');
  await page.getByRole('button', { name: 'Очистить историю', exact: true }).click();
  await page.waitForFunction(() => historyFixture.rows.length === 0);
  check(await page.locator('.empty').isVisible() && await remove.isDisabled(), 'Cleared history must show an empty state');
  check(await page.locator('#notice').innerText() === '', 'History actions must not report errors');
  return { passed: true, layouts, checked: ['day separators', 'individual selection', 'same URL visits', 'undated visit', 'load more', 'select all', 'search', 'stale search', 'open link', 'partial failure and retry', 'periods', 'cancel clear', 'clear cookies', 'clear history'] };
}
