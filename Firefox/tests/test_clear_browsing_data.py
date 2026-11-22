"""Clear-data dialog and scoped deletion on disposable native and imported history."""
import os
from runtime import Firefox
from test_runtime import task


def main():
    os.environ['MOZ_HEADLESS'] = '1'
    with Firefox() as f:
        f.wait('window.myBro?.ready')
        f.js("myBro.openManager('history');")
        f.wait("gBrowser.selectedBrowser.contentDocument?.documentElement?.dataset.ready==='true'")
        assert f.js("return Array.from(gBrowser.selectedBrowser.contentDocument.querySelectorAll('button')).some(b=>b.textContent==='Удалить данные просмотра…');")
        result = task(f, """
          const L=ChromeUtils.importESModule('chrome://browser/content/mybro/library.sys.mjs');
          const now=Date.now(),recent=now-60000,old=now-86400000;
          for(const [tag,date] of [['old',old],['recent',recent]]){
            await L.importHistory([{url:'https://example.invalid/native-'+tag,title:tag,date},
              {url:'https://example.invalid/overflow-'+tag+'?'+ 'a'.repeat(66000),title:tag,date}]);
          }
          await L.importPasswords([{origin:'https://example.invalid',username:'fixture-user',password:'fixture-password'}]);
          await L.places.bookmarks.insert({parentGuid:L.places.bookmarks.toolbarGuid,title:'Keep bookmark',url:'https://example.invalid/bookmark'});
          const before=(await L.history('example.invalid')).length;
          await L.sanitizeBrowsingData(['browsingHistoryAndDownloads'],{ignoreTimespan:false,range:[(now-3600000)*1000,now*1000]});
          const remaining=await L.history('example.invalid');
          return {before,titles:remaining.map(r=>r.title),passwords:(await Services.logins.getAllLogins()).length,
            bookmark:!!(await L.places.bookmarks.fetch({url:'https://example.invalid/bookmark'}))};
        """)
        assert result == dict(before=4, titles=['old', 'old'], passwords=1, bookmark=True), result
        print('PASS last-hour cleanup includes imported history and preserves older visits, bookmarks and passwords', flush=True)
        f.js("gBrowser.selectedBrowser.contentDocument.querySelectorAll('button').forEach(b=>{if(b.textContent==='Удалить данные просмотра…')b.click();});")
        f.wait("gDialogBox.dialog?._frame?.contentWindow?.gSanitizePromptDialog?._inited")
        data = f.js("const d=gDialogBox.dialog._frame.contentDocument;return {periods:d.querySelectorAll('#sanitizeDurationPopup menuitem').length,types:Array.from(d.querySelectorAll('#clearPrivateDataGroupbox checkbox')).map(n=>n.id)};")
        assert data['periods'] >= 5 and set(data['types']) == {'browsingHistoryAndDownloads','cookiesAndStorage','cache','formdata','siteSettings'}, data
        f.js("gDialogBox.dialog._frame.contentDocument.querySelector('dialog').cancelDialog();")
        f.wait('!gDialogBox.isOpen')
        assert task(f,"return (await ChromeUtils.importESModule('chrome://browser/content/mybro/library.sys.mjs').history('example.invalid')).length;") == 2
        print('PASS native five-category dialog opens from GrayFox history; cancellation preserves data', flush=True)
        f.js("Array.from(gBrowser.selectedBrowser.contentDocument.querySelectorAll('button')).find(b=>b.textContent==='Удалить данные просмотра…').click();")
        f.wait("gDialogBox.dialog?._frame?.contentWindow?.gSanitizePromptDialog?._inited")
        f.js("const d=gDialogBox.dialog._frame.contentDocument;d.getElementById('sanitizeDurationChoice').value='0';for(const c of d.querySelectorAll('#clearPrivateDataGroupbox checkbox'))if(c.checked!==(c.id==='browsingHistoryAndDownloads'))c.click();d.querySelector('dialog').getButton('accept').click();")
        f.wait('!gDialogBox.isOpen')
        assert task(f,"return (await ChromeUtils.importESModule('chrome://browser/content/mybro/library.sys.mjs').history('example.invalid')).length;") == 0
        assert task(f,"return (await Services.logins.getAllLogins()).length;") == 1
        f.wait("gBrowser.selectedBrowser.contentDocument?.querySelector('.history-items .empty')")
        print('PASS actual native dialog acceptance clears all selected history, including imported visits, and retains passwords', flush=True)


if __name__ == '__main__':
    main()
