// SPDX-License-Identifier: MIT
const prefs=Services.prefs;
const category="browser.contentblocking.category",saved="mybro.etpPreviousPreferences";
const off=Object.freeze({
 "privacy.trackingprotection.enabled":false,
 "privacy.trackingprotection.pbmode.enabled":false,
 "privacy.trackingprotection.emailtracking.enabled":false,
 "privacy.trackingprotection.emailtracking.pbmode.enabled":false,
 "privacy.trackingprotection.socialtracking.enabled":false,
 "privacy.trackingprotection.fingerprinting.enabled":false,
 "privacy.trackingprotection.cryptomining.enabled":false,
 "privacy.fingerprintingProtection":false,
 "privacy.fingerprintingProtection.pbmode":false,
 "privacy.socialtracking.block_cookies.enabled":false,
 "privacy.query_stripping.enabled":false,
 "privacy.query_stripping.enabled.pbmode":false,
 "privacy.bounceTrackingProtection.mode":0,
 "network.cookie.cookieBehavior":0,
 "network.cookie.cookieBehavior.pbmode":0,
 "network.cookie.cookieBehavior.optInPartitioning":false,
});
const get=(key,value)=>typeof value==="boolean"?prefs.getBoolPref(key,value):prefs.getIntPref(key,value);
const set=(key,value)=>typeof value==="boolean"?prefs.setBoolPref(key,value):prefs.setIntPref(key,value);

export const TrackingProtection={
 isOff(){return prefs.getStringPref(category,"standard")==="custom"&&Object.entries(off).every(([key,value])=>get(key,value)===value);},
 locked(){return [category,saved,...Object.keys(off)].some(key=>prefs.prefIsLocked(key));},
 select(level){
  if(!["off","standard","strict","custom"].includes(level))throw new Error("Неизвестный уровень защиты");
  if(level==="off"){
   if(this.locked())throw new Error("Настройки защиты заблокированы политикой");
   if(!this.isOff()){
    const previous=Object.fromEntries(Object.entries(off).map(([key,value])=>[key,prefs.prefHasUserValue(key)?get(key,value):null]));
    prefs.setStringPref(saved,JSON.stringify(previous));
    // Gecko supports three categories; Off is represented by an inactive custom profile.
    prefs.setStringPref(category,"custom");
    for(const[key,value]of Object.entries(off))set(key,value);
   }
   return "custom";
  }
  if(this.isOff()){
   let previous;
   try{previous=JSON.parse(prefs.getStringPref(saved,"{}"));}catch{previous={};}
   for(const[key,value]of Object.entries(off)){
    if(prefs.prefIsLocked(key))continue;
    const before=previous?.[key];
    if(typeof before===typeof value&&(typeof before==="boolean"||Number.isInteger(before)))set(key,before);
    else prefs.clearUserPref(key);
   }
   if(!prefs.prefIsLocked(saved))prefs.clearUserPref(saved);
  }
  return level;
 },
 observe(onChange){
  const observer={observe:()=>onChange()},keys=[category,...Object.keys(off)];
  for(const key of keys)prefs.addObserver(key,observer);
  return ()=>{for(const key of keys)prefs.removeObserver(key,observer);};
 }
};
