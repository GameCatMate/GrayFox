// Ported from the user's Vivaldi site fixes — Grafana & 9GAG 1.2.0.
export class MyBro9GagChild extends JSWindowActorChild {
  handleEvent(event) {
    if (event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
    const target = event.target;
    if (!(target instanceof this.contentWindow.Element)) return;
    const player = target.closest('.post-view.video-post');
    if (!player || target.closest('.sound-toggle, button, input, [role="button"], [role="slider"]')) return;
    const video = player.querySelector('video');
    const sound = player.querySelector('.sound-toggle');
    if (!video || !sound || video.controls) return;
    const rect = video.getBoundingClientRect();
    if (event.clientX < rect.left || event.clientX > rect.right || event.clientY < rect.top || event.clientY > rect.bottom) return;
    event.preventDefault();
    event.stopImmediatePropagation();
    // Use the site's control so its mute state and icon stay in sync.
    sound.click();
    if (video.paused) video.play().catch(() => {});
  }
}
