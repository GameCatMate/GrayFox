#!/usr/bin/env python3
"""Copy the old myBro data to an isolated Gecko profile without plaintext password files."""
import argparse
import csv
import json
from pathlib import Path
import plistlib
import subprocess
import sys
import time
from urllib.parse import urlsplit
sys.path.insert(0,str(Path(__file__).resolve().parent/'tests'))
from runtime import Firefox,ROOT

DEFAULT=Path.home()/'Library/Application Support/myBro Firefox/Profiles/Default'


def read_legacy():
    result=subprocess.run(['defaults','export','org.openstvor.browser','-'],capture_output=True,check=True)
    preferences=plistlib.loads(result.stdout)
    state=preferences.pop('browser-state',None)
    if not isinstance(state,bytes):raise ValueError('The old myBro profile has no session')
    downloads=preferences.pop('download-history',b'[]')
    data={'browser':json.loads(state),'downloads':json.loads(downloads),'preferences':{k:v for k,v in preferences.items() if isinstance(v,(str,bool,int,float))}}
    return data


def read_passwords():
    bridge=ROOT/'.build/firefox/keychain-bridge'
    source=ROOT/'Firefox/Keychain.swift'
    if not bridge.exists() or bridge.stat().st_mtime<source.stat().st_mtime:
        subprocess.run(['swiftc','-module-cache-path',str(ROOT/'.build/modules'),str(source),'-o',str(bridge)],check=True,capture_output=True)
    result=subprocess.run([str(bridge),'--transfer'],capture_output=True)
    if result.returncode:raise RuntimeError('Keychain unavailable. Wake and unlock the Mac, then retry with --passwords-only. The source was not modified.')
    return json.loads(result.stdout)


def read_password_csv(path):
    entries, skipped = [], 0
    with path.open(encoding='utf-8-sig', newline='') as stream:
        rows = csv.DictReader(stream)
        if not {'url', 'username', 'password'} <= set(rows.fieldnames or []):
            raise ValueError('Password CSV must contain url, username and password columns')
        for index, row in enumerate(rows, 1):
            if index > 100000:
                raise ValueError('Password CSV is too large')
            url = urlsplit(row.get('url') or '')
            if url.scheme not in ('http', 'https'):
                skipped += 1
                continue
            if not url.hostname or url.username or url.password or row.get('username') is None or not row.get('password') or len(row['password']) > 4096:
                raise ValueError(f'Invalid password CSV row {index}')
            _ = url.port
            entries.append({'origin': row['url'], 'username': row['username'], 'password': row['password']})
    return entries, skipped


def migrate(data,profile,passwords=False,passwords_only=False):
    prefs=profile/'prefs.js'
    if prefs.exists() and 'mybro.legacyImported", true' not in prefs.read_text():
        raise ValueError('Destination already has a profile; choose a new empty destination to preserve its data')
    if passwords or (passwords_only and 'passwords' not in data):data['passwords']=read_passwords()
    with Firefox(profile=profile) as browser:
        browser.wait('window.myBro?.ready')
        browser.js("const service=Cc['@mozilla.org/toolkit/profile-service;1'].getService(Ci.nsIToolkitProfileService),root=Services.dirsvc.get('ProfD',Ci.nsIFile);let profile=[...service.profiles].find(p=>p.rootDir.equals(root));if(!profile)profile=service.createProfile(root,'myBro Firefox','mybro-migration');service.defaultProfile=profile;service.flush();return true;")
        browser.socket.settimeout(180)
        browser.command('WebDriver:SetTimeouts',{'script':180000})
        if passwords_only:
            result=browser.async_js("const rows=arguments[0],done=arguments[arguments.length-1];ChromeUtils.importESModule('chrome://browser/content/mybro/library.sys.mjs').importPasswords(rows).then(count=>done({ok:true,passwords:count}),()=>done({ok:false}));",[data['passwords']])
            if not result.get('ok'):raise RuntimeError('Password import failed; source unchanged')
            print(json.dumps({'passwords':result['passwords']}));return
        if browser.js('return Services.prefs.getBoolPref("mybro.legacyImported",false);'):
            print('Already migrated; no data changed.');return
        result=browser.async_js("const data=arguments[0],done=arguments[arguments.length-1];ChromeUtils.importESModule('chrome://browser/content/mybro/library.sys.mjs').importLegacy(data,window,{replaceSession:true}).then(value=>{Services.prefs.setBoolPref('mybro.legacyImported',true);Services.prefs.savePrefFile(null);done({ok:true,value});},()=>done({ok:false,error:'Migration failed; the source remains intact. Inspect the destination before retrying.'}));",[data])
        if not result.get('ok'):raise RuntimeError(result.get('error'))
        browser.wait('gBrowser.tabs.length>0')
        time.sleep(2)
        print(json.dumps(result['value'],ensure_ascii=False))


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--profile',type=Path,default=DEFAULT);parser.add_argument('--passwords',action='store_true');parser.add_argument('--passwords-only',action='store_true');parser.add_argument('--passwords-csv',type=Path);parser.add_argument('--fixture',type=Path);parser.add_argument('--inspect',action='store_true');args=parser.parse_args()
    if args.passwords_csv:
        if args.passwords or args.fixture:parser.error('--passwords-csv cannot be combined with --passwords or --fixture')
        entries,skipped=read_password_csv(args.passwords_csv)
        data={'passwords':entries};args.passwords_only=True
        print(json.dumps({'csvWebLogins':len(entries),'skippedNonWebLogins':skipped}))
        if args.inspect:return
    else:data=json.loads(args.fixture.read_text()) if args.fixture else read_legacy()
    if args.inspect:
        state=data['browser'];print(json.dumps({k:len(state.get(k,[])) for k in ['tabs','groups','history','bookmarks','bookmarkFolders','closed']}));return
    if args.profile.exists() and any(args.profile.iterdir()) and not (args.profile/'prefs.js').exists():raise ValueError('Refusing an unrelated target directory')
    migrate(data,args.profile.resolve(),args.passwords,args.passwords_only)


if __name__=='__main__':main()
