// SPDX-License-Identifier: MIT
(()=>{
 const embedder=window.browsingContext?.top?.embedderElement;
 const owner=embedder?.documentGlobal||embedder?.ownerGlobal||Services.wm.getMostRecentWindow("navigator:browser");
 const {PrivateBrowsingUtils}=ChromeUtils.importESModule("resource://gre/modules/PrivateBrowsingUtils.sys.mjs");
 const start=()=>{
  const navigation=document.createElement("nav");navigation.id="navigation";navigation.setAttribute("aria-label","Разделы браузера");
  document.body.prepend(navigation);
  window.renderMyBroNavigation(navigation,owner.myBro,PrivateBrowsingUtils.isWindowPrivate(owner),"extensions");
 };
 if(owner.myBro?.ready)start();else owner.addEventListener("mybro-ready",start,{once:true});
})();
