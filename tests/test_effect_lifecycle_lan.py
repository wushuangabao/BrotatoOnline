"""Native effect lifecycle checks and two-peer LAN restoration regression."""
import json
import sys
import time
from pathlib import Path

folder = Path(sys.argv[1])
results = []
last_states = {}
def read(role):
    try:
        last_states[role] = json.loads((folder / f'{role}-state.json').read_text(encoding='utf-8-sig'))
        return last_states[role]
    except (OSError, ValueError):
        return last_states.get(role, {})

def wait(predicate, timeout=20):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        h, c = read('host'), read('client')
        if h and c and predicate(h, c):
            return h, c
        time.sleep(.08)
    raise TimeoutError(json.dumps({'host':read('host'),'client':read('client')},ensure_ascii=False))

def cmd(role, action, **args):
    ident = read(role)['command'] + 1
    path = folder / f'{role}-command.json'
    tmp = path.with_suffix('.tmp')
    tmp.write_text(json.dumps(dict(id=ident, action=action, **args)),encoding='utf-8')
    tmp.replace(path)
    states = wait(lambda h,c: (h if role=='host' else c)['command'] >= ident)
    return states[0 if role=='host' else 1]['result']

def check(label, ok, detail=None):
    results.append(dict(name=label,passed=bool(ok),detail=detail))
    print(('PASS: ' if ok else 'FAIL: ') + label, flush=True)
    (folder/'verification.json').write_text(json.dumps(results,ensure_ascii=False,indent=2),encoding='utf-8')
    if not ok:
        raise AssertionError(label + ' ' + str(detail))

def shop():
    end=time.monotonic()+45
    while time.monotonic()<end:
        states=[read(r) for r in ('host','client')]
        if all('coop_shop' in s.get('scene','') for s in states):
            return states
        for role,i,s in zip(('host','client'),(0,1),states):
            if len(s.get('progression_ready',[]))>i and s['progression_ready'][i]:
                cmd(role,'progression_confirm',player=i)
        time.sleep(.1)
    raise TimeoutError('shop transition: '+str(states))

def enter_wave():
    wait(lambda h,c: bool(c.get('shop_epoch')) and h.get('go_hooked') and c.get('go_hooked') and h['shop_ready'][0] and c['shop_ready'][1])
    cmd('client','go',player=1)
    wait(lambda h,c:len(h.get('pressed',[]))>1 and h['pressed'][1])
    cmd('host','go',player=0)
    wait(lambda h,c:h['scene']=='res://main.tscn' and c['scene']=='res://main.tscn',30)
    wait(lambda h,c:all('live_armor' in p for p in h['players']+c['players']),15)

def stable(label, expected):
    h,c=wait(lambda h,c: all([p['lifecycle'] for p in state['players']]==expected for state in (h,c)))
    check(label,True,expected)
try:
    wait(lambda h,c:'character_selection' in h['scene'] and 'title_screen' in c['scene'],60)
    cmd('host','host');wait(lambda h,c:h.get('lan_host') and h['online'])
    cmd('client','join');wait(lambda h,c:h['members']==2 and c['members']==2 and h['online'] and c['online'])
    for role in ('host','client'):
        for item in cmd(role,'lifecycle_checks')['checks']:
            check(role+': '+item['name'],item['passed'],item['detail'])
    cmd('host','lifecycle_fixture');shop()
    for role in ('host','client'):
        for i in (0,1):cmd(role,'render_effects',player=i)
    expected=read('host')['players']
    expected=[p['lifecycle'] for p in expected]
    check('Cursed native seashell fixture and one materialized flame arg',all(p['shell_cursed'] and p['shell_counts']==[1] and p['shell_bound'] and p['flame_args']==[1] and list(p['special_shots'].values())==[4] for p in expected),expected)
    stable('Both peers start with bound effects and correct native projectile counts',expected)
    for cycle in range(6):
        for role in ('host','client'):
            for i in (0,1):
                applied=cmd(role,'repeat_snapshot',player=i)
                check(f'Cycle {cycle+1} {role} seat {i+1} accepts all three full states',applied.get('applied')==3,applied)
                cmd(role,'render_effects',player=i)
        stable(f'Roundtrip/render cycle {cycle+1} is idempotent on every seat',expected)
    enter_wave();stable('Native battle begins with unchanged effects and projectile stats',expected)
    cmd('host','finish_wave');shop()
    for role in ('host','client'):
        for i in (0,1):cmd(role,'render_effects',player=i)
    stable('Real LAN wave handoff preserves description args and cursed subeffects',expected)
    for role,i in [('host',0),('client',1)]:
        cmd(role,'sell_wrench',player=i)
        expected[i]['flame_args']=[]
        stable(role+' native sale after repeated rendering leaves seashell unchanged',expected)
    enter_wave();stable('Second battle keeps each player special-shot stats',expected)
    cmd('host','finish_wave');shop();stable('Second native settlement remains stable',expected)
    print('RESULT: '+str(len(results))+' passed',flush=True)
except Exception as exc:
    (folder/'failure.json').write_text(json.dumps({'error':str(exc),'last_states':last_states},ensure_ascii=False,indent=2),encoding='utf8')
    raise
finally:
    for role in ('host','client'):
        try:
            path=folder/f'{role}-command.json';temp=path.with_suffix('.tmp')
            temp.write_text(json.dumps(dict(id=read(role)['command']+1,action='quit')),encoding='utf8');temp.replace(path)
        except (OSError,KeyError):pass
