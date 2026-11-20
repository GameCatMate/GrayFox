// SPDX-License-Identifier: MIT
"use strict";
const lib=ChromeUtils.importESModule("chrome://browser/content/mybro/library.sys.mjs");
const {SearchService:search}=ChromeUtils.importESModule("moz-src:///toolkit/components/search/SearchService.sys.mjs");
const {PrivateBrowsingUtils}=ChromeUtils.importESModule("resource://gre/modules/PrivateBrowsingUtils.sys.mjs");
const embedder=window.browsingContext?.top?.embedderElement;
const owner=embedder?.documentGlobal||embedder?.ownerGlobal||(window.opener?.myBro?window.opener:null)||Services.wm.getMostRecentWindow("navigator:browser");
let app=owner.myBro;
const privateMode=PrivateBrowsingUtils.isWindowPrivate(owner);
const requestedView=new URL(location.href).searchParams.get("view")||"start";
const view=requestedView==="notes"?"start":requestedView;
const names=window.myBroSections;
const navigation=document.getElementById("navigation"),content=document.getElementById("content"),notice=document.getElementById("notice");
const P=lib.places;
function el(tag,text="",className=""){const node=document.createElement(tag);if(text)node.textContent=text;if(className)node.className=className;return node;}
function report(error){notice.textContent=error?.message||String(error);}
function run(action){return async()=>{try{await action();}catch(error){report(error);}};}
function button(label,action,className=""){const b=el("button",label,className);b.type="button";b.onclick=run(action);return b;}
function input(placeholder="",type="search"){const x=el("input");x.type=type;x.placeholder=placeholder;x.setAttribute("aria-label",placeholder);return x;}
function card(title,parent=content){const c=el("section","","card");if(title)c.append(el("h2",title,"section-title"));parent.append(c);return c;}
function layout(){const grid=el("div","","layout"),side=el("aside","","side"),body=el("div");grid.append(side,body);content.append(grid);return{side,body};}
function open(url){owner.openTrustedLinkIn(lib.webURL(url),"tab");}
function empty(parent,text="Здесь пока ничего нет"){parent.append(el("p",text,"empty"));}
function day(date){if(!date)return "Без даты";return new Intl.DateTimeFormat("ru",{day:"numeric",month:"long",year:"numeric"}).format(new Date(date));}
function bytes(n){if(!n)return"0 Б";const u=["Б","КБ","МБ","ГБ"];let i=0;while(n>=1024&&i<u.length-1){n/=1024;i++;}return n.toLocaleString("ru",{maximumFractionDigits:1})+" "+u[i];}
function field(parent,label,node){const row=el("label",label,"setting");if(node.type==="checkbox"||node.type==="radio")row.prepend(node);else row.append(node);parent.append(row);return node;}
function period(){const s=el("select");for(const[n,h]of[["За час",1],["За сутки",24],["За неделю",168],["За месяц",720],["За 3 месяца",2160],["За год",8760],["За всё время",0]]){const o=el("option",n);o.value=h;s.append(o);}return s;}
function since(select){return +select.value?Date.now()-+select.value*3600000:0;}
async function edit(title,fields,action){
 const dialog=el("dialog"),form=el("form","","editor");form.append(el("h2",title));const values={};
 for(const[name,label,value,type]of fields){const row=el("label",label);let control;
  if(Array.isArray(type)){control=el("select");for(const[id,text]of type){const o=el("option",text);o.value=id;control.append(o);}control.value=value;}
  else{control=input(label,type||"text");control.value=value||"";control.required=true;}
  row.append(control);form.append(row);values[name]=control;
 }
 const actions=el("div","","actions");actions.append(button("Отмена",()=>dialog.close()));const save=el("button","Сохранить","primary");save.type="submit";actions.append(save);form.append(actions);dialog.append(form);document.body.append(dialog);
 dialog.addEventListener("close",()=>dialog.remove(),{once:true});
 form.onsubmit=async e=>{e.preventDefault();try{await action(Object.fromEntries(Object.entries(values).map(([k,v])=>[k,v.value])));dialog.close();}catch(error){report(error);}};dialog.showModal();
}
async function showHistory(){
 const{side,body}=layout(),q=input("Поиск в истории"),periods=period();
 document.body.classList.add("history-window");content.classList.add("history-page");side.parentElement.classList.add("history-layout");body.classList.add("history-list-pane");
 periods.setAttribute("aria-label","Период очистки");side.append(q,el("hr"),periods);
 side.append(button("Очистить историю",()=>clear("history"),"link"),button("Очистить cookies",()=>clear("cookies"),"link"));
 const c=card("",body),header=el("div","","history-header"),tools=el("div","","history-tools"),count=el("span","","muted"),all=input("Выбрать все показанные записи","checkbox"),allLabel=el("label","Выбрать все","history-select-all"),items=el("div","","history-items");
 count.setAttribute("role","status");allLabel.prepend(all);header.append(el("h2","История"),tools);c.append(header,items);
 let limit=1000,request=0,busy=false,checks=[];const selected=new Map();
 const remove=button("Удалить выбранное",async()=>{
  notice.textContent="";busy=true;syncSelection();
  try{for(const item of [...selected.values()]){await lib.removeVisit(item);selected.delete(item.id);}}
  finally{busy=false;await render(false);}
 },"danger");tools.append(allLabel,count,remove);
 function syncSelection(){
  count.textContent=selected.size?"Выбрано: "+selected.size:"";remove.disabled=busy||!selected.size;all.disabled=busy||!checks.length;
  const picked=checks.filter(({visit})=>selected.has(visit.id)).length;all.checked=!!checks.length&&picked===checks.length;all.indeterminate=picked>0&&picked<checks.length;
  for(const{visit,check,row}of checks){check.checked=selected.has(visit.id);check.disabled=busy;row.classList.toggle("selected",check.checked);}
 }
 all.onchange=()=>{for(const{visit}of checks)if(all.checked)selected.set(visit.id,visit);else selected.delete(visit.id);syncSelection();};
 async function clear(kind){if(!Services.prompt.confirm(owner,"Очистка данных",(kind==="history"?"Удалить историю ":"Удалить cookies ")+periods.selectedOptions[0].textContent.toLowerCase()+"?"))return;if(kind==="history")await lib.clearHistory(since(periods),owner);else lib.clearCookies(since(periods));await render();}
 let timer;q.oninput=()=>{request++;clearTimeout(timer);timer=setTimeout(()=>run(render)(),150);};
 async function render(reset=true){
  const token=++request,rows=await lib.history(q.value,limit);if(token!==request)return;
  const scroll=reset?0:items.scrollTop;items.replaceChildren();checks=[];if(reset)selected.clear();let last="";
  if(!rows.length)empty(items);
  for(const v of rows){const d=day(v.date);if(d!==last){items.append(el("div",d,"day"));last=d;}
   const row=el("div","","row history-row"),check=input("Выбрать посещение: "+v.title+", "+d,"checkbox"),text=el("div","","grow"),address=el("span",v.url,"subtitle"),time=el("time",v.undated?"—":new Date(v.date).toLocaleTimeString("ru",{hour:"2-digit",minute:"2-digit"}),"muted");
   row.dataset.visitId=v.id;const link=button(v.title||v.url,()=>open(v.url),"name");link.title=(v.title||v.url)+"\n"+v.url;address.title=v.url;if(!v.undated)time.dateTime=new Date(v.date).toISOString();
   text.append(link,address);check.onchange=()=>{if(check.checked)selected.set(v.id,v);else selected.delete(v.id);syncSelection();};
   checks.push({visit:v,check,row});row.append(check,text,time);items.append(row);
  }
  if(rows.length===limit)items.append(button("Показать ещё",()=>{limit+=1000;return render(false);},"link"));
  syncSelection();items.scrollTop=scroll;
 }await render();
}
async function showBookmarks(){
 const{side,body}=layout(),q=input("Поиск в закладках"),treeView=el("nav","","bookmark-folders"),tools=el("div","","bookmark-sidebar-tools");
 document.body.classList.add("bookmarks-window");content.classList.add("bookmarks-page");side.parentElement.classList.add("bookmarks-layout");body.classList.add("bookmark-list-pane");
 treeView.setAttribute("aria-label","Папки избранного");tools.append(button("Новая папка",createFolder,"link"));side.append(q,tools,treeView);
 let active=P.bookmarks.toolbarGuid,tree,folders=[];const expanded=new Set([active]),parents=new Map();
 const roots=new Set([P.bookmarks.rootGuid,P.bookmarks.toolbarGuid,P.bookmarks.menuGuid,P.bookmarks.unfiledGuid,P.bookmarks.mobileGuid]);
 const rootNames={[P.bookmarks.toolbarGuid]:"Панель закладок",[P.bookmarks.menuGuid]:"Меню закладок",[P.bookmarks.unfiledGuid]:"Другие закладки",[P.bookmarks.mobileGuid]:"Мобильные закладки"};
 const children=node=>node.children||[],isFolder=node=>node.type==="text/x-moz-place-container"||node.type===2;
 const title=node=>rootNames[node.guid]||node.title||"Папка";
 function find(node,id){if(node.guid===id)return node;for(const c of children(node)){const found=find(c,id);if(found)return found;}return null;}
 async function load(){
  tree=await lib.bookmarkTree();folders=[];parents.clear();
  const gather=(node,path=[])=>{if(!isFolder(node))return;const next=node.guid===P.bookmarks.rootGuid?path:[...path,title(node)];if(next.length)folders.push([node.guid,next.join(" / ")]);for(const c of children(node)){parents.set(c.guid,node.guid);gather(c,next);}};gather(tree);
  if(!find(tree,active))active=P.bookmarks.toolbarGuid;
  for(let id=parents.get(active);id;id=parents.get(id))expanded.add(id);
  await render();
 }
 async function rename(node){await edit("Переименовать",[["title","Название",node.title||rootNames[node.guid]]],async v=>{await P.bookmarks.update({guid:node.guid,title:v.title});await load();});}
 async function createFolder(){await edit("Новая папка",[["title","Название",""]],async v=>{const folder=await P.bookmarks.insert({parentGuid:active,title:v.title,type:P.bookmarks.TYPE_FOLDER});expanded.add(active);active=folder.guid;await load();});}
 async function move(node){await edit("Перенести",[["parent","Папка",parents.get(node.guid)||active,folders.filter(([id])=>!find(node,id))]],async v=>{await P.bookmarks.update({guid:node.guid,parentGuid:v.parent,index:P.bookmarks.DEFAULT_INDEX});await load();});}
 async function remove(node){
  if(roots.has(node.guid))return;
  if(isFolder(node)&&!Services.prompt.confirm(owner,"Удаление","Удалить папку со всеми закладками?"))return;
  if(active===node.guid)active=parents.get(node.guid)||P.bookmarks.toolbarGuid;
  await P.bookmarks.remove(node.guid);await load();
 }
 function draggable(node,item){node.draggable=!roots.has(item.guid);node.ondragstart=e=>{e.stopPropagation();e.dataTransfer.setData("text/mybro-bookmark",item.guid);};}
 function dropTarget(node,id){
  node.ondragover=e=>e.preventDefault();node.addEventListener("drop",e=>{e.preventDefault();e.stopPropagation();const guid=e.dataTransfer.getData("text/mybro-bookmark");if(guid&&guid!==id)run(async()=>{await P.bookmarks.update({guid,parentGuid:id,index:P.bookmarks.DEFAULT_INDEX});expanded.add(id);await load();})();});
 }
 function selectFolder(id){active=id;for(let parent=parents.get(id);parent;parent=parents.get(parent))expanded.add(parent);return render();}
 function renderTree(focusId){
  treeView.replaceChildren();const list=el("ul","","bookmark-tree");treeView.append(list);
  const visit=(node,parent)=>{
   const branch=el("li"),row=el("div","","bookmark-folder-row"),nested=children(node).filter(isFolder),open=expanded.has(node.guid),childList=el("ul");
   childList.id="bookmark-children-"+node.guid;childList.hidden=!open;
   const toggle=button("",()=>{if(open)expanded.delete(node.guid);else expanded.add(node.guid);renderTree(toggle.id);},"folder-toggle");
   toggle.id="bookmark-toggle-"+node.guid;toggle.title=(open?"Свернуть ":"Раскрыть ")+title(node);toggle.setAttribute("aria-label",toggle.title);toggle.disabled=!nested.length;
   if(nested.length){toggle.setAttribute("aria-expanded",String(open));toggle.setAttribute("aria-controls",childList.id);}
   const name=button("",async()=>{await selectFolder(node.guid);document.getElementById(name.id)?.focus();},"folder-select"+(active===node.guid?" active":""));
   name.id="bookmark-folder-"+node.guid;name.title=title(node);if(active===node.guid)name.setAttribute("aria-current","page");
   const icon=el("span","","folder-icon");icon.setAttribute("aria-hidden","true");name.append(icon,el("span",title(node),"folder-label"));row.append(toggle,name);draggable(row,node);dropTarget(row,node.guid);
   branch.append(row,childList);parent.append(branch);if(open)for(const child of nested)visit(child,childList);
  };
  for(const node of children(tree).filter(isFolder))if(node.guid===P.bookmarks.toolbarGuid||children(node).length||!roots.has(node.guid))visit(node,list);
  if(focusId)document.getElementById(focusId)?.focus();
 }
 async function render(){
  renderTree();body.replaceChildren();const node=find(tree,active)||tree,c=card("",body),header=el("div","","bookmark-header"),actions=el("div","","bookmark-tools");
  const heading=el("h2",q.value?"Результаты поиска":title(node));heading.title=heading.textContent;
  actions.append(button("Добавить закладку",()=>edit("Новая закладка",[["title","Название",""],["url","Адрес","https://","url"]],async v=>{await P.bookmarks.insert({parentGuid:active,title:v.title,url:lib.webURL(v.url)});await load();}),"link"));
  if(!roots.has(active))actions.append(button("Переименовать папку",()=>rename(node),"link"),button("Удалить папку",()=>remove(node),"danger"));
  header.append(heading,actions);const itemsView=el("div","","bookmark-items");c.append(header,itemsView);dropTarget(itemsView,active);
  let items=children(node);if(q.value){const all=[];const walk=n=>{for(const x of children(n)){if(x.uri||x.url)all.push(x);walk(x);}};walk(tree);items=all.filter(x=>((x.title||"")+" "+(x.uri||x.url)).toLowerCase().includes(q.value.toLowerCase()));}
  if(!items.length)empty(itemsView);
  for(const item of items){
   const folder=isFolder(item),row=el("div","","row bookmark-row"),text=el("div","","grow"),url=item.uri||item.url,label=item.title||url||"Папка";row.dataset.bookmarkGuid=item.guid;draggable(row,item);if(folder)dropTarget(row,item.guid);
   const name=button("",()=>folder?selectFolder(item.guid):open(url),"name");name.title=label+(url?"\n"+url:"");
   const icon=el("span","",folder?"folder-icon":"bookmark-icon");icon.setAttribute("aria-hidden","true");name.append(icon,el("span",label,"bookmark-label"));text.append(name);
   const address=el("span",url||"Папка","subtitle");address.title=url||"Папка";text.append(address);
   const buttons=el("div","","row-actions");buttons.append(button("Изменить",()=>folder?rename(item):edit("Изменить закладку",[["title","Название",item.title],["url","Адрес",url,"url"]],async v=>{await P.bookmarks.update({guid:item.guid,title:v.title,url:lib.webURL(v.url)});await load();})),button("Перенести",()=>move(item)),button("Удалить",()=>remove(item)));
   row.append(text,buttons);itemsView.append(row);
  }
 }q.oninput=run(render);await load();
}
async function showDownloads(){
 const{side,body}=layout(),q=input("Поиск в загрузках");side.append(q);let month="",hide=false,rows=[];
 const list=await lib.downloads.getList(privateMode?lib.downloads.PRIVATE:lib.downloads.PUBLIC);
 const observer={onDownloadAdded:reload,onDownloadChanged:reload,onDownloadRemoved:reload};let pending;
 function reload(){clearTimeout(pending);pending=setTimeout(()=>run(render)(),80);}
 list.addView(observer);window.addEventListener("unload",()=>{list.removeView(observer);clearTimeout(pending);},{once:true});
 const key=d=>new Date(d.startTime).toISOString().slice(0,7);
 async function render(){rows=(await list.getAll()).sort((a,b)=>b.startTime-a.startTime);side.querySelectorAll(".month,.download-tools").forEach(x=>x.remove());
  for(const m of [...new Set(rows.map(key))]){const label=new Intl.DateTimeFormat("ru",{month:"long",year:"numeric"}).format(new Date(m+"-01"));side.append(button(label,()=>{month=m;render();},"month "+(month===m?"active":"")));}
  const tools=el("div","","download-tools");tools.append(el("hr"),button("Открыть папку",lib.downloadFolder),button(hide?"Показать загруженные":"Скрыть загруженные",()=>{hide=!hide;render();}),button("Очистить список",async()=>{await list.removeFinished();await render();}));side.append(tools);
  body.replaceChildren();const c=card(month?new Intl.DateTimeFormat("ru",{month:"long",year:"numeric"}).format(new Date(month+"-01")):"Загрузки",body);let last="",shown=0;
  for(const d of rows){const path=d.target.path,name=path.split("/").pop();if((month&&key(d)!==month)||(hide&&d.succeeded)||!(name+" "+d.source.url).toLowerCase().includes(q.value.toLowerCase()))continue;shown++;
   const date=day(d.startTime);if(date!==last){c.append(el("div",date,"download-day"));last=date;}
   const row=el("div","","row"),icon=el("img","","file-icon"),text=el("div","","grow");icon.alt="";icon.src="moz-icon://"+encodeURIComponent(name)+"?size=32";
   const line=el("div","","name"),nameButton=button(name,()=>d.succeeded?d.launch():undefined);line.append(nameButton,el("small",bytes(d.totalBytes||d.currentBytes)));text.append(line,el("div",d.source.url,"subtitle"));
   if(!d.stopped){const progress=el("progress");progress.max=d.totalBytes||1;progress.value=d.currentBytes;text.append(progress);text.append(el("div",bytes(d.currentBytes)+" из "+bytes(d.totalBytes),"subtitle"));}
   else if(d.error)text.append(el("div","Ошибка загрузки","subtitle"));else if(d.canceled)text.append(el("div","Загрузка отменена","subtitle"));else if(!d.target.exists)text.append(el("div","Файл удалён","subtitle"));
   const actions=el("div","","row-actions");if(d.succeeded&&d.target.exists)actions.append(button("Показать в папке",()=>lib.openFolder(path)));
   if(!d.stopped)actions.append(button("Отменить",()=>d.cancel()));else if(!d.succeeded)actions.append(button("Повторить",()=>d.start()));
   actions.append(button("Убрать из списка",async()=>{if(!d.stopped)await d.cancel();await list.remove(d);await d.finalize(false);}));row.append(icon,text,actions);c.append(row);
  }if(!shown)empty(c);
 }q.oninput=run(render);await render();
}
function boolSetting(parent,label,key,fallback=true,invert=false){const check=input(label,"checkbox");check.checked=invert?!Services.prefs.getBoolPref(key,fallback):Services.prefs.getBoolPref(key,fallback);check.onchange=()=>Services.prefs.setBoolPref(key,invert?!check.checked:check.checked);field(parent,label,check);}
function ownBool(parent,label,key,fallback=true){const check=input(label,"checkbox");check.checked=app.read(key,fallback);check.onchange=()=>app.write(key,check.checked);field(parent,label,check);}
function select(parent,label,options,value,action){const s=el("select");for(const[id,text]of options){const o=el("option",text);o.value=id;s.append(o);}s.value=value;s.onchange=run(()=>action(s.value));field(parent,label,s);return s;}
async function showSettings(){
 const{side,body}=layout(),q=input("Поиск настроек");side.append(q);
 const sections={general:"Общие настройки",interface:"Интерфейс",tools:"Инструменты",sites:"Сайты",system:"Системные",accessibility:"Специальные возможности"};const cards={};
 for(const[id,name]of Object.entries(sections)){const c=card(name,body);c.id=id;cards[id]=c;side.append(button(name,()=>c.scrollIntoView({behavior:app.read("reduceMotion",false)?"instant":"smooth",block:"start"})));}
 const {general:g,interface:i,tools:t,sites:s,system:y,accessibility:a}=cards;
 const primary=el("section","","card");primary.append(el("h2","Сделать GrayFox основным браузером?"),el("p","В нём будут открываться ссылки из других приложений.","muted"),button("Сделать основным",()=>ChromeUtils.importESModule("moz-src:///browser/components/shell/ShellService.sys.mjs").ShellService.setAsDefault(),"primary"));body.prepend(primary);
 g.append(el("h3","Профили"),button("Управление профилями и перенос данных",()=>app.openManager("profile"),"link"));
 g.append(el("h3","Поиск"));await search.init();const engines=(await search.getEngines()).filter(e=>!e.hidden),options=engines.map(e=>[e.id,e.name]);
 select(g,"Поисковая система",options,search.defaultEngine.id,id=>search.setDefault(engines.find(e=>e.id===id),search.CHANGE_REASON.USER));
 select(g,"Поиск в инкогнито",options,search.defaultPrivateEngine.id,id=>search.setDefaultPrivate(engines.find(e=>e.id===id),search.CHANGE_REASON.USER));
 boolSetting(g,"Предлагать поисковые подсказки", "browser.search.suggest.enabled");boolSetting(g,"Предлагать сайты из истории","browser.urlbar.suggest.history");boolSetting(g,"Предлагать закладки","browser.urlbar.suggest.bookmark");boolSetting(g,"Предлагать открытые вкладки","browser.urlbar.suggest.openpage");boolSetting(g,"Подсказки в инкогнито","browser.search.suggest.enabled.private",false);
 i.append(el("h3","Цветовая схема"));const themes=el("div","","themes");for(const[value,label]of[["system","Как в системе"],["light","Светлая"],["dark","Тёмная"]]){const b=button(label,()=>{app.write("theme",value);document.documentElement.dataset.theme=value;themes.querySelectorAll("button").forEach(x=>x.classList.toggle("active",x===b));},"theme "+(app.read("theme","system")===value?"active":""));b.dataset.value=value;themes.append(b);}i.append(themes);
 i.append(el("h3","Новая вкладка"));ownBool(i,"Часы","startClock",false);ownBool(i,"Поисковая строка","startSearch");ownBool(i,"Плитки закладок","startTiles");
 i.append(el("h3","Вкладки и группы"));const restore=input("Восстанавливать вкладки при запуске","checkbox");restore.checked=Services.prefs.getIntPref("browser.startup.page",3)===3;restore.onchange=()=>Services.prefs.setIntPref("browser.startup.page",restore.checked?3:1);field(i,"Восстанавливать вкладки при запуске",restore);ownBool(i,"Открывать дополнительную новую вкладку при запуске","extraStartTab",false);ownBool(i,"Уменьшить анимацию","reduceMotion",false);
 select(i,"Панель закладок",[["always","На всех страницах"],["newtab","На новой вкладке"],["never","Скрыта"]],Services.prefs.getStringPref("browser.toolbars.bookmarks.visibility","always"),v=>{Services.prefs.setStringPref("browser.toolbars.bookmarks.visibility",v);for(const w of Services.wm.getEnumerator("navigator:browser"))w.BookmarkingUI?.updateBookmarkToolbarVisibility();});
 t.append(el("h3","Автозаполнение"));boolSetting(t,"Предлагать сохранять пароли","signon.rememberSignons");boolSetting(t,"Автоматически подставлять пароли","signon.autofillForms");t.append(button("Сохранённые пароли",()=>app.nativePage("about:logins"),"link"));
 t.append(el("h3","Загруженные файлы"));boolSetting(t,"Всегда спрашивать, куда сохранять файлы","browser.download.useDownloadDir",true,true);t.append(button("Изменить папку загрузок…",async()=>{const p=Cc["@mozilla.org/filepicker;1"].createInstance(Ci.nsIFilePicker);p.init(owner.browsingContext,"Папка загрузок",Ci.nsIFilePicker.modeGetFolder);if(await new Promise(r=>p.open(r))===Ci.nsIFilePicker.returnOK){Services.prefs.setComplexValue("browser.download.dir",Ci.nsIFile,p.file);Services.prefs.setIntPref("browser.download.folderList",2);}},"link"));
 t.append(el("h3","Просмотр файлов"));boolSetting(t,"Открывать PDF-файлы в браузере","pdfjs.disabled",false,true);t.append(button("Снимок страницы",()=>{ChromeUtils.importESModule("moz-src:///browser/components/screenshots/ScreenshotsUtils.sys.mjs").ScreenshotsUtils.start(owner.gBrowser.selectedBrowser);},"link"));
 s.append(el("h3","Разрешения сайтов"));for(const[key,label]of[["camera","Камера"],["microphone","Микрофон"],["desktop-notification","Уведомления"],["geo","Местоположение"]])select(s,label,[["0","Спрашивать"],["2","Блокировать"]],Services.prefs.getIntPref("permissions.default."+key,0),v=>Services.prefs.setIntPref("permissions.default."+key,+v));
 select(s,"Минимальный размер шрифта",[["0","Нет ограничения"],["12","12"],["14","14"],["16","16"],["18","18"]],Services.prefs.getIntPref("font.minimum-size.x-western",0),v=>{for(const language of["x-western","x-cyrillic"])Services.prefs.setIntPref("font.minimum-size."+language,+v);});
 select(s,"Масштаб по умолчанию",[80,90,100,110,120,130,150,175,200].map(v=>[String(v),v+"%"]),app.read("pageZoom",100),v=>lib.setDefaultZoom(owner,+v));s.append(button("Расширенные настройки сайтов",()=>app.nativePage("about:preferences#privacy"),"link"));
 y.append(el("h3","Сеть"));select(y,"Режим только HTTPS",[["off","Выключен"],["private","Только в инкогнито"],["all","Во всех окнах"]],Services.prefs.getBoolPref("dom.security.https_only_mode",false)?"all":Services.prefs.getBoolPref("dom.security.https_only_mode_pbm",false)?"private":"off",v=>{Services.prefs.setBoolPref("dom.security.https_only_mode",v==="all");Services.prefs.setBoolPref("dom.security.https_only_mode_pbm",v!=="off");});y.append(button("Прокси и сеть",()=>app.nativePage("about:preferences#general"),"link"));
 y.append(el("h3","Производительность"));boolSetting(y,"Использовать аппаратное ускорение (после перезапуска)","layers.acceleration.disabled",false,true);boolSetting(y,"Выгружать неиспользуемые вкладки при нехватке памяти","browser.tabs.unloadOnLowMemory");
 y.append(el("h3","Конфиденциальность"),button("Очистить историю и cookies",()=>app.openManager("history"),"link"),button("Сертификаты, язык и безопасность",()=>app.nativePage("about:preferences#privacy"),"link"));
 a.append(el("h3","Доступ к контенту"));boolSetting(a,"Навигация по тексту с помощью курсора","accessibility.browsewithcaret",false);a.append(button("Шрифты, языки и специальные возможности",()=>app.nativePage("about:preferences#general"),"link"));
 y.append(button("Сбросить настройки",async()=>{
  if(!Services.prompt.confirm(owner,"Сброс настроек","Вернуть настройки GrayFox по умолчанию? Вкладки, группы, история, закладки и пароли сохранятся."))return;
  for(const key of ["theme","reduceMotion","pageZoom","startClock","startSearch","startTiles","extraStartTab","reuseExternalTab"])Services.prefs.clearUserPref("mybro."+key);
  const keys=["browser.startup.page","browser.toolbars.bookmarks.visibility","browser.search.suggest.enabled","browser.search.suggest.enabled.private","browser.urlbar.suggest.history","browser.urlbar.suggest.bookmark","browser.urlbar.suggest.openpage","signon.rememberSignons","signon.autofillForms","browser.download.useDownloadDir","browser.download.dir","browser.download.folderList","pdfjs.disabled","font.minimum-size.x-western","font.minimum-size.x-cyrillic","permissions.default.camera","permissions.default.microphone","permissions.default.desktop-notification","permissions.default.geo","dom.security.https_only_mode","dom.security.https_only_mode_pbm","layers.acceleration.disabled","browser.tabs.unloadOnLowMemory","accessibility.browsewithcaret"];
  for(const key of keys)Services.prefs.clearUserPref(key);await lib.setDefaultZoom(owner,100);
  const google=engines.find(e=>e.name==="Google"),duck=engines.find(e=>e.name.includes("DuckDuckGo"));if(google)await search.setDefault(google,search.CHANGE_REASON.USER);if(duck)await search.setDefaultPrivate(duck,search.CHANGE_REASON.USER);location.reload();
 },"link"));
 q.oninput=()=>{const value=q.value.toLowerCase();primary.hidden=!!value&&!primary.textContent.toLowerCase().includes(value);for(const c of Object.values(cards))c.hidden=!!value&&!c.textContent.toLowerCase().includes(value);};
}
async function showProfile(){
 const c=card("Мой профиль");c.append(el("p","Данные GrayFox хранятся в текущем профиле. Старый myBro остаётся отдельным приложением."));c.append(button("Профили GrayFox",()=>app.nativePage("about:profiles"),"link"),button("Расширения",()=>app.nativePage("about:addons"),"link"),button("Пароли",()=>app.nativePage("about:logins"),"link"));
 c.append(el("h3","Перенос профиля"),el("p","Архив GrayFox зашифрован парольной фразой. В него входят вкладки и группы, история, закладки, сохранённые пароли и настройки GrayFox. Cookies, расширения и файлы загрузок в этот переносимый архив не входят.","muted"));
 c.append(button("Экспортировать зашифрованный профиль…",()=>edit("Защитите архив",[["phrase","Парольная фраза от 12 символов","","password"],["confirm","Повторите фразу","","password"]],async v=>{if(v.phrase!==v.confirm)throw new Error("Фразы не совпадают");const file=await lib.chooseFile(owner,"Экспорт профиля",true);if(!file)return;const archive=await lib.encrypt(await lib.exportProfile(owner),v.phrase);await IOUtils.write(file.path,archive,{mode:"overwrite",permissions:0o600});notice.textContent="Профиль экспортирован";}),"link"));
 c.append(button("Импортировать профиль…",async()=>{const file=await lib.chooseFile(owner,"Импорт профиля");if(!file)return;const stat=await IOUtils.stat(file.path);if(stat.size>128*1024*1024)throw new Error("Архив больше 128 МиБ");await edit("Открыть архив",[["phrase","Парольная фраза","","password"]],async v=>{const data=await lib.decrypt(await IOUtils.read(file.path),v.phrase);const result=await lib.importProfile(data,owner);notice.textContent=`Импортировано: ${result.tabs} вкладок, ${result.passwords} паролей`;});},"link"));
 c.append(el("h3","Импорт из других браузеров"),button("Открыть импорт данных…",()=>ChromeUtils.importESModule("moz-src:///browser/components/migration/MigrationUtils.sys.mjs").MigrationUtils.showMigrationWizard(owner,{}),"link"),el("p","Для прежнего myBro предусмотрен локальный перенос Firefox/migrate.py. Источники Vivaldi и Яндекс, не распознанные штатным импортом, можно перенести через сохранённую старую версию myBro.","muted"));
}
async function showStart(){navigation.hidden=true;content.className="start";if(app.read("startClock",false)){const clock=el("div","","clock");const tick=()=>clock.textContent=new Date().toLocaleTimeString("ru",{hour:"2-digit",minute:"2-digit"});tick();const timer=setInterval(tick,1000);window.addEventListener("unload",()=>clearInterval(timer),{once:true});content.append(clock);}
 const logo=el("img","","start-logo");logo.src="chrome://browser/content/mybro/AppIcon.png";logo.alt="GrayFox";content.append(logo,el("h1",privateMode?"GrayFox · Инкогнито":"GrayFox"));
 if(app.read("startSearch",true)){const form=el("form","","search"),q=input("Поиск");q.type="text";const submit=el("button","⌕");submit.type="submit";form.append(q,submit);form.onsubmit=run(async()=>{});form.addEventListener("submit",e=>{e.preventDefault();owner.gURLBar.search(q.value);});q.oninput=()=>{if(q.value)owner.gURLBar.search(q.value);};content.append(form);}
 if(privateMode){content.append(el("p","История и cookies этого окна не сохранятся после закрытия приватных окон. Скачанные файлы и добавленные закладки сохраняются.","private"));return;}
 if(app.read("startTiles",true)){const tree=await lib.bookmarkTree(),tiles=el("div","","tiles"),items=[];const walk=n=>{for(const c of n.children||[]){if(c.uri||c.url)items.push(c);if(items.length<12)walk(c);}};walk(tree);for(const item of items.slice(0,12))tiles.append(button(item.title||new URL(item.uri||item.url).hostname,()=>open(item.uri||item.url),"tile"));content.append(tiles);}
}
async function init(){
 const theme=app.read("theme","system");document.documentElement.dataset.theme=theme==="system"?(matchMedia("(prefers-color-scheme:light)").matches?"light":"dark"):theme;
 window.renderMyBroNavigation(navigation,app,privateMode,view);
 document.title=names[view]||"Новая вкладка";
 if(privateMode&&["profile","history"].includes(view)){empty(content,"Этот раздел недоступен в инкогнито");return;}
 const pages={history:showHistory,bookmarks:showBookmarks,downloads:showDownloads,settings:showSettings,profile:showProfile,start:showStart};
 await(pages[view]||showStart)();document.documentElement.dataset.ready="true";
}
function start(){app=owner.myBro;init().catch(report);}
if(app?.ready)start();else owner.addEventListener("mybro-ready",start,{once:true});
