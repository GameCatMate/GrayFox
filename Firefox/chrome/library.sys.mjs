// SPDX-License-Identifier: MIT
const { PlacesUtils: P }=ChromeUtils.importESModule("resource://gre/modules/PlacesUtils.sys.mjs");
const { Downloads }=ChromeUtils.importESModule("resource://gre/modules/Downloads.sys.mjs");
const { SessionStore: SS }=ChromeUtils.importESModule("moz-src:///browser/components/sessionstore/SessionStore.sys.mjs");
export const places=P;
export const downloads=Downloads;
export function webURL(value){const url=new URL(value);if(!["http:","https:"].includes(url.protocol)||url.username||url.password)throw new Error("Допустим только адрес HTTP(S)");return url.href;}
const overflowPath=PathUtils.join(PathUtils.profileDir,"mybro-history-overflow.json");
let overflowQueue=Promise.resolve();
async function readOverflow(){return await IOUtils.exists(overflowPath)?IOUtils.readJSON(overflowPath):[];}
function updateOverflow(change){
 const operation=overflowQueue.then(async()=>IOUtils.writeJSON(overflowPath,change(await readOverflow()),{tmpPath:overflowPath+".tmp",permissions:0o600}));
 overflowQueue=operation.catch(()=>{});return operation;
}
export async function history(query="",limit=1000){
 const db=await P.promiseDBConnection();
 const rows=await db.executeCached(`SELECT v.id,p.url,p.title,v.visit_date FROM moz_historyvisits v JOIN moz_places p ON p.id=v.place_id WHERE p.url LIKE :q OR p.title LIKE :q ORDER BY v.visit_date DESC LIMIT :limit`,{q:"%"+query+"%",limit});
 await overflowQueue;
 const extra=(await readOverflow()).filter(e=>(e.url+" "+e.title).toLowerCase().includes(query.toLowerCase()));
 return [...rows.map(r=>({id:r.getResultByName("id"),url:r.getResultByName("url"),title:r.getResultByName("title")||r.getResultByName("url"),date:r.getResultByName("visit_date")/1000})),...extra].sort((a,b)=>b.date-a.date).slice(0,limit);
}
export async function removeVisit(visit){
 if(String(visit.id).startsWith("extra:")){await updateOverflow(rows=>rows.filter(e=>e.id!==visit.id));return;}
 const date=new Date(visit.date);await P.history.removeVisitsByFilter({url:visit.url,beginDate:date,endDate:new Date(visit.date+1),limit:1});
}
export async function clearHistory(since,window){
 await updateOverflow(rows=>since?rows.filter(e=>e.date<since):[]);
 if(since)await P.history.removeVisitsByFilter({beginDate:new Date(since)});else await P.history.clear();
 for(const w of Services.wm.getEnumerator("navigator:browser")){
  if(!SS.getClosedTabCountForWindow)continue;
  for(let i=SS.getClosedTabCountForWindow(w)-1;i>=0;i--){
   const tab=SS.getClosedTabDataForWindow(w)[i];if(!since||tab.closedAt>=since)SS.forgetClosedTab(w,i);
  }
 }
}
export function clearCookies(since){
 let count=0;for(const c of Services.cookies.cookies){
  if(c.originAttributes.privateBrowsingId)continue;
  if(!since||c.creationTime/1000>=since){Services.cookies.remove(c.host,c.name,c.path,c.originAttributes);count++;}
 }return count;
}
export async function bookmarkTree(){return P.promiseBookmarksTree(P.bookmarks.rootGuid);}
export async function chooseFile(window,title,save=false,extension="mybroprofile"){
 const picker=Cc["@mozilla.org/filepicker;1"].createInstance(Ci.nsIFilePicker);
 picker.init(window.browsingContext,title,save?Ci.nsIFilePicker.modeSave:Ci.nsIFilePicker.modeOpen);
 picker.appendFilter("Профиль GrayFox","*."+extension);picker.appendFilters(Ci.nsIFilePicker.filterAll);
 picker.defaultExtension=extension;picker.defaultString="GrayFox."+extension;
 const result=await new Promise(resolve=>picker.open(resolve));
 return [Ci.nsIFilePicker.returnOK,Ci.nsIFilePicker.returnReplace].includes(result)?picker.file:null;
}
export function openFolder(path){const file=Cc["@mozilla.org/file/local;1"].createInstance(Ci.nsIFile);file.initWithPath(path);file.reveal();}
export async function downloadFolder(){const path=await Downloads.getPreferredDownloadsDirectory();const file=Cc["@mozilla.org/file/local;1"].createInstance(Ci.nsIFile);file.initWithPath(path);file.launch();}
export async function encrypt(data,phrase){
 if(phrase.length<12||new TextEncoder().encode(phrase).length>1024)throw new Error("Парольная фраза — от 12 символов");
 const prefix=new Uint8Array(24);prefix.set(new TextEncoder().encode("MYBROPF1"));crypto.getRandomValues(prefix.subarray(8));
 const nonce=crypto.getRandomValues(new Uint8Array(12));const key=await derive(phrase,prefix.subarray(8));
 const body=new Uint8Array(await crypto.subtle.encrypt({name:"AES-GCM",iv:nonce,additionalData:prefix},key,new TextEncoder().encode(JSON.stringify(data))));
 if(body.length>128*1024*1024-36)throw new Error("Профиль превышает 128 МиБ");
 const out=new Uint8Array(36+body.length);out.set(prefix);out.set(nonce,24);out.set(body,36);return out;
}
async function derive(phrase,salt){
 const input=await crypto.subtle.importKey("raw",new TextEncoder().encode(phrase),"PBKDF2",false,["deriveKey"]);
 return crypto.subtle.deriveKey({name:"PBKDF2",salt,iterations:600000,hash:"SHA-256"},input,{name:"AES-GCM",length:256},false,["encrypt","decrypt"]);
}
export async function decrypt(bytes,phrase){
 if(bytes.length<52||bytes.length>128*1024*1024||new TextDecoder().decode(bytes.subarray(0,8))!=="MYBROPF1")throw new Error("Неверный формат профиля");
 try{const key=await derive(phrase,bytes.subarray(8,24));return JSON.parse(new TextDecoder().decode(await crypto.subtle.decrypt({name:"AES-GCM",iv:bytes.subarray(24,36),additionalData:bytes.subarray(0,24)},key,bytes.subarray(36))));}
 catch{throw new Error("Парольная фраза неверна или архив повреждён");}
}
export function setDefaultZoom(window,value){
 if(!Number.isInteger(value)||value<30||value>300)throw new Error("Неверный масштаб");
 window.myBro.write("pageZoom",value);
 const service=Cc["@mozilla.org/content-pref/service;1"].getService(Ci.nsIContentPrefService2);
 return new Promise((resolve,reject)=>service.setGlobal("browser.content.full-zoom",value/100,Cu.createLoadContext(),{handleCompletion(){window.FullZoom.setZoom(value/100);resolve();},handleError:reject}));
}
const nativeKeys=["browser.startup.page","browser.toolbars.bookmarks.visibility","browser.search.suggest.enabled","browser.search.suggest.enabled.private","browser.urlbar.suggest.history","browser.urlbar.suggest.bookmark","browser.urlbar.suggest.openpage","signon.rememberSignons","signon.autofillForms","browser.download.useDownloadDir","pdfjs.disabled","font.minimum-size.x-western","font.minimum-size.x-cyrillic","permissions.default.camera","permissions.default.microphone","permissions.default.desktop-notification","permissions.default.geo","dom.security.https_only_mode","dom.security.https_only_mode_pbm","layers.acceleration.disabled","browser.tabs.unloadOnLowMemory","accessibility.browsewithcaret"];
function nativePreferences(){
 const values={};for(const key of nativeKeys){const type=Services.prefs.getPrefType(key);if(type===128)values[key]=Services.prefs.getBoolPref(key);else if(type===64)values[key]=Services.prefs.getIntPref(key);else if(type===32)values[key]=Services.prefs.getStringPref(key);}return values;
}
async function restoreNativePreferences(data){
 for(const [key,value]of Object.entries(data.nativePreferences||{})){
  if(!nativeKeys.includes(key))continue;const type=Services.prefs.getPrefType(key);
  if(type===128&&typeof value==="boolean")Services.prefs.setBoolPref(key,value);
  else if(type===64&&Number.isInteger(value)&&value>=0&&value<=72)Services.prefs.setIntPref(key,value);
  else if(key==="browser.toolbars.bookmarks.visibility"&&["always","never","newtab"].includes(value))Services.prefs.setStringPref(key,value);
 }
 if(data.searchEngines){
  const {SearchService:S}=ChromeUtils.importESModule("moz-src:///toolkit/components/search/SearchService.sys.mjs");await S.init();const engines=await S.getEngines();
  const regular=engines.find(e=>e.id===data.searchEngines.regular),privateEngine=engines.find(e=>e.id===data.searchEngines.private);
  if(regular)await S.setDefault(regular,S.CHANGE_REASON.USER);if(privateEngine)await S.setDefaultPrivate(privateEngine,S.CHANGE_REASON.USER);
 }
}
export async function exportProfile(window){
 const logins=await Services.logins.getAllLogins(),session=SS.getWindowState(window);
 const {SearchService:S}=ChromeUtils.importESModule("moz-src:///toolkit/components/search/SearchService.sys.mjs");await S.init();
 return {format:"mybro-gecko-1",nativePreferences:nativePreferences(),searchEngines:{regular:S.defaultEngine.id,private:S.defaultPrivateEngine.id},session:typeof session==="string"?JSON.parse(session):session,groups:window.myBro.groups(),
  bookmarks:await bookmarkTree(),history:await history("",1000000),
  passwords:logins.map(l=>({origin:l.origin,formActionOrigin:l.formActionOrigin,httpRealm:l.httpRealm,username:l.username,password:l.password,usernameField:l.usernameField,passwordField:l.passwordField})),
  preferences:Object.fromEntries(Services.prefs.getChildList("mybro.").filter(k=>Services.prefs.getPrefType(k)===Services.prefs.PREF_STRING).map(k=>[k,Services.prefs.getStringPref(k)]))};
}
export async function importPasswords(entries){
 if(!Array.isArray(entries)||entries.length>100000)throw new Error("Некорректный список паролей");
 const existing=await Services.logins.getAllLogins(),seen=new Set(existing.map(l=>l.origin+"\n"+l.username));let added=0;
 for(const entry of entries){
  const origin=typeof entry.origin==="string"?new URL(webURL(entry.origin)).origin:new URL(webURL(entry.origin.url||`${entry.origin.scheme}://${entry.origin.host}${entry.origin.port?":"+entry.origin.port:""}`)).origin;
  if(typeof entry.username!=="string"||typeof entry.password!=="string"||!entry.password||entry.password.length>4096)throw new Error("Некорректная запись пароля");
  const id=origin+"\n"+entry.username;if(seen.has(id))continue;
  const login=Cc["@mozilla.org/login-manager/loginInfo;1"].createInstance(Ci.nsILoginInfo);
  login.init(origin,entry.httpRealm?null:(entry.formActionOrigin||""),entry.httpRealm||null,entry.username,entry.password,entry.usernameField||"",entry.passwordField||"");
  await Services.logins.addLoginAsync(login);seen.add(id);added++;
 }return added;
}
function planHistory(entries,legacy){
 if(!Array.isArray(entries)||entries.length>1000000)throw new Error("Слишком большая история");
 const pages=new Map(),overflow=[],seen=new Set(),nativeHistory=Cc["@mozilla.org/browser/nav-history-service;1"].getService(Ci.nsINavHistoryService);let count=0;
 for(const e of entries){
  let url;try{url=webURL(e.url);}catch{continue;}
  const undated=!!e.undated||(legacy&&(e.visitedAt===undefined||e.visitedAt===null));
  const time=undated?0:legacy?(e.visitedAt+978307200)*1000:e.date;
  if(!Number.isFinite(time)||time<0)continue;
  const key=url+"\n"+Math.trunc(time);
  if(undated||!nativeHistory.canAddURI(Services.io.newURI(url))||url.length>65536||seen.has(key)||String(e.id||"").startsWith("extra:")){
   const id=String(e.id||crypto.randomUUID());overflow.push({id:id.startsWith("extra:")?id:"extra:"+id,url,title:String(e.title||url),date:time,undated});count++;continue;
  }
  seen.add(key);
  if(!pages.has(url))pages.set(url,{url,title:String(e.title||url),visits:[]});pages.get(url).visits.push({date:new Date(time),transition:P.history.TRANSITIONS.LINK});count++;
 }
 return {pages:[...pages.values()],overflow,count};
}
async function mergeOverflow(incoming){
 if(incoming.length)await updateOverflow(rows=>{const ids=new Set(rows.map(e=>e.id));return [...rows,...incoming.filter(e=>!ids.has(e.id))];});
}
export async function preserveLegacyHistoryExtras(entries){
 const plan=planHistory(entries,true);await mergeOverflow(plan.overflow);return plan.overflow.length;
}
export async function importHistory(entries,legacy=false){
 const {pages,overflow,count}=planHistory(entries,legacy);
 for(const page of pages)P.validatePageInfo(page);
 for(let i=0;i<pages.length;i+=250)await P.history.insertMany(pages.slice(i,i+250));
 await mergeOverflow(overflow);return count;
}

export async function importBookmarkNodes(node,parentGuid){
 let count=0;for(const child of node.children||[]){
  if(child.type==="text/x-moz-place-container"||child.type===2){
   const folder=await P.bookmarks.insert({parentGuid,title:String(child.title||"Папка"),type:P.bookmarks.TYPE_FOLDER});
   count+=await importBookmarkNodes(child,folder.guid);
  }else if(child.url||child.uri){
   try{await P.bookmarks.insert({parentGuid,title:String(child.title||""),url:webURL(child.url||child.uri)});count++;}catch(error){if(error.name!=="TypeError")console.warn("myBro bookmark skipped");}
  }
 }return count;
}
function safeIcon(value){
 if(typeof value!=="string"||value.length>1000000)return "";
 if(/^data:image\/(png|jpeg|gif|x-icon|vnd.microsoft.icon);base64,[a-zA-Z0-9+/=]+$/.test(value))return value;
 try{return webURL(value);}catch{return "";}
}
function safeSession(session,groups){
 const source=session?.windows?.[0];if(!source||!Array.isArray(source.tabs)||source.tabs.length>10000)throw new Error("Неверная сессия");
 const ids=new Set(groups.map(g=>g.id));
 const tab=t=>{
  if(!Array.isArray(t.entries)||!t.entries.length||t.entries.length>1000)throw new Error("Неверная вкладка");
  const entries=t.entries.map(e=>{
   const internal=/^about:mybro\?view=(start|profile|bookmarks|downloads|history|settings|notes)$/.test(e.url)||["about:blank","about:logins","about:addons","about:preferences"].includes(e.url);
   return {url:internal?e.url:webURL(e.url),title:String(e.title||"").slice(0,10000)};
  });
  return {entries,index:Math.max(1,Math.min(entries.length,Number(t.index)||1)),pinned:!!t.pinned,muted:!!t.muted,
   extData:{mybroGroup:ids.has(t.extData?.mybroGroup)?t.extData.mybroGroup:""},image:safeIcon(t.image)};
 };
 return {tabs:source.tabs.map(tab),selected:Math.max(1,Math.min(source.tabs.length,Number(source.selected)||1)),
  _closedTabs:(source._closedTabs||[]).slice(0,100).map((c,i)=>({state:tab(c.state),closedAt:Number(c.closedAt)||Date.now(),pos:Math.max(0,Number(c.pos)||0),closedId:i+1}))};
}
export async function importProfile(data,window){
 if(data?.browser)return importLegacy(data,window);
 if(data?.format!=="mybro-gecko-1"||!Array.isArray(data.groups)||data.groups.length>1000)throw new Error("Неподдерживаемый профиль");
 for(const g of data.groups)if(typeof g.id!=="string"||g.id.length>100||typeof g.name!=="string"||g.name.length>1000)throw new Error("Неверная группа");
 const state=safeSession(data.session,data.groups);
 const passwords=await importPasswords(data.passwords||[]);await importHistory(data.history||[]);
 const folder=await P.bookmarks.insert({parentGuid:P.bookmarks.toolbarGuid,title:"Импорт myBro",type:P.bookmarks.TYPE_FOLDER});await importBookmarkNodes(data.bookmarks||{},folder.guid);
 const old=window.myBro.groups(),known=new Set(old.map(g=>g.id));window.myBro.write("groups",[...old,...data.groups.filter(g=>!known.has(g.id))]);
 for(const [key,value]of Object.entries(data.preferences||{}))if(/^mybro\.(theme|reduceMotion|pageZoom|notes|groupWidth|startClock|startSearch|startTiles)$/.test(key)&&typeof value==="string")Services.prefs.setStringPref(key,value);
 await restoreNativePreferences(data);
 SS.setWindowState(window,JSON.stringify({windows:[state]}),false);
 return {passwords,tabs:state.tabs.length};
}

export async function importLegacy(data,window,{replaceSession=false,skipHistory=false,skipBookmarks=false}={}){
 const browser=data.browser;if(!browser||!Array.isArray(browser.tabs)||browser.tabs.length>10000||!Array.isArray(browser.groups))throw new Error("Неверный профиль старого myBro");
 const colors={"Синий":"blue","Фиолетовый":"purple","Зелёный":"green","Оранжевый":"orange","Красный":"red","Серый":"gray"};
 const existing=window.myBro.groups(),model=[...existing],ids=new Map();
 for(const name of browser.groups){if(typeof name!=="string"||name.length>1000)throw new Error("Неверная группа");const old=existing.find(g=>g.name===name);const g=old||{id:crypto.randomUUID(),name,color:colors[browser.groupTints?.[name]]||"blue"};if(!old)model.push(g);ids.set(name,g.id);}
 const tabState=t=>{let url="about:mybro?view=start";
  if(t.internalPage)url=["passwords","extensions"].includes(t.internalPage)?(t.internalPage==="passwords"?"about:logins":"about:addons"):"about:mybro?view="+t.internalPage;
  else if(t.page?.url){try{url=webURL(t.page.url);}catch{return null;}}
  return {entries:[{url,title:String(t.page?.title||"Новая вкладка")}],index:1,pinned:!!t.pinned,muted:!!t.muted,extData:{mybroGroup:ids.get(t.group)||""},image:safeIcon(t.page?.iconURL)||(/^https?:/.test(url)?new URL("/favicon.ico",url).href:"")};
 };
 const tabs=browser.tabs.map(tabState).filter(Boolean);if(!tabs.length)tabs.push(tabState({}));
 const passwords=await importPasswords(data.passwords||[]);
 let historyCount=0;if(!skipHistory)historyCount=await importHistory(browser.history||[],true);
 let bookmarkCount=0;if(!skipBookmarks){
  const mapping=new Map(),pending=[...(browser.bookmarkFolders||[])];
  while(pending.length){
   let changed=false;for(let n=pending.length-1;n>=0;n--){const folder=pending[n];if(folder.parentID&&!mapping.has(folder.parentID))continue;
    const f=await P.bookmarks.insert({parentGuid:mapping.get(folder.parentID)||P.bookmarks.toolbarGuid,title:String(folder.name||"Папка"),type:P.bookmarks.TYPE_FOLDER});mapping.set(folder.id,f.guid);
    bookmarkCount+=await importBookmarkNodes({children:folder.pages||[]},f.guid);pending.splice(n,1);changed=true;
   }if(!changed)break;
  }
  if(pending.length)throw new Error("Некорректное дерево папок");
  bookmarkCount+=await importBookmarkNodes({children:browser.bookmarks||[]},P.bookmarks.toolbarGuid);
 }
 const preferences=data.preferences||{},own={"browser-theme":"theme","start-page-search":"startSearch","start-page-bookmarks":"startTiles","start-page-clock":"startClock","extra-start-tab":"extraStartTab","reuse-external-tab":"reuseExternalTab","reduce-browser-motion":"reduceMotion","default-page-zoom":"pageZoom","tab-groups-width":"groupWidth","local-notes":"notes"};
 for(const[key,target]of Object.entries(own))if(key in preferences){let value=preferences[key];if(["true","false"].includes(value))value=value==="true";else if(["pageZoom","groupWidth"].includes(target))value=Number(value);window.myBro.write(target,value);}
 const bools={"password-autofill":["signon.autofillForms",false],"ask-download-folder":["browser.download.useDownloadDir",true],"preview-pdf":["pdfjs.disabled",true],"search-suggestions":["browser.search.suggest.enabled",false]};
 for(const[key,[target,invert]]of Object.entries(bools))if(key in preferences){const b=preferences[key]===true||preferences[key]==="true";Services.prefs.setBoolPref(target,invert?!b:b);}
 if(preferences["bookmark-bar-visibility"])Services.prefs.setStringPref("browser.toolbars.bookmarks.visibility",{always:"always",newTab:"newtab",hidden:"never"}[preferences["bookmark-bar-visibility"]]||"always");
 if(preferences["minimum-web-font-size"]){const size=Number(preferences["minimum-web-font-size"]);if(Number.isInteger(size)&&size>=0&&size<=72)for(const lang of["x-western","x-cyrillic"])Services.prefs.setIntPref("font.minimum-size."+lang,size);}
 if(preferences["default-page-zoom"])await setDefaultZoom(window,Number(preferences["default-page-zoom"]));
 window.myBro.write("groups",model);
 const state={tabs,selected:Math.max(1,Math.min(tabs.length,(browser.selected||0)+1)),_closedTabs:(browser.closed||[]).map((t,i)=>({state:tabState(t),title:String(t.page?.title||"Новая вкладка"),pos:t.closedIndex||0,closedAt:(t.closedAt+978307200)*1000,closedId:i+1})).filter(t=>t.state&&Number.isFinite(t.closedAt))};
 SS.setWindowState(window,JSON.stringify({windows:[state]}),replaceSession);
 let downloads=0;const list=await Downloads.getList(Downloads.PUBLIC);
 for(const item of data.downloads||[]){try{
  const target=new URL(item.destination);if(target.protocol!=="file:"||!item.sourceURL)continue;
  const path=decodeURIComponent(target.pathname),source=webURL(item.sourceURL),complete=!!item.state?.complete;
  const download=await Downloads.createDownload({source,target:path,startTime:new Date((item.startedAt+978307200)*1000),succeeded:complete,canceled:!complete,totalBytes:0});await download.refresh();await list.add(download);downloads++;
 }catch{console.warn("myBro download metadata skipped");}}
 return {tabs:tabs.length,groups:browser.groups.length,passwords,history:historyCount,bookmarks:bookmarkCount,downloads};
}
