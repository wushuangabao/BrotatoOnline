"""Mount the existing mechanical-upgrade assertions in the isolated retail runner."""
from pathlib import Path
import sys, zipfile, json, hashlib
runner, output = map(Path, sys.argv[1:3])
repo = Path(__file__).resolve().parents[1]
probe = runner/'workshop/content/1942280/3834592597/Local-NoobsProbe.zip'
with zipfile.ZipFile(probe) as z:
    manifest = z.read('mods-unpacked/Local-NoobsProbe/manifest.json')
source = (repo/'tests/meca_upgrade_lan.gd').read_text(encoding='utf8')
adapted = source.replace('session.join_lan("127.0.0.1", 27462)', 'session.join_lan("127.0.0.1", int(OS.get_environment("BROTATO_TEST_PORT")))')
adapted = adapted.replace('session.create_session(false)', 'session._get_mod_settings_manager().set_lan_host_port(int(OS.get_environment("BROTATO_TEST_PORT")))\n\t\tsession.create_session(false)')
assert source != adapted
(output/'meca_upgrade_lan.gd').write_text(adapted, encoding='utf8')
bootstrap = '''extends Node
func _init():
    ModLoaderMod.install_script_extension("res://mods-unpacked/Local-NoobsProbe/online_session_fixture.gd")
func _ready():
    call_deferred("_start_test")
func _start_test():
    # The retail boot scene changes to the title after ModLoader ready.
    # Wait for that transition before the standalone scene test takes over.
    while get_tree().current_scene == null or get_tree().current_scene.filename != MenuData.title_screen_scene:
        yield(get_tree(), "idle_frame")
    yield(get_tree(), "idle_frame")
    var probe = load("res://mods-unpacked/Local-NoobsProbe/meca_upgrade_lan.gd").new()
    get_tree().root.add_child(probe)
func _process(_delta):
    var manager = get_tree().root.find_node("BrotatoOnlineMenuSyncManager", true, false)
    if manager == null:
        return
    var state = {"scene":get_tree().current_scene.filename if get_tree().current_scene else "", "intercept":manager._client_shop_intercept_key, "players":[]}
    for i in RunData.get_player_count():
        state.players.append({"weapons":RunData.get_player_weapons(i).size(), "parts":RunData.get_player_meca_parts(i)})
    var f = File.new()
    f.open(OS.get_environment("BROTATO_TEST_DIR").plus_file(OS.get_environment("BROTATO_TEST_ROLE") + "-retail-state.json"), File.WRITE)
    f.store_string(JSON.print(state))
    f.close()
'''
with zipfile.ZipFile(probe, 'w', zipfile.ZIP_DEFLATED) as z:
    prefix='mods-unpacked/Local-NoobsProbe/'
    z.writestr(prefix+'manifest.json',manifest)
    z.writestr(prefix+'mod_main.gd',bootstrap)
    z.writestr(prefix+'meca_upgrade_lan.gd',adapted)
    z.write(repo/'tests/fixtures/EquipmentEffectsProbe/session_fixture.gd',prefix+'online_session_fixture.gd')
packages=json.loads((output/'packages.json').read_text())
packages[probe.name]=hashlib.sha256(probe.read_bytes()).hexdigest()
(output/'packages.json').write_text(json.dumps(packages,indent=2),encoding='utf8')
(output/'meca-fixture.json').write_text(json.dumps({'original_sha256':hashlib.sha256(source.encode()).hexdigest(),'adapted_sha256':hashlib.sha256(adapted.encode()).hexdigest(),'changes':'Only fixed LAN port replaced with per-run environment port; assertions unchanged; bootstrap waits for retail title before taking over; Steam-room fixture bypasses shared-account lobby creation.'},indent=2),encoding='utf8')
