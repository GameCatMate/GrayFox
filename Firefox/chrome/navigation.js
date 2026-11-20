// SPDX-License-Identifier: MIT
window.myBroSections={profile:"Мой профиль",bookmarks:"Закладки",downloads:"Загрузки",history:"История",passwords:"Пароли",extensions:"Расширения",settings:"Настройки"};
window.renderMyBroNavigation=(navigation,app,privateMode,active)=>{
 navigation.replaceChildren();navigation.classList.add("mybro-navigation");
 for(const[id,label]of Object.entries(window.myBroSections)){
  if(privateMode&&["profile","history"].includes(id))continue;
  const button=document.createElement("button");button.type="button";button.textContent=label;
  if(id===active){button.className="active";button.setAttribute("aria-current","page");}
  button.onclick=async()=>{
   try{await(id==="extensions"?app.nativePage("about:addons"):id==="passwords"?app.nativePage("about:logins"):app.openManager(id));}
   catch(error){const notice=document.getElementById("notice");if(notice)notice.textContent=error?.message||String(error);else console.error(error);}
  };
  navigation.append(button);
 }
};
