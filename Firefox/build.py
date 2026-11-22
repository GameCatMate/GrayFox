#!/usr/bin/env python3
"""Build the myBro frontend fork on the pinned official Gecko binary distribution."""
import argparse
import base64
import configparser
import hashlib
import io
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import struct
import subprocess
import tempfile
import urllib.request
import uuid
from datetime import datetime,timezone
import zipfile

ROOT = Path(__file__).resolve().parent.parent
HERE = ROOT / "Firefox"
BRAND = "GrayFox"
BRANDING = HERE / "branding"
CACHE = ROOT / ".build/firefox"
LOCK = json.loads((HERE / "upstream.lock.json").read_text())


def read_jar(path):
    data = Path(path).read_bytes()
    if data[:2] != b"PK":
        # Mozilla moves the central directory to the front and duplicates the EOCD.
        # Reattach the directory at the tail so Python's standard ZIP reader needs no heuristics.
        end_offset = data.rfind(b"PK\x05\x06")
        if end_offset < 0:
            raise ValueError("Missing Mozilla JAR directory")
        end = bytearray(data[end_offset:])
        size, offset = struct.unpack_from("<II", end, 12)
        if data[offset:offset + 4] != b"PK\x01\x02" or offset + size > end_offset:
            raise ValueError("Invalid Mozilla JAR directory")
        struct.pack_into("<I", end, 16, end_offset)
        data = data[:end_offset] + data[offset:offset + size] + end
    with zipfile.ZipFile(io.BytesIO(data)) as archive:
        if len(archive.infolist()) > 100000:
            raise ValueError("Oversized JAR")
        return {info.filename: archive.read(info) for info in archive.infolist()}


def write_jar(path, entries):
    temporary = Path(str(path) + ".mybro-new")
    with zipfile.ZipFile(temporary, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        for name, content in entries.items():
            archive.writestr(name, content)
    os.replace(temporary, path)


def prepare_upstream():
    base = CACHE / "upstream"
    base.mkdir(parents=True, exist_ok=True)
    image = base / ("firefox-" + LOCK["version"] + "-ru.dmg")
    if not image.exists():
        with urllib.request.urlopen(LOCK["url"], timeout=90) as source, image.with_suffix(".part").open("wb") as target:
            shutil.copyfileobj(source, target)
        os.replace(image.with_suffix(".part"), image)
    if hashlib.sha256(image.read_bytes()).hexdigest() != LOCK["sha256"]:
        raise ValueError("Official DMG checksum does not match the pinned release")
    app = base / "Firefox.app"
    if not app.exists():
        mount = Path(tempfile.mkdtemp(prefix="mybro-firefox-dmg-"))
        try:
            subprocess.run(["hdiutil", "attach", str(image), "-nobrowse", "-readonly", "-mountpoint", str(mount)], check=True)
            subprocess.run(["ditto", str(mount / "Firefox.app"), str(app)], check=True)
        finally:
            subprocess.run(["hdiutil", "detach", str(mount)], check=False)
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
    config = configparser.ConfigParser()
    config.read(app / "Contents/Resources/application.ini")
    if config["App"]["Version"] != LOCK["version"] or config["App"]["SourceStamp"] != LOCK["source_revision"]:
        raise ValueError("Upstream app is not the pinned version/revision")
    return app


def brand_localized_name(data):
    encoding = 'utf-16' if data.startswith((b'\xff\xfe', b'\xfe\xff')) else 'utf-8'
    text = data.decode(encoding)
    return re.sub(r'(?m)^(\s*CFBundle(?:Display)?Name\s*=\s*)"[^"]*"(\s*;)',
                  r'\1"' + BRAND + r'"\2', text).encode(encoding)


def patch_addons_navigation(html):
    if html.count('</head>') != 1 or html.count('<body>') != 1:
        raise ValueError('Upstream aboutaddons.html layout changed')
    injection = ('<link rel="stylesheet" href="chrome://browser/content/mybro/navigation.css">\n'
                 '<link rel="stylesheet" href="chrome://browser/content/mybro/addons-layout.css">\n'
                 '<script defer src="chrome://browser/content/mybro/navigation.js"></script>\n'
                 '<script defer src="chrome://browser/content/mybro/addons-navigation.js"></script>\n')
    return html.replace('</head>', injection + '</head>')


def patch_select_menus(entries):
    base = "chrome/toolkit/content/global/elements/"
    replacements = {
        "moz-select.mjs": {
            "      min-width-from-anchor\n":
                '      min-width-from-anchor\n      ?overlap-anchor=${document.documentURI.startsWith("about:preferences")}\n',
            "      click-on-mouseup\n":
                '      ?click-on-mouseup=${!document.documentURI.startsWith("about:preferences")}\n',
            "this.panelList?.toggle(event, this.panelTrigger);":
                'if (!this.panelList?.hasAttribute("overlap-anchor")) {\n'
                '      this.panelList?.toggle(event, this.panelTrigger?.parentElement);\n'
                '    }',
            "if (event.detail === 0) {":
                'if (event.detail === 0 || this.panelList?.hasAttribute("overlap-anchor")) {',
            "this.panelList?.toggle(event);":
                "this.panelList?.toggle(event, this.panelTrigger?.parentElement);",
        },
        "panel-list.mjs": {
            "      if (\n        roundedAnchorBottom > roundedBottomSpaceY &&":
                '      if (this.hasAttribute("overlap-anchor")) {\n'
                '        topOffset = Math.max(VIEWPORT_PANEL_MIN_MARGIN, Math.min(roundedAnchorTop, winHeight - roundedPanelHeight - VIEWPORT_PANEL_MIN_MARGIN));\n'
                '        this.style.maxHeight = `${winHeight - 2 * VIEWPORT_PANEL_MIN_MARGIN}px`;\n'
                '        valign = "bottom";\n'
                '      } else if (\n        roundedAnchorBottom > roundedBottomSpaceY &&',
        },
    }
    for name, changes in replacements.items():
        source = entries[base + name].decode()
        for old, new in changes.items():
            expected = 2 if old == "this.panelList?.toggle(event);" else 1
            if source.count(old) != expected:
                raise ValueError("Upstream select menu changed: " + name)
            source = source.replace(old, new)
        entries[base + name] = source.encode()
    entries[base + "moz-select.css"] += b'''\n@-moz-document url-prefix("about:preferences") {
  .select-wrapper:has(+ panel-list[overlap-anchor][open]:not([showing])) { opacity: 0; }
}\n'''


def patch_tracking_protection(entries):
    path = "chrome/browser/content/browser/preferences/config/privacy.mjs"
    source = entries[path].decode()
    replacements = {
        'import { Preferences } from "chrome://global/content/preferences/Preferences.mjs";':
            'import { TrackingProtection as GrayFoxETP } from "chrome://browser/content/mybro/tracking-protection.sys.mjs";\nimport { Preferences } from "chrome://global/content/preferences/Preferences.mjs";',
        'Preferences.addSetting({\n  id: "contentBlockingCategory",':
            'Preferences.addSetting({id:"grayfoxETPOff",get:()=>GrayFoxETP.isOff(),setup:emitChange=>GrayFoxETP.observe(emitChange)});\n\nPreferences.addSetting({\n  id: "contentBlockingCategory",',
        '            id: "etpLevelStandard",':
            '            id: "etpLevelOff", value: "off", l10nId: "grayfox-etp-level-off",\n          },\n          {\n            id: "etpLevelStandard",',
        '    return contentBlockingCategory.value;':
            '    return GrayFoxETP.isOff() ? "off" : contentBlockingCategory.value;',
        '    contentBlockingCategory.value = value;':
            '    contentBlockingCategory.value = GrayFoxETP.select(value);',
        '    if (!PrivacySettingHelpers.shouldDisableETPCategoryControls()) {\n      return config;':
            '    config.options.find(option=>option.value==="off").disabled=GrayFoxETP.locked();\n    if (!PrivacySettingHelpers.shouldDisableETPCategoryControls()) {\n      return config;',
        '      standard: "preferences-etp-level-standard",':
            '      off: "grayfox-etp-level-off",\n      standard: "preferences-etp-level-standard",',
        'categoryToL10nId[contentBlockingCategory.value]':
            'categoryToL10nId[GrayFoxETP.isOff() ? "off" : contentBlockingCategory.value]',
        '    get: prefValue => prefValue == "custom",':
            '    deps: ["grayfoxETPOff"],\n    get: prefValue => prefValue == "custom" && !GrayFoxETP.isOff(),',
        '      "etpCustomEnabled",\n      ...SECURITY_WARNINGS':
            '      "etpCustomEnabled",\n      "grayfoxETPOff",\n      ...SECURITY_WARNINGS',
    }
    for old, new in replacements.items():
        if source.count(old) != 1:
            raise ValueError("Upstream ETP settings changed: " + old[:90])
        source = source.replace(old, new)
    source = source.replace('deps: ["contentBlockingCategory"],', 'deps: ["contentBlockingCategory", "grayfoxETPOff"],')
    entries[path] = source.encode()
    path = "chrome/browser/content/browser/preferences/widgets/security-privacy-card.mjs"
    source = entries[path].decode()
    replacements = {
        '      "etpCustomEnabled",': '      "etpCustomEnabled",\n      "grayfoxETPOff",',
        '  buildIssuesElement() {': '  buildIssuesElement() {\n    if(this.setting.deps.grayfoxETPOff.value)return html`<li class="status-alert"><p data-l10n-id="grayfox-etp-disabled-status"></p></li>`;',
    }
    for old, new in replacements.items():
        if source.count(old) != 1:
            raise ValueError("Upstream ETP status card changed")
        source = source.replace(old, new)
    entries[path] = source.encode()
    entries["localization/ru/browser/preferences/preferences.ftl"] += b"\n" + (HERE / "chrome/tracking-protection.ftl").read_bytes()


def brand_images(entries):
    prefix = "chrome/browser/content/branding/"
    rendered = {}
    with tempfile.TemporaryDirectory(prefix="branding-", dir=CACHE) as folder:
        for path in entries:
            if not path.startswith(prefix) or not re.fullmatch(r"(?:icon\d+|about-logo(?:-private)?(?:@2x)?)\.png", Path(path).name):
                continue
            width, height = struct.unpack(">II", entries[path][16:24])
            if width != height:
                raise ValueError("Upstream branding icon is no longer square: " + path)
            if width not in rendered:
                output = Path(folder) / (str(width) + ".png")
                subprocess.run(["sips", "--resampleHeightWidth", str(height), str(width),
                                str(BRANDING / "GrayFox.png"), "--out", str(output)],
                               check=True, stdout=subprocess.DEVNULL)
                rendered[width] = output.read_bytes()
            entries[path] = rendered[width]
    logo = (b'<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512" viewBox="0 0 512 512">'
            b'<image width="512" height="512" href="data:image/png;base64,' +
            base64.b64encode(rendered[384]) + b'"/></svg>')
    for path in [prefix + "about-logo.svg", "chrome/browser/content/browser/logos/share-firefox.svg",
                 "chrome/browser/skin/classic/browser/sidebar/firefox.svg",
                 "chrome/browser/skin/classic/browser/window-firefox.svg",
                 "chrome/browser/builtin-addons/newtab/data/data/content/assets/firefox.svg"]:
        if path not in entries:
            raise ValueError("Upstream browser logo missing: " + path)
        entries[path] = logo
    for name in ("about-wordmark.svg", "firefox-wordmark.svg"):
        entries[prefix + name] = (HERE / "chrome/branding/wordmark.svg").read_bytes()


def build(upstream, output):
    output = output.resolve()
    if output == (ROOT / "myBro.app").resolve() or output.suffix != ".app":
        raise ValueError("The WebKit application must never be replaced")
    if output.exists() and not (output / "Contents/Resources/mybro-build.json").exists():
        raise ValueError("Refusing to replace an application not built by myBro Firefox")
    stage = Path(tempfile.mkdtemp(prefix="stage-", dir=CACHE)) / output.name
    subprocess.run(["ditto", str(upstream), str(stage)], check=True)
    resources = stage / "Contents/Resources"
    jar_path = resources / "browser/omni.ja"
    entries = read_jar(jar_path)
    browser_script_path = "chrome/browser/content/browser/browser.js"
    browser_script = entries[browser_script_path].decode()
    initial_page_check = "return gInitialPages.includes(nonQuery) || nonQuery == BROWSER_NEW_TAB_URL;"
    if browser_script.count(initial_page_check) != 1:
        raise ValueError("Upstream initial-page check changed")
    entries[browser_script_path] = browser_script.replace(
        initial_page_check, 'return url.spec === "about:mybro?view=start" || gInitialPages.includes(nonQuery) || nonQuery == BROWSER_NEW_TAB_URL;').encode()
    browser_path = "chrome/browser/content/browser/browser.xhtml"
    browser = entries[browser_path].decode()
    if browser.count("</head>") != 1:
        raise ValueError("Upstream browser.xhtml layout changed")
    injection = ('<link rel="stylesheet" href="chrome://browser/content/mybro/chrome.css"/>\n'
                 '<link rel="stylesheet" href="chrome://browser/content/mybro/navigation.css"/>\n'
                 '<script src="chrome://browser/content/mybro/navigation.js"></script>\n'
                 '<script src="chrome://browser/content/mybro/chrome.js"></script>\n')
    entries[browser_path] = browser.replace("</head>", injection + "</head>").encode()
    for source in (HERE / "chrome").rglob("*"):
        if source.is_file():
            relative = source.relative_to(HERE / "chrome").as_posix()
            entries["chrome/browser/content/browser/mybro/" + relative] = source.read_bytes()
    preferences_path = "chrome/browser/content/browser/preferences/preferences.xhtml"
    preferences = entries[preferences_path].decode()
    if preferences.count("</head>") != 1:
        raise ValueError("Upstream preferences layout changed")
    preferences_injection = ('<link rel="stylesheet" href="chrome://browser/content/mybro/navigation.css"/>\n'
                             '<link rel="stylesheet" href="chrome://browser/content/mybro/preferences.css"/>\n'
                             '<script src="chrome://browser/content/mybro/navigation.js"></script>\n'
                             '<script src="chrome://browser/content/mybro/preferences.js"></script>\n')
    entries[preferences_path] = preferences.replace("</head>", preferences_injection + "</head>").encode()
    preferences_main_path = "chrome/browser/content/browser/preferences/main.js"
    preferences_main = entries[preferences_main_path].decode()
    for illustration in ("kit-happy", "kit-concerned"):
        original = ('imagesrc: "chrome://global/skin/illustrations/' + illustration + '.svg",\n'
                    '      imagedisplay: "cover",')
        if preferences_main.count(original) != 1:
            raise ValueError("Upstream default-browser illustration changed: " + illustration)
        preferences_main = preferences_main.replace(original,
            'imagesrc: "chrome://browser/content/mybro/AppIcon.png",\n      imagedisplay: "padded",')
    entries[preferences_main_path] = preferences_main.encode()
    newtab_preferences_path = "chrome/browser/builtin-addons/newtab/lib/AboutPreferences.sys.mjs"
    newtab_preferences = entries[newtab_preferences_path].decode()
    sponsorship = 'id: "supportFirefox",\n      pref: "browser.newtabpage.activity-stream.showSponsoredCheckboxes",'
    if newtab_preferences.count(sponsorship) != 1:
        raise ValueError("Upstream sponsorship setting changed")
    entries[newtab_preferences_path] = newtab_preferences.replace(sponsorship,
        'id: "supportFirefox",\n      visible: () => false,\n      pref: "browser.newtabpage.activity-stream.showSponsoredCheckboxes",').encode()
    patch_tracking_protection(entries)
    for stylesheet in (HERE / "chrome/preferences-widgets").glob("*.css"):
        target = "chrome/browser/content/browser/preferences/widgets/" + stylesheet.name
        if target not in entries:
            raise ValueError("Upstream preference widget stylesheet missing: " + target)
        entries[target] += b"\n" + stylesheet.read_bytes()
    logins_path = "chrome/browser/content/browser/aboutlogins/"
    logins_html = entries[logins_path + "aboutLogins.html"].decode()
    if logins_html.count("<header>") != 1:
        raise ValueError("Upstream aboutLogins.html layout changed")
    entries[logins_path + "aboutLogins.html"] = logins_html.replace(
        "<header>", '<header><h1 data-l10n-id="about-logins-page-title-name"></h1>').encode()
    for stylesheet in (HERE / "chrome/passwords").rglob("*.css"):
        target = logins_path + stylesheet.relative_to(HERE / "chrome/passwords").as_posix()
        if target not in entries:
            raise ValueError("Upstream password stylesheet missing: " + target)
        entries[target] += b"\n" + stylesheet.read_bytes()
    entries["chrome/browser/content/browser/mybro/AppIcon.png"] = (BRANDING / "GrayFox.png").read_bytes()
    brand_images(entries)
    sanitize_path = "chrome/browser/content/browser/sanitizeDialog.js"
    sanitize_script = entries[sanitize_path].decode()
    sanitize_call = "Sanitizer.sanitize(itemsToClear, options)"
    if sanitize_script.count(sanitize_call) != 1:
        raise ValueError("Upstream clear-data dialog changed")
    entries[sanitize_path] = sanitize_script.replace(
        sanitize_call, 'ChromeUtils.importESModule("chrome://browser/content/mybro/library.sys.mjs").sanitizeBrowsingData(itemsToClear, options)').encode()
    entries["chrome/browser/content/browser/default-bookmarks.html"] = b'<!-- This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. See https://mozilla.org/MPL/2.0/. GrayFox modifications. --><!DOCTYPE NETSCAPE-Bookmark-file-1><META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8"><TITLE>GrayFox</TITLE><H1>GrayFox</H1><DL><p></DL><p>'
    for name in list(entries):
        if name.endswith("branding/brand.ftl"):
            entries[name] = entries[name].replace(b"Firefox", BRAND.encode())

    info_path = stage / "Contents/Info.plist"
    info = plistlib.loads(info_path.read_bytes())
    # Preserve the bundle/profile identities so existing data and system choices survive the rename.
    info.update(CFBundleName=BRAND, CFBundleDisplayName=BRAND,
                CFBundleIdentifier="org.mybro.firefox", CFBundleExecutable="mybro-launcher",
                CFBundleIconFile="GrayFox.icns", CFBundleGetInfoString=BRAND + " on Gecko " + LOCK["version"])
    info.pop("CFBundleIconName", None)  # The upstream asset-catalog icon overrides CFBundleIconFile.
    info_path.write_bytes(plistlib.dumps(info))
    for localized in resources.glob('*.lproj/InfoPlist.strings'):
        localized.write_bytes(brand_localized_name(localized.read_bytes()))
    shutil.copy2(BRANDING / "GrayFox.icns", resources / "GrayFox.icns")
    shutil.copy2(BRANDING / "GrayFox.icns", resources / "firefox.icns")
    application = configparser.ConfigParser()
    application.optionxform = str
    application.read(resources / "application.ini")
    application["App"].update(Name=BRAND, Vendor="myBro", RemotingName="mybro-firefox", Profile="myBro Firefox", BuildID=datetime.now(timezone.utc).strftime("%Y%m%d%H%M%S"))
    application["AppUpdate"]["URL"] = ""
    application["Crash Reporter"]["Enabled"] = "0"
    with (resources / "browser/application.ini").open("w") as target:
        application.write(target, space_around_delimiters=False)
    shutil.copy2(resources / "browser/application.ini", resources / "application.ini")

    major=LOCK["version"].split(".")[0]+".0"
    prefs = {
        "general.useragent.override": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:"+major+") Gecko/20100101 Firefox/"+major,
        "browser.tabs.inTitlebar": 1, "browser.tabs.tabMinWidth": 24,
        "browser.tabs.groups.enabled": True, "sidebar.verticalTabs": False, "sidebar.revamp": False,
        "browser.translations.automaticallyPopup": False,
        "sidebar.visibility": "hide-sidebar", "browser.fullscreen.autohide": False,
        "browser.startup.page": 3, "browser.shell.checkDefaultBrowser": True,
        "browser.shell.skipDefaultBrowserCheckOnFirstRun": False,
        "browser.aboutwelcome.enabled": False, "browser.preonboarding.enabled": False,
        "browser.aboutwelcome.experimentsGate.enabled": False, "browser.startup.homepage_override.mstone": "ignore",
        "browser.uitour.enabled": False, "browser.newtabpage.activity-stream.feeds.telemetry": False,
        "browser.newtabpage.activity-stream.showSponsoredTopSites": False,
        "browser.newtabpage.activity-stream.showSponsored": False,
        "browser.newtabpage.activity-stream.feeds.section.topstories": False,
        "browser.newtabpage.activity-stream.feeds.weatherfeed": False,
        "browser.tabs.groups.smart.enabled": False, "browser.ml.enable": False, "browser.ml.chat.enabled": False,
        "datareporting.healthreport.uploadEnabled": False, "datareporting.policy.dataSubmissionEnabled": False,
        "toolkit.telemetry.enabled": False, "toolkit.telemetry.unified": False,
        "browser.search.separatePrivateDefault.enabled": True, "browser.search.separatePrivateDefault.featureGate": True,
        "browser.search.suggest.enabled": True, "browser.urlbar.suggest.searches": True,
        "browser.search.suggest.enabled.private": False, "browser.download.useDownloadDir": True,
        "browser.download.autohideButton": False, "browser.download.alwaysOpenPanel": False, "browser.tabs.warnOnClose": False,
        "browser.ctrlTab.sortByRecentlyUsed": False, "browser.tabs.hoverPreview.enabled": False,
    }
    default_dir = resources / "defaults/pref"
    default_dir.mkdir(parents=True, exist_ok=True)
    pref_text="\n".join("pref(" + json.dumps(k) + ", " + json.dumps(v) + ");" for k, v in prefs.items()) + "\n"
    (default_dir / "mybro.js").write_text(pref_text)
    entries["defaults/preferences/firefox.js"] += ("\n// myBro defaults\n"+pref_text).encode()
    write_jar(jar_path, entries)
    toolkit_path = resources / 'omni.ja'
    toolkit = read_jar(toolkit_path)
    patch_select_menus(toolkit)
    addons_path = 'chrome/toolkit/content/mozapps/extensions/aboutaddons.html'
    toolkit[addons_path] = patch_addons_navigation(toolkit[addons_path].decode()).encode()
    write_jar(toolkit_path, toolkit)
    distribution = resources / "distribution"
    distribution.mkdir(exist_ok=True)
    (distribution / "policies.json").write_text(json.dumps({"policies": {
        "DisableAppUpdate": True, "DisableTelemetry": True, "DisableFirefoxStudies": True,
        "OverrideFirstRunPage": "", "OverridePostUpdatePage": ""
    }}, indent=2))
    launcher = stage / "Contents/MacOS/mybro-launcher"
    launcher.write_text('#!/bin/sh\nset -eu\nbundle=$(CDPATH=\'\' cd "$(dirname "$0")/.." && pwd)\nfor arg in "$@"; do case "$arg" in -profile|--profile|-P|-ProfileManager|--ProfileManager) exec "$bundle/MacOS/firefox" -app "$bundle/Resources/browser/application.ini" -no-remote "$@";; esac; done\nexport MOZ_CRASHREPORTER_DISABLE=1\nif [ -n "${MYBRO_FIREFOX_PROFILE:-}" ]; then mkdir -p "$MYBRO_FIREFOX_PROFILE"; exec "$bundle/MacOS/firefox" -app "$bundle/Resources/browser/application.ini" -no-remote -profile "$MYBRO_FIREFOX_PROFILE" "$@"; fi\nexec "$bundle/MacOS/firefox" -app "$bundle/Resources/browser/application.ini" -no-remote "$@"\n')
    launcher.chmod(0o755)
    (resources / "mybro-build.json").write_text(json.dumps({**LOCK, "fork": "myBro Firefox", "displayName": BRAND, "frontend": "Firefox/chrome"}, indent=2))
    # Gecko is the official compiled engine; only the open frontend/resources are changed.
    macho = {b"\xcf\xfa\xed\xfe", b"\xfe\xed\xfa\xcf", b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca"}
    for binary in sorted(stage.rglob("*"), key=lambda p: len(p.parts), reverse=True):
        if not binary.is_file() or binary.is_symlink():
            continue
        with binary.open("rb") as stream:
            magic = stream.read(4)
        if magic in macho:
            original = subprocess.run(["codesign", "-d", "--entitlements", ":-", str(binary)], capture_output=True)
            entitlements = plistlib.loads(original.stdout) if original.stdout.startswith(b"<?xml") else {}
            # Mozilla's team/passkey entitlements cannot be granted to a local ad-hoc fork.
            entitlements = {k: v for k, v in entitlements.items()
                            if k not in ("com.apple.application-identifier", "application-identifier", "com.apple.security.application-groups")
                            and not k.startswith("com.apple.developer.")}
            entitlements["com.apple.security.cs.disable-library-validation"] = True
            with tempfile.NamedTemporaryFile(suffix=".plist", dir=CACHE) as entitlement_file:
                entitlement_file.write(plistlib.dumps(entitlements)); entitlement_file.flush()
                subprocess.run(["codesign", "--force", "--sign", "-", "--preserve-metadata=flags,runtime",
                                "--entitlements", entitlement_file.name, str(binary)], check=True)
    for nested in sorted(stage.rglob("*.app"), key=lambda p: len(p.parts), reverse=True):
        subprocess.run(["codesign", "--force", "--sign", "-", "--preserve-metadata=entitlements,flags,runtime", str(nested)], check=True)
    subprocess.run(["codesign", "--force", "--sign", "-", str(stage)], check=True)
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(stage)], check=True)
    if output.exists():
        backup = CACHE / ("previous-" + uuid.uuid4().hex + ".app")
        os.replace(output, backup)
    os.replace(stage, output)
    print("Built:", output)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=ROOT / "GrayFox.app")
    args = parser.parse_args()
    CACHE.mkdir(parents=True, exist_ok=True)
    build(prepare_upstream(), args.output)


if __name__ == "__main__":
    main()
