// SPDX-License-Identifier: MIT
const ID = Components.ID("{a96d581a-7e64-4ea8-bbca-545ac071b223}");
let registered = false;
export function registerPages() {
  if (registered) return;
  ChromeUtils.registerWindowActor("MyBroLoginFields", {
    remoteTypes: ["web"],
    safeForUntrustedWebProcess: true,
    child: {
      esModuleURI: "chrome://browser/content/mybro/MyBroLoginFieldsChild.sys.mjs",
      events: {DOMWindowCreated: {}},
    },
    matches: ["https://my.easydocs.ru/login*"],
    allFrames: false,
  });
  ChromeUtils.registerWindowActor("MyBro9Gag", {
    remoteTypes: ["web"],
    safeForUntrustedWebProcess: true,
    child: {
      esModuleURI: "chrome://browser/content/mybro/MyBro9GagChild.sys.mjs",
      events: {click: {capture: true, mozSystemGroup: false}},
    },
    matches: ["https://9gag.com/*", "https://www.9gag.com/*"],
    allFrames: false,
  });
  const page = {
    QueryInterface: ChromeUtils.generateQI(["nsIAboutModule"]),
    getURIFlags() { return Ci.nsIAboutModule.ALLOW_SCRIPT; },
    newChannel(uri, loadInfo) {
      const target = Services.io.newURI("chrome://browser/content/mybro/manager.html" + (uri.query ? "?" + uri.query : ""));
      const channel = Services.io.newChannelFromURIWithLoadInfo(target, loadInfo);
      channel.originalURI = uri;
      return channel;
    },
  };
  const factory = {
    QueryInterface: ChromeUtils.generateQI(["nsIFactory"]),
    createInstance(iid) { return page.QueryInterface(iid); },
  };
  Components.manager.QueryInterface(Ci.nsIComponentRegistrar)
    .registerFactory(ID, "GrayFox internal pages", "@mozilla.org/network/protocol/about;1?what=mybro", factory);
  registered = true;
}
