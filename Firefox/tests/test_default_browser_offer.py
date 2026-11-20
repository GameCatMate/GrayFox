"""Native prompt eligibility, without changing the system's default browser."""
import os
from runtime import Firefox


def main():
    os.environ['MOZ_HEADLESS'] = '1'
    with Firefox() as f:
        f.wait('window.myBro?.ready')
        state = f.js("return {enabled:Services.prefs.getDefaultBranch('').getBoolPref('browser.shell.checkDefaultBrowser'),locked:Services.prefs.prefIsLocked('browser.shell.checkDefaultBrowser'),skipFirst:Services.prefs.getBoolPref('browser.shell.skipDefaultBrowserCheckOnFirstRun')};")
        assert state == dict(enabled=True, locked=False, skipFirst=False), state
        result = f.async_js("""const done=arguments[arguments.length-1];(async()=>{
          const {DefaultBrowserCheck}=ChromeUtils.importESModule('moz-src:///browser/components/DefaultBrowserCheck.sys.mjs');
          const shell=getShellService(),original=shell.isDefaultBrowserAsync,checked=shell._checkedThisSession;
          const pref=Services.prefs.getBoolPref('browser.shell.checkDefaultBrowser');
          try {
            Services.prefs.setBoolPref('browser.shell.checkDefaultBrowser',true);shell._checkedThisSession=false;
            shell.isDefaultBrowserAsync=async()=>false;
            const notDefault=await DefaultBrowserCheck.willCheckDefaultBrowser(false);
            shell.isDefaultBrowserAsync=async()=>true;
            const alreadyDefault=await DefaultBrowserCheck.willCheckDefaultBrowser(false);
            shell.isDefaultBrowserAsync=async()=>false;
            Services.prefs.setBoolPref('browser.shell.checkDefaultBrowser',false);
            const optedOut=await DefaultBrowserCheck.willCheckDefaultBrowser(false);
            return {notDefault,alreadyDefault,optedOut};
          } finally {shell.isDefaultBrowserAsync=original;shell._checkedThisSession=checked;Services.prefs.setBoolPref('browser.shell.checkDefaultBrowser',pref);}
        })().then(done).catch(error=>done({error:String(error)}));""")
        assert result == dict(notDefault=True, alreadyDefault=False, optedOut=False), result
        print('PASS native offer enabled, suppressed when already default or opted out; no system association changed', flush=True)


if __name__ == '__main__':
    main()
