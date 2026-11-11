from pathlib import Path
import sys, zipfile, shutil, hashlib, json

runner, package, output = map(Path, sys.argv[1:4])
repo = Path(__file__).resolve().parents[1]
mods = runner / 'workshop/content/1942280/3834592597'
with zipfile.ZipFile(package) as archive:
    for entry in archive.infolist():
        relative = entry.filename.split('wushuangabao-BrotatoOnlineFriends/', 1)[1]
        assert archive.read(entry) == (repo / relative).read_bytes(), relative
for existing in mods.glob('wushuangabao-BrotatoOnlineFriends-*.zip'):
    if existing.name != package.name:
        existing.unlink()
shutil.copy2(package, mods / package.name)
manifest = dict(name='NoobsProbe', namespace='Local', version_number='1.0.0', description='Isolated equipment sync regression', website_url='', dependencies=['wushuangabao-NoobsWantToLive'], extra={'godot':{'authors':['Test'], 'compatible_mod_loader_version':['6.3.0'], 'compatible_game_version':['1.2.0.1']}})
with zipfile.ZipFile(mods / 'Local-NoobsProbe.zip', 'w', zipfile.ZIP_DEFLATED) as archive:
    prefix = 'mods-unpacked/Local-NoobsProbe/'
    archive.writestr(prefix+'manifest.json', json.dumps(manifest))
    for source, destination in [('tests/equipment_effects_lan.gd','mod_main.gd'), ('tests/effect_lifecycle_checks.gd','effect_lifecycle_checks.gd'), ('tests/fixtures/EquipmentEffectsProbe/base_probe.gd','base_probe.gd'), ('tests/fixtures/EquipmentEffectsProbe/session_fixture.gd','online_session_fixture.gd')]:
        archive.write(repo / source, prefix+destination)
(output/'packages.json').write_text(json.dumps({p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in mods.glob('*.zip')}, indent=2), encoding='utf8')

(output/"sources.json").write_text(json.dumps({str(p.relative_to(repo)): hashlib.sha256(p.read_bytes()).hexdigest() for p in [repo/"scripts/menu_sync_manager.gd", repo/"scripts/upgrade_runtime_sync.gd", repo/"tests/Test-EquipmentEffectsLan.ps1", repo/"tests/test_equipment_effects_lan.py", repo/"tests/equipment_effects_lan.gd", repo/"tests/prepare_equipment_probe.py", repo/"tests/effect_lifecycle_checks.gd", repo/"tests/test_effect_lifecycle_lan.py"]}, indent=2),encoding="utf8")
