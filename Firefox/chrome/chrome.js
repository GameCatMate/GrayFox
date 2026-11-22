// SPDX-License-Identifier: MIT
(() => {
  "use strict";
  const BASE = "chrome://browser/content/mybro/";
  const SS = ChromeUtils.importESModule("moz-src:///browser/components/sessionstore/SessionStore.sys.mjs").SessionStore;
  const { PrivateBrowsingUtils } = ChromeUtils.importESModule("resource://gre/modules/PrivateBrowsingUtils.sys.mjs");
  const privateWindow = PrivateBrowsingUtils.isWindowPrivate(window);
  ChromeUtils.importESModule(BASE + "pages.sys.mjs").registerPages();
  const { SearchService: search }=ChromeUtils.importESModule("moz-src:///toolkit/components/search/SearchService.sys.mjs");
  const COLORS = {blue:"#32648a",purple:"#754579",green:"#3b775a",orange:"#9a6532",red:"#984444",gray:"#62666b"};
  const groupKey = "mybroGroup";
  const read = (key, fallback) => { try { return JSON.parse(Services.prefs.getStringPref("mybro." + key)); } catch { return fallback; } };
  const write = (key, value) => Services.prefs.setStringPref("mybro." + key, JSON.stringify(value));
  const html = (tag, attrs = {}) => { const node = document.createElementNS("http://www.w3.org/1999/xhtml", tag); for (const [k,v] of Object.entries(attrs)) node.setAttribute(k,v); return node; };
  const xul = (tag, attrs = {}) => { const node = document.createXULElement(tag); for (const [k,v] of Object.entries(attrs)) node.setAttribute(k,v); return node; };
  const all = () => Array.from(gBrowser.tabs).filter(t => !t.closing);
  const groupOf = tab => { if (privateWindow) return ""; try { return SS.getCustomTabValue(tab, groupKey) || ""; } catch { return ""; } };
  function setGroup(tab, id) { if (privateWindow) return; SS.setCustomTabValue(tab, groupKey, id || ""); tab.setAttribute("mybro-group",id || ""); }
  let current = "", selecting = false, refreshScheduled = false, dragging = null, armedNode = null;
  const selections = new Map();
  let groupList, groupArea, groupMenu, groupContext, tabContext, zoomButton;
  const groups = () => privateWindow ? [] : read("groups", []);
  const visible = () => all().filter(t => groupOf(t) === current);
  const selectedGroup = () => groups().find(g => g.id === current);

  function saveGroups(value) { if (privateWindow) return; write("groups", value); refresh(); }
  function namePrompt(title, initial = "") {
    const text = {value:initial};
    return Services.prompt.prompt(window, title, "Название", text, null, {}) ? text.value.trim() : null;
  }
  function createGroup(tab = null) {
    if (privateWindow) return;
    const name = namePrompt("Новая группа вкладок"); if (!name) return;
    const id = crypto.randomUUID(); saveGroups([...groups(),{id,name,color:"blue"}]);
    if (tab) { setGroup(tab,id); selectGroup(id); }
    else { current = id; newTab(); }
  }
  function renameGroup(id) {
    const name = namePrompt("Переименовать группу",groups().find(g=>g.id===id)?.name || "");
    if (name) saveGroups(groups().map(g=>g.id===id ? {...g,name}:g));
  }
  function removeGroup(id) {
    for (const tab of all()) if (groupOf(tab) === id) setGroup(tab,"");
    saveGroups(groups().filter(g=>g.id!==id));
    if (current === id) selectGroup("");
  }
  function selectGroup(id) {
    if (id && !groups().some(g=>g.id===id)) return;
    if (selecting) return;
    selecting = true;
    selections.set(current,gBrowser.selectedTab);
    current = id;
    const members = visible();
    for (const tab of members) gBrowser.showTab(tab);
    const wanted = selections.get(id);
    const target = members.includes(wanted) ? wanted : members[0];
    if (target) gBrowser.selectedTab = target;
    else newTab();
    applyVisibility();
    selecting = false;
    refresh();
  }
  function applyVisibility() {
    for (const tab of all()) {
      const hide = groupOf(tab) !== current;
      tab.toggleAttribute("mybro-hidden", hide);
      if (!hide) gBrowser.showTab(tab);
      else if (!tab.pinned && tab !== gBrowser.selectedTab) gBrowser.hideTab(tab);
    }
  }
  function newTab() {
    const tab = gBrowser.addTrustedTab("about:mybro?view=start",{inBackground:true});
    setGroup(tab,current); gBrowser.showTab(tab); gBrowser.selectedTab = tab;
    refresh(); gURLBar.select(); return tab;
  }
  function openManager(view) {
    const allowed = ["start","profile","bookmarks","downloads","history","settings"];
    if (!allowed.includes(view)) throw new Error("Unknown GrayFox page");
    if (PrivateBrowsingUtils.isWindowPrivate(window) && ["history","profile","bookmarks"].includes(view)) return;
    const url = view==="settings"?"about:preferences#grayfox":"about:mybro?view=" + view;
    const existing = visible().find(t=>view==="settings"?t.linkedBrowser.currentURI.spec.split("#",1)[0]==="about:preferences":t.linkedBrowser.currentURI.spec===url);
    if (existing) { gBrowser.selectedTab = existing; return; }
    const tab = gBrowser.addTrustedTab(url,{inBackground:true}); setGroup(tab,current);
    gBrowser.selectedTab = tab; refresh();
  }
  function nativePage(url) { openTrustedLinkIn(url,"tab"); }
  function refresh() {
    if (refreshScheduled || dragging) return;
    refreshScheduled = true;
    requestAnimationFrame(() => {
      refreshScheduled = false;
      const model = groups();
      const oldNodes = new Map(Array.from(groupList.children).map(n=>[n.dataset.group,n]));
      for (const group of model) {
        let chip = oldNodes.get(group.id);
        if (!chip) {
          chip = html("button", {class:"mybro-group",type:"button",role:"tab"}); chip.dataset.group = group.id;
          chip.append(html("span",{class:"mybro-group-count"}),html("span",{class:"mybro-group-name"}));
          chip.addEventListener("click",()=>{ if (!chip._dragged) selectGroup(group.id); });
          chip.addEventListener("contextmenu",event=>{event.preventDefault(); showGroupContext(group.id,event);});
        }
        chip.children[0].textContent = all().filter(t=>groupOf(t)===group.id).length;
        chip.children[1].textContent = group.name;
        chip.title = group.name;
        chip.setAttribute("aria-selected", String(current === group.id));
        chip.style.setProperty("--mybro-tint", COLORS[group.color] || COLORS.blue);
        groupList.append(chip); oldNodes.delete(group.id);
      }
      for (const node of oldNodes.values()) node.remove();
      const width = read("groupWidth",0);
      groupList.style.setProperty("--mybro-group-width",width > 0 ? width + "px" : Math.min(270,model.length * 100) + "px");
      document.documentElement.setAttribute("data-mybro-theme", read("theme","system"));
      document.documentElement.toggleAttribute("data-mybro-reduce-motion",read("reduceMotion",false));
      applyVisibility();
      for (const tab of all()) {
        tab.setAttribute("context","mybro-tab-context");tab.setAttribute("draggable","false");observer.observe(tab);
        const icon=window.myBroPageIcon(SS.getLazyTabValue(tab,"url")||tab.linkedBrowser.currentURI.spec);
        tab.toggleAttribute("mybro-page-icon",!!icon);
        if(icon&&tab.getAttribute("image")!==icon)gBrowser.setIcon(tab,icon);
      }
    });
  }
  const observer = new ResizeObserver(entries => {
    for (const {target,contentRect} of entries) {
      target.toggleAttribute("mybro-small",contentRect.width < 62);
    }
  });
  function menuItem(parent,label,action,disabled = false) {
    const item = xul("menuitem",{label});
    if(disabled)item.setAttribute("disabled","true");
    item.addEventListener("command",action); parent.append(item); return item;
  }
  function divider(parent) { parent.append(xul("menuseparator")); }
  function menu(parent,label,fill) {
    const item=xul("menu",{label}),popup=xul("menupopup",{nonnative:"true",type:"arrow",class:"mybro-browser-menu"}); item.append(popup);parent.append(item);
    popup.addEventListener("popupshowing",()=>{popup.replaceChildren();fill(popup);});return item;
  }
  function showGroupContext(id,event) {
    groupContext.replaceChildren();
    menuItem(groupContext,"Переименовать…",()=>renameGroup(id));
    menu(groupContext,"Цвет",popup=>{ for (const [color,label] of Object.entries({blue:"Синий",purple:"Фиолетовый",green:"Зелёный",orange:"Оранжевый",red:"Красный",gray:"Серый"})) {
      menuItem(popup,label,()=>saveGroups(groups().map(g=>g.id===id ? {...g,color}:g)));
    }});
    divider(groupContext); menuItem(groupContext,"Удалить группу",()=>removeGroup(id));
    groupContext.openPopupAtScreen(event.screenX,event.screenY,true);
  }
  function reopenClosed(){
    const closed=SS.getClosedTabDataForWindow(window);
    const index=closed.reduce((latest,tab,i)=>tab.closedAt>closed[latest].closedAt?i:latest,0);
    const tab=SS.undoCloseTab(window,index,window);if(!tab)return;
    const id=groupOf(tab);if(id!==current)selectGroup(id);gBrowser.selectedTab=tab;
    tab.setAttribute("mybro-reopened","true");setTimeout(()=>tab.removeAttribute("mybro-reopened"),240);
    return tab;
  }
  function closeRelative(tab,side) {
    const tabs = visible(),index=tabs.indexOf(tab);
    const closing=tabs.filter((t,i)=>t!==tab && !t.pinned && (side==="others" || (side==="left" ? i<index:i>index)));
    if (closing.includes(gBrowser.selectedTab)) gBrowser.selectedTab=tab;
    gBrowser.removeTabs(closing); refresh();
  }
  function fillTabMenu(tab) {
    tabContext.replaceChildren();
    menuItem(tabContext,"Новая вкладка",newTab);
    if (!privateWindow) menu(tabContext,"Перенести вкладку",popup=>{
      menuItem(popup,"В новую группу…",()=>createGroup(tab));
      menuItem(popup,"Без группы",()=>{setGroup(tab,"");selectGroup("");},groupOf(tab)==="");
      for (const group of groups()) menuItem(popup,group.name,()=>{setGroup(tab,group.id);selectGroup(group.id);},groupOf(tab)===group.id);
    });
    divider(tabContext);
    menuItem(tabContext,"Обновить",()=>tab.linkedBrowser.reload());
    menuItem(tabContext,"Обновить все открытые вкладки",()=>{for (const t of all()) if (!t.hasAttribute("pending")) t.linkedBrowser.reload();});
    menuItem(tabContext,"Дублировать",()=>{const copy=gBrowser.duplicateTab(tab);setGroup(copy,groupOf(tab));gBrowser.selectedTab=copy;refresh();});
    menuItem(tabContext,tab.pinned ? "Открепить вкладку":"Закрепить вкладку",()=>{tab.pinned?gBrowser.unpinTab(tab):gBrowser.pinTab(tab);refresh();});
    menuItem(tabContext,tab.muted?"Включить звук на вкладке":"Отключить звук на вкладке",()=>tab.toggleMuteAudio());
    divider(tabContext);
    menuItem(tabContext,"Закрыть вкладку",()=>gBrowser.removeTab(tab));
    for (const [side,label] of [["others","Закрыть другие вкладки"],["left","Закрыть вкладки слева"],["right","Закрыть вкладки справа"]]) {
      const members=visible(),index=members.indexOf(tab);
      const enabled=members.some((t,i)=>t!==tab&&!t.pinned&&(side==="others"||(side==="left"?i<index:i>index)));
      menuItem(tabContext,label,()=>closeRelative(tab,side),!enabled);
    }
    divider(tabContext);
    menuItem(tabContext,"Открыть закрытую вкладку",reopenClosed);
    menuItem(tabContext,"Настройки",()=>openManager("settings"));
  }
  function installGroups() {
    groupArea=xul("toolbaritem",{id:"mybro-groups",removable:"false"});
    groupList=html("div",{id:"mybro-group-list",role:"tablist","aria-label":"Группы вкладок"});
    const dropdown=html("button",{id:"mybro-group-menu",title:"Все группы","aria-label":"Все группы","aria-haspopup":"menu",type:"button"});
    const resize=html("div",{id:"mybro-group-divider",role:"separator","aria-orientation":"vertical"});
    groupArea.append(groupList,dropdown,resize);
    if (!privateWindow) document.getElementById("tabbrowser-tabs").before(groupArea);
    const popups=document.getElementById("mainPopupSet");
    groupMenu=xul("menupopup",{id:"mybro-groups-popup",nonnative:"true",type:"arrow",class:"mybro-browser-menu"}); groupContext=xul("menupopup",{id:"mybro-group-context",nonnative:"true",type:"arrow",class:"mybro-browser-menu"});
    tabContext=xul("menupopup",{id:"mybro-tab-context",nonnative:"true",type:"arrow",class:"mybro-browser-menu"});
    popups.append(groupMenu,groupContext,tabContext);
    dropdown.addEventListener("click",()=>{
      groupMenu.replaceChildren();menuItem(groupMenu,"Создать группу…",()=>createGroup());divider(groupMenu);
      menuItem(groupMenu,"Вкладки без группы",()=>selectGroup(""));
      for (const g of groups()) menuItem(groupMenu,g.name,()=>selectGroup(g.id));
      groupMenu.openPopup(dropdown,"after_start");
    });
    resize.addEventListener("pointerdown",event=>{
      if (event.button!==0) return;event.preventDefault();resize.setPointerCapture(event.pointerId);
      const x=event.clientX,width=groupList.getBoundingClientRect().width;
      const move=e=>groupList.style.setProperty("--mybro-group-width",Math.max(48,Math.min(innerWidth*.4,width+e.clientX-x))+"px");
      const end=()=>{resize.removeEventListener("pointermove",move);write("groupWidth",groupList.getBoundingClientRect().width);};
      resize.addEventListener("pointermove",move);resize.addEventListener("pointerup",end,{once:true});
    });
    groupList.addEventListener("pointerdown",event=>armDrag(event,"group"));
    window.addEventListener("pointerdown",event=>armDrag(event,"tab"),true);
    window.addEventListener("dragstart",event=>{if(armedNode||event.target.closest?.(".tabbrowser-tab")){event.preventDefault();event.stopImmediatePropagation();}},true);
    gBrowser.tabContainer.addEventListener("contextmenu",event=>{
      const tab=event.target.closest?.(".tabbrowser-tab");if(!tab)return;
      event.preventDefault();event.stopPropagation();fillTabMenu(tab);
      tabContext.openPopupAtScreen(event.screenX,event.screenY,true);
    },true);
  }
  function armDrag(event,type) {
    if (event.button!==0 || event.target.closest?.(".tab-close-button,.tab-icon-overlay")) return;
    const node=event.target.closest?.(type==="group"?".mybro-group":".tabbrowser-tab");if(!node)return;
    if(type==="tab"){event.preventDefault();event.stopImmediatePropagation();gBrowser.selectedTab=node;}
    const host=type==="group"?groupList:window;
    armedNode=node;
    const initial=node.getBoundingClientRect(),startX=event.clientX,grab=event.clientX-initial.left;
    let active=false;
    const move=e=>{
      if(!active && Math.abs(e.clientX-startX)<4)return;
      if(!active){active=true;dragging={node,type};if(type==="group")host.setPointerCapture(e.pointerId);node._dragged=true;node.style.zIndex="20";}
      e.preventDefault();
      const peers=type==="group"?Array.from(groupList.children):visible();
      const target=peers.find(n=>{const r=n.getBoundingClientRect();return n!==node && e.clientX>=r.left && e.clientX<=r.right;});
      if(target){
        const r=target.getBoundingClientRect(),before=peers.indexOf(node)<peers.indexOf(target);
        if ((before && e.clientX > r.left+r.width/2) || (!before && e.clientX < r.left+r.width/2)) {
          const positions=new Map(peers.map(n=>[n,n.getBoundingClientRect().left]));
          node.style.transform="";
          if(type==="group") groupList.insertBefore(node,before?target.nextSibling:target);
          else if(before) gBrowser.moveTabAfter(node,target); else gBrowser.moveTabBefore(node,target);
          if (!read("reduceMotion",false) && !matchMedia("(prefers-reduced-motion: reduce)").matches) {
            for(const n of peers) if(n!==node){const delta=positions.get(n)-n.getBoundingClientRect().left;if(delta)n.animate([{transform:`translateX(${delta}px)`},{transform:"translateX(0)"}],{duration:160,easing:"cubic-bezier(.22,1,.36,1)"});}
          }
        }
      }
      const shift = new DOMMatrixReadOnly(getComputedStyle(node).transform).m41;
      const base = node.getBoundingClientRect().left - shift;
      node.style.transform=`translateX(${e.clientX-grab-base}px)`;
      if(type==="tab"){
        const scroll=gBrowser.tabContainer.arrowScrollbox,rect=scroll.getBoundingClientRect();
        if(e.clientX<rect.left+28)scroll.scrollByPixels(-18,true);
        else if(e.clientX>rect.right-28)scroll.scrollByPixels(18,true);
      }
    };
    const end=e=>{
      host.removeEventListener("pointermove",move,true);host.removeEventListener("pointerup",end,true);host.removeEventListener("pointercancel",end,true);
      armedNode=null;
      if(!active)return;
      if(type==="tab"){
        const target=Array.from(groupList.children).find(n=>{const r=n.getBoundingClientRect();return e.clientX>=r.left&&e.clientX<=r.right&&e.clientY>=r.top&&e.clientY<=r.bottom;});
        if(target){setGroup(node,target.dataset.group);selectGroup(target.dataset.group);}
      } else {
        const model=groups(),order=Array.from(groupList.children).map(n=>n.dataset.group);
        write("groups",order.map(id=>model.find(g=>g.id===id)).filter(Boolean));
      }
      node.style.transform="";node.style.zIndex="";node.style.removeProperty("--mybro-drag-x");dragging=null;
      setTimeout(()=>{node._dragged=false;refresh();},0);
    };
    host.addEventListener("pointermove",move,true);host.addEventListener("pointerup",end,true);host.addEventListener("pointercancel",end,true);
  }
  function installChrome() {
    const contentPrefs=Cc["@mozilla.org/content-pref/service;1"].getService(Ci.nsIContentPrefService2);
    const zoomPreference={
      onContentPrefSet(group,name,value){if(group===null)write("pageZoom",Math.round(value*100));},
      onContentPrefRemoved(group){if(group===null)write("pageZoom",100);}
    };
    contentPrefs.addObserverForName("browser.content.full-zoom",zoomPreference);
    window.addEventListener("unload",()=>contentPrefs.removeObserverForName("browser.content.full-zoom",zoomPreference),{once:true});
    const toolbarMenu=document.getElementById("toolbar-context-menu");
    const styleToolbarMenus=()=>{
      for(const popup of [toolbarMenu,...toolbarMenu.querySelectorAll("menupopup")]){
        popup.setAttribute("nonnative","true");popup.setAttribute("type","arrow");popup.classList.add("mybro-browser-menu");
      }
    };
    styleToolbarMenus();
    const menuSections={"appMenu-history-button":"history","appMenu-bookmarks-button":"bookmarks","appMenu-downloads-button":"downloads","appMenu-passwords-button":"passwords","appMenu-extensions-themes-button":"extensions","appMenu-unified-extensions-button":"extensions","appMenu-settings-button":"settings"};
    const sectionCommands={"Tools:Downloads":"downloads","Browser:ShowAllHistory":"history","Browser:ShowAllBookmarks":"bookmarks","Tools:Addons":"extensions"};
    document.addEventListener("popupshowing",event=>{
      if(event.target===toolbarMenu)styleToolbarMenus();
      if(event.target.id!=="appMenu-popup")return;
      for(const [id,view]of Object.entries(menuSections)){
        const node=document.getElementById(id);if(!node)continue;
        node.removeAttribute("command");node.removeAttribute("closemenu");node.classList.remove("subviewbutton-nav");
        if(["history","bookmarks"].includes(view))node.disabled=privateWindow;
        if(view==="history"){node.removeAttribute("data-l10n-id");node.setAttribute("label","История браузера");}
      }
    });
    window.addEventListener("command",event=>{
      const view=menuSections[event.target.id]||sectionCommands[event.target.id];if(!view)return;
      event.preventDefault();event.stopImmediatePropagation();PanelUI.hide();window.openMyBroSection(window.myBro,view);
    },true);
    const navigation=html("nav",{id:"mybro-passwords-navigation","aria-label":"Разделы браузера"});
    document.getElementById("browser").before(navigation);
    window.renderMyBroNavigation(navigation,window.myBro,privateWindow,"passwords");
    const updateNavigation=()=>{navigation.hidden=gBrowser.currentURI.spec.split(/[?#]/,1)[0]!=="about:logins";};
    const progress={onLocationChange(browser){if(browser===gBrowser.selectedBrowser)updateNavigation();refresh();}};
    gBrowser.addTabsProgressListener(progress);
    gBrowser.tabContainer.addEventListener("TabSelect",updateNavigation);
    window.addEventListener("unload",()=>{gBrowser.removeTabsProgressListener(progress);gBrowser.tabContainer.removeEventListener("TabSelect",updateNavigation);},{once:true});
    updateNavigation();
    const privateKey=document.getElementById("key_privatebrowsing"),restoreWindowKey=document.getElementById("key_undoCloseWindow");
    privateKey.removeAttribute("data-l10n-id");privateKey.setAttribute("key","n");
    restoreWindowKey.removeAttribute("data-l10n-id");restoreWindowKey.removeAttribute("key");restoreWindowKey.removeAttribute("keycode");
    window.addEventListener("command",event=>{if(event.target.id==="cmd_newNavigatorTab"){event.preventDefault();event.stopImmediatePropagation();newTab();}},true);
    if(PrivateBrowsingUtils.isWindowPrivate(window)){
      const badge=html("span",{id:"mybro-private-indicator",title:"Приватное окно GrayFox",role:"status","aria-label":"Приватное окно GrayFox — Инкогнито"});badge.textContent="Инкогнито";document.getElementById("urlbar-container").after(badge);
    }
    zoomButton=html("button",{id:"mybro-zoom",hidden:"true",title:"Вернуть масштаб по умолчанию"});
    document.getElementById("urlbar-container").after(zoomButton);
    zoomButton.addEventListener("click",()=>{FullZoom.setZoom(read("pageZoom",100)/100);showZoom();});
    window.addEventListener("keydown",event=>{
      if(event.ctrlKey && event.key==="Tab"){
        const tabs=visible(),index=tabs.indexOf(gBrowser.selectedTab);if(tabs.length)gBrowser.selectedTab=tabs[(index+(event.shiftKey?-1:1)+tabs.length)%tabs.length];
        event.preventDefault();event.stopImmediatePropagation();return;
      }
      if(!event.metaKey || event.altKey || event.ctrlKey)return;
      if(event.shiftKey && event.key.toLowerCase()==="t"){reopenClosed();event.preventDefault();event.stopImmediatePropagation();return;}
      const key=event.key.toLowerCase();
      if(key==="y"&&!event.shiftKey){openManager("history");event.preventDefault();event.stopImmediatePropagation();}
      else if(key===","){openManager("settings");event.preventDefault();event.stopImmediatePropagation();}
      else if(["+","=","-","0"].includes(key)){
        const percent=key==="0"?read("pageZoom",100):Math.max(30,Math.min(300,Math.round(ZoomManager.zoom*100)+(key==="-"?-10:10)));
        FullZoom.setZoom(percent/100);showZoom();event.preventDefault();event.stopImmediatePropagation();
      }
    },true);
  }
  let zoomTimer;
  function showZoom(){zoomButton.textContent=Math.round(ZoomManager.zoom*100)+"%";zoomButton.hidden=false;clearTimeout(zoomTimer);zoomTimer=setTimeout(()=>{zoomButton.hidden=true;},2000);}
  async function configureSearch() {
    await search.init();
    if(Services.prefs.getBoolPref("mybro.searchInitialized",false))return;
    const engines=await search.getEngines();
    const google=engines.find(e=>e.name==="Google"),duck=engines.find(e=>e.name.includes("DuckDuckGo"));
    if(google) await search.setDefault(google,search.CHANGE_REASON.USER);
    if(duck) await search.setDefaultPrivate(duck,search.CHANGE_REASON.USER);
    Services.prefs.setBoolPref("mybro.searchInitialized",true);
  }
  async function installLibraryControls(){
    const L=ChromeUtils.importESModule(BASE+"library.sys.mjs");
    const button=document.getElementById("downloads-button");
    const ring=document.createElementNS("http://www.w3.org/2000/svg","svg");ring.id="mybro-download-progress";ring.setAttribute("viewBox","0 0 32 32");ring.setAttribute("aria-hidden","true");
    const circle=document.createElementNS(ring.namespaceURI,"circle");for(const [k,v]of Object.entries({cx:16,cy:16,r:14,fill:"none",stroke:"currentColor","stroke-width":2,"stroke-dasharray":88}))circle.setAttribute(k,v);ring.append(circle);button.append(ring);
    const active=new Set(),draw=()=>{const items=[...active].filter(d=>!d.stopped);ring.toggleAttribute("hidden",!items.length);const total=items.reduce((n,d)=>n+d.totalBytes,0),received=items.reduce((n,d)=>n+d.currentBytes,0);circle.setAttribute("stroke-dashoffset",88*(1-(total?Math.min(1,received/total):.08)));};
    const list=await L.downloads.getList(PrivateBrowsingUtils.isWindowPrivate(window)?L.downloads.PRIVATE:L.downloads.PUBLIC);
    const listener={onDownloadAdded(d){active.add(d);draw();},onDownloadChanged:draw,onDownloadRemoved(d){active.delete(d);draw();}};
    await list.addView(listener);window.addEventListener("unload",()=>list.removeView(listener),{once:true});draw();
    document.addEventListener("popupshown",event=>{
      if(event.target.id==="downloadsPanel"&&!document.getElementById("mybro-download-header")){
        const header=html("div",{id:"mybro-download-header"});const title=html("strong");title.textContent="Загрузки";
        const folder=html("button",{type:"button"});folder.textContent="Открыть папку";folder.addEventListener("click",()=>L.downloadFolder().catch(console.error));header.append(title,folder);document.getElementById("downloadsPanel-mainView").prepend(header);
        const allButton=document.getElementById("downloadsHistory");allButton.removeAttribute("data-l10n-id");allButton.setAttribute("label","Все загрузки");allButton.setAttribute("tooltiptext","Все загрузки");allButton.setAttribute("aria-label","Все загрузки");
      }
      if(event.target.id==="editBookmarkPanel"&&!document.getElementById("mybro-bookmarks-window")){
        const b=html("button",{id:"mybro-bookmarks-window",type:"button"});b.textContent="Открыть избранное в отдельном окне";
        b.addEventListener("click",()=>{event.target.hidePopup();window.openDialog(BASE+"manager.html?view=bookmarks","mybro-bookmarks","chrome,dialog=no,resizable,width=900,height=650");});document.getElementById("editBookmarkPanelBottomContent").append(b);
      }
    });
    const external=window.browserDOMWindow.openURI.bind(window.browserDOMWindow);
    window.browserDOMWindow.openURI=function(uri,info,where,flags,...rest){
      if(read("reuseExternalTab",false)&&(flags&Ci.nsIBrowserDOMWindow.OPEN_EXTERNAL)&&["http","https"].includes(uri?.scheme)){
        const match=all().find(t=>t.linkedBrowser.currentURI.equals(uri));if(match){selectGroup(groupOf(match));gBrowser.selectedTab=match;return match.linkedBrowser.browsingContext;}
      }return external(uri,info,where,flags,...rest);
    };
    SS.promiseAllWindowsRestored.then(()=>{if(!window.closed&&!PrivateBrowsingUtils.isWindowPrivate(window)&&read("extraStartTab",false)&&Array.from(Services.wm.getEnumerator("navigator:browser")).length===1)newTab();});
  }
  function init() {
    if(window.myBro)return;
    window.myBro={groups,groupOf,setGroup,selectGroup,newTab,openManager,createGroup,renameGroup,removeGroup,visible,
      get current(){return current;},read,write,refresh,closeRelative,nativePage,reopenClosed,
      clearBrowsingData:()=>gDialogBox.open("chrome://browser/content/sanitize_v2.xhtml",{inBrowserWindow:true})};
    installGroups();installChrome();
    installLibraryControls().catch(error=>console.error("GrayFox library controls",error));
    current=groupOf(gBrowser.selectedTab);
    const onEvent=event=>{
      const tab=event.target;
      if(event.type==="TabOpen" && !groupOf(tab))setGroup(tab,current);
      if(!selecting&&(event.type==="TabSelect"||(event.type==="SSTabRestored"&&tab===gBrowser.selectedTab))){
        current=groupOf(tab);selections.set(current,tab);applyVisibility();
      }
      refresh();
    };
    for(const type of ["TabOpen","TabClose","TabSelect","TabMove","TabPinned","TabUnpinned","TabAttrModified","SSTabRestored"])gBrowser.tabContainer.addEventListener(type,onEvent);
    const onPrefs=()=>refresh();Services.prefs.addObserver("mybro.",onPrefs);
    window.addEventListener("unload",()=>{Services.prefs.removeObserver("mybro.",onPrefs);observer.disconnect();clearTimeout(zoomTimer);},{once:true});
    configureSearch().catch(error=>console.error("GrayFox search",error));
    DownloadsPanel.showDownloadsHistory=()=>openManager("downloads");
    DownloadsView.kItemCountLimit=9;
    window.myBro.ready=true;
    window.dispatchEvent(new CustomEvent("mybro-ready"));
    refresh();
    if(all().length===1 && ["about:blank","about:newtab","about:home","about:welcome","about:privatebrowsing"].includes(gBrowser.currentURI.spec)){
      const initialTab=gBrowser.selectedTab;
      setTimeout(()=>{
        if(window.closed||initialTab.closing||all().length!==1)return;
        // A sign-in window can stay blank while its opener prepares the destination.
        if(!window.toolbar.visible||initialTab.linkedBrowser.browsingContext.opener)return;
        const rawState=SS.getTabState(initialTab),state=typeof rawState==="string"?JSON.parse(rawState):rawState;
        const url=state.entries?.[(state.index||1)-1]?.url||initialTab.linkedBrowser.currentURI.spec;
        if(!["about:blank","about:newtab","about:home","about:welcome","about:privatebrowsing"].includes(url)||gBrowser.userTypedValue)return;
        initialTab.linkedBrowser.loadURI(Services.io.newURI("about:mybro?view=start"),{triggeringPrincipal:Services.scriptSecurityManager.getSystemPrincipal()});
      },250);
    }
  }
  if(window.gBrowserInit?.delayedStartupFinished)init();
  else {
    const ready=(subject,topic)=>{if(subject!==window)return;Services.obs.removeObserver(ready,topic);try{init();}catch(error){console.error("GrayFox startup",error);}};
    Services.obs.addObserver(ready,"browser-delayed-startup-finished");
  }
})();
