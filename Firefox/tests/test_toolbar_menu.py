"""Toolbar context-menu styling and bookmark visibility on a disposable profile."""
from runtime import Firefox
from test_menus import panel_surface
from test_runtime import check


def open_menu(f):
    f.js("document.getElementById('nav-bar').dispatchEvent(new MouseEvent('contextmenu',{bubbles:true,cancelable:true,screenX:350,screenY:180}));")
    f.wait("document.getElementById('toolbar-context-menu').state==='open'")


def main():
    with Firefox() as f:
        f.wait('window.myBro?.ready')
        for theme in ['dark', 'light']:
            f.js("myBro.write('theme',arguments[0]);", [theme])
            for visibility in ['always', 'never', 'newtab']:
                open_menu(f)
                check(panel_surface(f, '#toolbar-context-menu'), theme+' toolbar menu uses the application panel surface')
                check(f.js("const n=document.getElementById('toolbar-context-customize');return !n.hidden&&!n.disabled;"), 'toolbar customization stays available')
                f.js("document.querySelector('#toolbar-context-menu #toggle_PersonalToolbar').openMenu(true);")
                f.wait("document.querySelector('#toolbar-context-menu #toggle_PersonalToolbar menupopup').state==='open'")
                check(panel_surface(f, '#toolbar-context-menu #toggle_PersonalToolbar menupopup'), 'dynamic bookmark submenu uses the same surface')
                f.js("const p=document.querySelector('#toolbar-context-menu #toggle_PersonalToolbar menupopup');p.activateItem(p.querySelector('[data-visibility-enum='+arguments[0]+']'));", [visibility])
                f.wait("Services.prefs.getCharPref('browser.toolbars.bookmarks.visibility')==="+repr(visibility))
                f.wait("document.getElementById('toolbar-context-menu').state==='closed'")
                open_menu(f)
                check(f.js("return document.querySelector('#toolbar-context-menu #toggle_PersonalToolbar [checked]').getAttribute('data-visibility-enum')===arguments[0];", [visibility]), visibility+' selection persists when the menu is rebuilt')
                f.js("document.getElementById('toolbar-context-menu').hidePopup();")
                f.wait("document.getElementById('toolbar-context-menu').state==='closed'")


if __name__ == '__main__':
    main()
