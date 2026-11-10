from pathlib import Path
import sys,zipfile,shutil,hashlib,json
runner,package,output=map(Path,sys.argv[1:4])
repo=Path(__file__).resolve().parents[1]
mods=runner/'workshop/content/1942280'
existing=list(mods.glob('*/wushuangabao-BrotatoOnlineFriends-*.zip'))
assert len(existing)==1
with zipfile.ZipFile(package) as z:
    for entry in z.infolist():
        rel=entry.filename.split('wushuangabao-BrotatoOnlineFriends/',1)[1]
        assert z.read(entry)==(repo/rel).read_bytes(),rel
shutil.copy2(package,existing[0])
probe=list(mods.glob('*/Local-NoobsProbe.zip'))
assert len(probe)==1
with zipfile.ZipFile(probe[0]) as z:manifest=z.read('mods-unpacked/Local-NoobsProbe/manifest.json')
with zipfile.ZipFile(probe[0],'w',zipfile.ZIP_DEFLATED) as z:
    prefix='mods-unpacked/Local-NoobsProbe/'
    z.writestr(prefix+'manifest.json',manifest)
    for src,dest in [('tests/movement_rewards_lan.gd','mod_main.gd'),('tests/fixtures/MovementRewardsProbe/base_probe.gd','base_probe.gd'),('tests/fixtures/MovementRewardsProbe/session_fixture.gd','online_session_fixture.gd')]:
        z.write(repo/src,prefix+dest)
noobs=list(mods.glob('*/wushuangabao-NoobsWantToLive-*.zip'))
assert len(noobs)==1
with zipfile.ZipFile(noobs[0]) as z:
    assert not any(i.filename.endswith('/online_friends_tracking.gd') for i in z.infolist()),'Disable old adapter in candidate first'
    assert b'extensions/online_friends_tracking.gd' not in z.read('mods-unpacked/wushuangabao-NoobsWantToLive/mod_main.gd')
five=list(mods.glob('*/wushuangabao-FiveItemShop-*.zip'))
assert len(five)==1
with zipfile.ZipFile(five[0]) as z:
    manifest=json.loads(z.read('mods-unpacked/wushuangabao-FiveItemShop/manifest.json'))
    assert manifest['version_number']=='1.1.3'
report={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in [package,probe[0],noobs[0],five[0]]}
(output/'packages.json').write_text(json.dumps({'adapter_enabled':False,'five_item_shop':'1.1.3','sha256':report},indent=2),encoding='utf8')
