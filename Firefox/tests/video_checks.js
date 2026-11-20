async (page) => {
  const source = await (await page.request.get(new URL('/MyBro9GagChild.sys.mjs', page.url()).href)).text();
  await page.setContent(`<div class="post-view video-post"><a href="#post"><video style="width:320px;height:180px"></video></a><button class="sound-toggle">Sound</button><button class="other">Other</button></div>`);
  await page.evaluate(source => {
    const Actor = new Function('JSWindowActorChild', source.replace('export class', 'class') + '; return MyBro9GagChild;')(class {});
    const actor = new Actor(); actor.contentWindow = window;
    window.addEventListener('click', event => actor.handleEvent(event), true);
    window.counts = {sound:0, posts:0, other:0, play:0};
    const video = document.querySelector('video');
    video.muted = true;
    video.play = () => { counts.play++; return Promise.resolve(); };
    document.querySelector('.sound-toggle').onclick = event => { event.stopPropagation(); counts.sound++; video.muted = !video.muted; };
    document.querySelector('.other').onclick = event => { event.stopPropagation(); counts.other++; };
    document.querySelector('a').onclick = event => { event.preventDefault(); counts.posts++; };
  }, source);
  const check = (ok, label) => { if (!ok) throw new Error(label); };
  await page.locator('video').click();
  await page.locator('video').click();
  let state = await page.evaluate(() => ({...counts, muted:document.querySelector('video').muted}));
  check(state.sound === 2 && state.posts === 0 && state.muted, 'Repeated video clicks toggle sound and keep the feed open');
  await page.locator('video').click({modifiers:['Control']});
  await page.locator('video').evaluate(video => video.controls = true);
  await page.locator('video').click({position:{x:160,y:40}});
  await page.locator('.sound-toggle').click();
  await page.locator('.other').click();
  state = await page.evaluate(() => ({...counts}));
  check(state.sound === 3 && state.posts === 1 && state.other === 1, 'Modified clicks, native video controls and buttons keep their behavior');
  await page.locator('video').evaluate(video => video.controls = false);
  await page.locator('.post-view').evaluate(player => player.innerHTML = '<a href="#new"><video style="width:320px;height:180px"></video></a><button class="sound-toggle">Sound</button>');
  await page.evaluate(() => {
    const video = document.querySelector('video'); video.play = () => Promise.resolve();
    document.querySelector('.sound-toggle').onclick = event => {event.stopPropagation(); counts.sound++;};
    document.querySelector('a').onclick = event => {event.preventDefault(); counts.posts++;};
  });
  await page.locator('video').click();
  state = await page.evaluate(() => ({...counts}));
  check(state.sound === 4 && state.posts === 1, 'Dynamically inserted videos are handled without observers');
  return {passed:3, ...state};
}
