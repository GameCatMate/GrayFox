async (page) => {
  const check = (ok, message) => { if (!ok) throw new Error(message); };
  await page.reload();
  await page.waitForFunction(() => document.documentElement.dataset.ready === 'true');
  check(await page.locator('#bookmark-folder-mobile______').count() === 0, 'Empty system folders must stay out of the tree');
  check(await page.locator('#bookmark-folder-fixture-child').count() === 0, 'Branches must initially be collapsed');
  await page.locator('#bookmark-toggle-fixture-it').click();
  check(await page.locator('#bookmark-folder-fixture-child').isVisible(), 'Expanding a folder must reveal its children');
  await page.locator('#bookmark-toggle-fixture-it').click();
  check(await page.locator('#bookmark-folder-fixture-child').count() === 0, 'Collapsing a folder must hide its children');
  await page.locator('#bookmark-folder-fixture-it').click();
  const layouts = [];
  for (const width of [1280, 960, 720, 480]) {
    await page.setViewportSize({ width, height: 800 });
    const layout = await page.evaluate(() => ({
      viewport: innerWidth, document: document.documentElement.scrollWidth,
      pane: document.querySelector('.bookmark-items').clientWidth,
      paneContent: document.querySelector('.bookmark-items').scrollWidth,
      paneHeight: document.querySelector('.bookmark-items').clientHeight,
      paneScrollHeight: document.querySelector('.bookmark-items').scrollHeight,
      paneBottom: document.querySelector('.bookmark-items').getBoundingClientRect().bottom,
      folderHeight: document.querySelector('.bookmark-folder-row').getBoundingClientRect().height,
      bookmarkHeight: document.querySelector('.bookmark-row').getBoundingClientRect().height,
      unsavedTabVisible: document.body.innerText.includes('UNSAVED OPEN TAB'),
    }));
    check(layout.document === layout.viewport && layout.paneContent <= layout.pane, 'Long bookmarks must not overflow at ' + width);
    check(layout.paneScrollHeight > layout.paneHeight && layout.paneBottom <= 800, 'Long folders must scroll inside the window at ' + width);
    check(layout.folderHeight === 28 && layout.bookmarkHeight === 32, 'Bookmark rows must remain compact');
    check(!layout.unsavedTabVisible, 'The library must only list saved bookmarks');
    layouts.push(layout);
  }
  await page.setViewportSize({ width: 1280, height: 800 });
  const search = page.getByRole('searchbox', { name: 'Поиск в закладках' });
  await search.fill('Deep bookmark');
  check(await page.locator('.bookmark-row').count() === 1, 'Search must find bookmarks inside collapsed folders');
  await search.fill('UNSAVED OPEN TAB');
  check(await page.locator('.bookmark-row').count() === 0, 'Open tabs must not appear in bookmark search');
  await search.fill('');
  const docs = page.locator('[data-bookmark-guid="fixture-docs"]');
  await docs.hover();
  await docs.getByRole('button', { name: 'Изменить', exact: true }).click();
  await page.getByLabel('Название', { exact: true }).fill('Документация обновлена');
  await page.getByRole('button', { name: 'Сохранить', exact: true }).click();
  await page.getByRole('dialog').waitFor({ state: 'detached' });
  check(await page.evaluate(() => bookmarkFixture.locate('fixture-docs').node.title === 'Документация обновлена'), 'Rename must update the saved item');
  await docs.hover();
  await docs.getByRole('button', { name: 'Перенести', exact: true }).click();
  await page.getByRole('combobox', { name: 'Папка', exact: true }).selectOption('fixture-personal');
  await page.getByRole('button', { name: 'Сохранить', exact: true }).click();
  await page.getByRole('dialog').waitFor({ state: 'detached' });
  check(await page.evaluate(() => bookmarkFixture.locate('fixture-docs').parent.guid === 'fixture-personal'), 'Move must preserve the item in its destination');
  await page.locator('#bookmark-folder-fixture-personal').click();
  check(await docs.isVisible(), 'Moved bookmark must appear in its new folder');
  await page.locator('.side').getByRole('button', { name: 'Новая папка', exact: true }).click();
  await page.getByLabel('Название', { exact: true }).fill('Новая тема');
  await page.getByRole('button', { name: 'Сохранить', exact: true }).click();
  await page.getByRole('dialog').waitFor({ state: 'detached' });
  check(await page.locator('.folder-select.active').innerText() === 'Новая тема', 'New folder must be selected and visible in its tree branch');
  await page.getByRole('button', { name: 'Добавить закладку', exact: true }).click();
  await page.getByLabel('Название', { exact: true }).fill('Добавленная ссылка');
  await page.getByLabel('Адрес', { exact: true }).fill('https://example.test/new');
  await page.getByRole('button', { name: 'Сохранить', exact: true }).click();
  await page.getByRole('dialog').waitFor({ state: 'detached' });
  const added = page.locator('.bookmark-row').filter({ hasText: 'Добавленная ссылка' });
  const addedGuid = await added.getAttribute('data-bookmark-guid');
  check(!!addedGuid, 'Adding a bookmark must insert it into the selected folder');
  await page.getByRole('button', { name: 'Переименовать папку', exact: true }).click();
  await page.getByLabel('Название', { exact: true }).fill('Новая тема 2');
  await page.getByRole('button', { name: 'Сохранить', exact: true }).click();
  await page.getByRole('dialog').waitFor({ state: 'detached' });
  await added.dragTo(page.locator('.bookmark-folder-row').filter({ has: page.locator('#bookmark-folder-fixture-it') }));
  await page.waitForFunction(guid => bookmarkFixture.locate(guid).parent.guid === 'fixture-it', addedGuid);
  await page.locator('#bookmark-folder-fixture-it').click();
  check(await page.locator('[data-bookmark-guid="' + addedGuid + '"]').isVisible(), 'Dragging must move the saved bookmark into its target folder');
  await page.evaluate(() => { Services.prompt.confirm = () => false; });
  await page.getByRole('button', { name: 'Удалить папку', exact: true }).click();
  check(await page.evaluate(() => !!bookmarkFixture.locate('fixture-it')), 'Cancelling folder deletion must preserve all saved data');
  check(await page.locator('#notice').innerText() === '', 'Bookmark interactions must not report errors');
  return { passed: true, layouts, checked: ['collapse', 'search', 'rename', 'move', 'create folder', 'add bookmark', 'drag', 'cancel deletion'] };
}
