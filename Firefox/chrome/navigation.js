// SPDX-License-Identifier: MIT
window.myBroSections={profile:"Мой профиль",bookmarks:"Закладки",downloads:"Загрузки",history:"История",passwords:"Пароли",extensions:"Расширения",settings:"Настройки"};
window.myBroPageIcons={settings:"chrome://global/skin/icons/settings.svg",passwords:"chrome://browser/skin/login.svg",bookmarks:"chrome://global/skin/icons/folder.svg",downloads:"chrome://browser/skin/downloads/downloads.svg",history:"chrome://browser/skin/history.svg"};
window.myBroPageIcon=url=>{
 const page=new URL(url);
 if(page.protocol!=="about:")return "";
 const view=page.pathname==="mybro"?page.searchParams.get("view"):({logins:"passwords",preferences:"settings",downloads:"downloads"})[page.pathname];
 return window.myBroPageIcons[view]||"";
};
window.openMyBroSection=(app,id)=>id==="extensions"?app.nativePage("about:addons"):id==="passwords"?app.nativePage("about:logins"):app.openManager(id);
window.renderMyBroNavigation=(navigation,app,privateMode,active)=>{
 navigation.replaceChildren();navigation.classList.add("mybro-navigation");
 for(const[id,label]of Object.entries(window.myBroSections)){
  if(privateMode&&["profile","history"].includes(id))continue;
  const button=document.createElement("button");button.type="button";button.textContent=label;
  if(id===active){button.className="active";button.setAttribute("aria-current","page");}
  button.onclick=async()=>{
   try{await window.openMyBroSection(app,id);}
   catch(error){const notice=document.getElementById("notice");if(notice)notice.textContent=error?.message||String(error);else console.error(error);}
  };
  navigation.append(button);
 }
};
