// SPDX-License-Identifier: MIT
(()=>{
 const initialHash=location.hash;
 const owner=window.browsingContext.topChromeWindow;
 const html=(tag,text="",attrs={})=>{
  const n=document.createElementNS("http://www.w3.org/1999/xhtml",tag);n.textContent=text;
  for(const[k,v]of Object.entries(attrs))n.setAttribute(k,v);
  return n;
 };
 function start(){
  const app=owner.myBro,root=document.documentElement;
  const navigation=html("nav","",{id:"navigation","aria-label":"Разделы браузера"});
  document.body.prepend(navigation);
  window.renderMyBroNavigation(navigation,app,PrivateBrowsingUtils.isWindowPrivate(owner),"settings");
  const categories=document.getElementById("categories");
  const pane=html("section","",{id:"grayfox-settings","data-category":"paneGrayfox",hidden:"true"});
  pane.append(html("h1","Интерфейс GrayFox"));
  const notice=html("p","",{id:"grayfox-settings-notice",role:"status"});pane.append(notice);
  const controls=[];
  function card(title){const n=html("section","",{class:"grayfox-card"});n.append(html("h2",title));pane.append(n);return n;}
  function setting(parent,label,key,options,fallback){
   const row=html("label",label,{class:"grayfox-setting"});
   const control=html(options?"select":"input","",{"data-grayfox-pref":key,"aria-label":label});
   if(options){for(const[value,text]of options)control.append(html("option",text,{value}));row.append(control);}
   else{control.type="checkbox";row.prepend(control);}
   control.onchange=()=>{try{app.write(key,options?control.value:control.checked);notice.textContent="";}catch(error){notice.textContent=error.message;sync();}};
   controls.push({control,key,options,fallback});parent.append(row);
  }
  const appearance=card("Оформление браузера");
  setting(appearance,"Цветовая схема GrayFox","theme",[["system","Как в системе"],["light","Светлая"],["dark","Тёмная"]],"system");
  const home=card("Новая вкладка");
  setting(home,"Часы","startClock",null,false);setting(home,"Поисковая строка","startSearch",null,true);setting(home,"Плитки закладок","startTiles",null,true);
  const tabs=card("Вкладки и группы");
  setting(tabs,"Открывать дополнительную новую вкладку при запуске","extraStartTab",null,false);
  setting(tabs,"Открывать внешние ссылки в уже существующей вкладке с этим адресом","reuseExternalTab",null,false);
  setting(tabs,"Уменьшить анимацию интерфейса GrayFox","reduceMotion",null,false);
  const bookmarks=html("label","Панель закладок",{class:"grayfox-setting"}),visibility=html("select","",{"aria-label":"Панель закладок"});
  for(const[value,label]of[["always","На всех страницах"],["newtab","На новой вкладке"],["never","Скрыта"]])visibility.append(html("option",label,{value}));
  visibility.onchange=()=>{
   Services.prefs.setStringPref("browser.toolbars.bookmarks.visibility",visibility.value);
   for(const w of Services.wm.getEnumerator("navigator:browser"))w.BookmarkingUI?.updateBookmarkToolbarVisibility();
  };
  bookmarks.append(visibility);tabs.append(bookmarks);
  const reset=html("button","Сбросить настройки интерфейса GrayFox",{type:"button",class:"grayfox-reset"});
  reset.onclick=()=>{
   if(!Services.prompt.confirm(owner,"Настройки GrayFox","Вернуть оформление и параметры новой вкладки по умолчанию? Вкладки, группы и сохранённые данные останутся."))return;
   for(const{key}of controls)if(!Services.prefs.prefIsLocked("mybro."+key))Services.prefs.clearUserPref("mybro."+key);
   if(!Services.prefs.prefIsLocked("mybro.groupWidth"))Services.prefs.clearUserPref("mybro.groupWidth");
  };
  pane.append(reset);document.getElementById("mainPrefPane").append(pane);
  window.register_module("paneGrayfox",{init(){}});
  const category=html("moz-page-nav-button","Интерфейс GrayFox",{id:"category-grayfox",view:"paneGrayfox",iconsrc:"chrome://global/skin/icons/settings.svg"});
  categories.prepend(category);
  const side=html("aside","",{id:"grayfox-settings-sidebar","aria-label":"Категории настроек"});categories.before(side);
  const categoryList=html("nav","",{id:"grayfox-settings-categories","aria-label":"Разделы настроек"});
  side.append(document.getElementById("searchInput"),categoryList);
  function renderSidebar(){
   const buttons=[],seen=new Set();
   for(const n of categories.querySelectorAll(":scope > moz-page-nav-button[id][view]")){
    const view=n.getAttribute("view"),label=n.textContent.trim();
    if(n.hidden||!label||seen.has(view)||n.getAttribute("slot"))continue;
    seen.add(view);const b=html("button",label,{type:"button","data-view":view});
    b.onclick=()=>window.gotoPref(view);buttons.push(b);
   }
   categoryList.replaceChildren(...buttons);updateSelection();
  }
  function updateSelection(){
   const current=categories.currentView;
   for(const b of categoryList.children){const active=b.dataset.view===current;b.classList.toggle("active",active);if(active)b.setAttribute("aria-current","page");else b.removeAttribute("aria-current");}
  }
  function sync(){
   const theme=app.read("theme","system");root.dataset.theme=theme;
   root.style.colorScheme=theme==="system"?"light dark":theme;
   for(const{control,key,options,fallback}of controls){
    control.disabled=Services.prefs.prefIsLocked("mybro."+key);
    if(options)control.value=app.read(key,fallback);else control.checked=app.read(key,fallback);
   }
   visibility.value=Services.prefs.getStringPref("browser.toolbars.bookmarks.visibility","always");
   visibility.disabled=Services.prefs.prefIsLocked("browser.toolbars.bookmarks.visibility");
  }
  const prefObserver={observe:sync};Services.prefs.addObserver("mybro.",prefObserver);Services.prefs.addObserver("browser.toolbars.bookmarks.visibility",prefObserver);
  const observer=new MutationObserver(renderSidebar);observer.observe(categories,{childList:true,subtree:true,characterData:true,attributes:true,attributeFilter:["hidden"]});
  document.addEventListener("paneshown",updateSelection);
  window.addEventListener("unload",()=>{observer.disconnect();Services.prefs.removeObserver("mybro.",prefObserver);Services.prefs.removeObserver("browser.toolbars.bookmarks.visibility",prefObserver);},{once:true});
  sync();renderSidebar();
  if(!initialHash||initialHash==="#grayfox")window.gotoPref("paneGrayfox");
  root.dataset.grayfoxReady="true";
 }
 document.addEventListener("Initialized",()=>{
  if(owner.myBro?.ready)start();else owner.addEventListener("mybro-ready",start,{once:true});
 },{once:true});
})();
