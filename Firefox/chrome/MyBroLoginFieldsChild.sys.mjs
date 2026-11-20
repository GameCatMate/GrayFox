// EasyDocs uses the nonstandard input type="login", which misses Gecko's username events.
export class MyBroLoginFieldsChild extends JSWindowActorChild {
  handleEvent() {
    const normalize = () => {
      for (const input of this.document.querySelectorAll('input#username[name="username"][type="login"]')) {
        input.autocomplete = 'username';
        input.type = 'text';
      }
    };
    this.observer = new this.contentWindow.MutationObserver(normalize);
    this.observer.observe(this.document, {childList:true, subtree:true});
    normalize();
  }
  didDestroy() { this.observer?.disconnect(); }
}
