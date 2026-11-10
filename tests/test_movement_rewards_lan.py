"""Two real LAN peers; drive native scenes and real trail/enemy collisions."""
import json
import sys
import time
from pathlib import Path

folder = Path(sys.argv[1])
results = []
last_read = {}
hit_damage = 90 if '--luck-gains' in sys.argv else 10
wave_damage = hit_damage * 2

def read(role):
    try:
        last_read[role] = json.loads((folder / f'{role}-state.json').read_text(encoding='utf-8-sig'))
        return last_read[role]
    except (OSError, ValueError):
        return last_read.get(role, {})

def wait(predicate, timeout=20):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        h, c = read('host'), read('client')
        if h and c and predicate(h, c):
            return h, c
        time.sleep(.08)
    raise TimeoutError(json.dumps({'host':read('host'),'client':read('client')},ensure_ascii=False))

def cmd(role, action, **args):
    states = wait(lambda h,c: 'command' in h and 'command' in c)
    ident = states[0 if role=='host' else 1]['command'] + 1
    path = folder / f'{role}-command.json'
    tmp = path.with_suffix('.tmp')
    tmp.write_text(json.dumps(dict(id=ident, action=action, **args)),encoding='utf-8')
    deadline=time.monotonic()+2
    while True:
        try:
            tmp.replace(path)
            break
        except PermissionError:
            if time.monotonic()>=deadline: raise
            time.sleep(.02)
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

try:
    wait(lambda h,c: 'character_selection' in h['scene'] and 'title_screen' in c['scene'],60)
    cmd('host','host')
    wait(lambda h,c: h.get('lan_host') and h['online'])
    cmd('client','join')
    wait(lambda h,c: h['members']==2 and c['members']==2 and c['online'])
    check('Friends LAN connected',True)
    cmd('host','fixture'); shop()
    for wave in (2,3):
        wait(lambda h,c: bool(c.get('shop_epoch')) and h.get('go_hooked') and c.get('go_hooked') and h['shop_ready'][0] and c['shop_ready'][1])
        cmd('client','go',player=1)
        wait(lambda h,c: len(h.get('pressed',[]))>1 and h['pressed'][1])
        cmd('host','go',player=0)
        wait(lambda h,c: h['scene']=='res://main.tscn' and c['scene']=='res://main.tscn' and h['wave']==wave and c['wave']==wave,30)
        time.sleep(3)
        baseline=(wave-2)*4
        h,c=read('host'),read('client')
        check('wave start stats synchronized '+str(wave),all(s['players'][1]['crit_bonus']==baseline and s['players'][1]['total']==baseline for s in [h,c]),[h['players'],c['players']])
        cmd('client','cat_steps',player=1,steps=79)
        check('below 80 grants nothing',read('client')['players'][1]['crit_bonus']==baseline)
        cmd('client','walk',player=1)
        c=read('client')
        check('real walking crosses 80 and grants 2 percent',c['players'][1]['crit_bonus']==baseline+2 and c['players'][1]['total']==baseline+2,c['players'])
        cmd('client','cat_steps',player=1,steps=80)
        c=read('client')
        check('second threshold accumulates once',c['players'][1]['crit_bonus']==baseline+4 and c['players'][1]['total']==baseline+4,c['players'])
        h,c=wait(lambda h,c: h['players'][1]['crit_bonus']==baseline+4)
        check('client walking gains synchronized live to host',True)
        cmd('host','cat_steps',player=0,steps=80)
        h,c=wait(lambda h,c: c['players'][0]['crit_bonus']==(wave-1)*2)
        check('host walking gains synchronized live to client',True)
        cmd('host','finish_wave');cmd('client','finish_wave');shop();time.sleep(1)
        c=read('client')
        check('client progression survives settlement',c['players'][1]['crit_bonus']==baseline+4 and c['players'][1]['total']==baseline+4,c['players'])
        cmd('client','reroll',player=1);time.sleep(1)
        c=read('client')
        check('reroll preserves stats and ownership',c['players'][1]['crit_bonus']==baseline+4 and c['players'][0]['crit_bonus']==(wave-1)*2,c['players'])
    restored=cmd('client','cat_restore',player=1)
    check('stale and duplicate snapshots preserve gains plus incoming item bonus; retry restores snapshot',restored.get('preserved') and restored.get('retry'),restored)
    cmd('client','screenshot',player=1,label='cat-statistics')
    print('RESULT: '+str(len(results))+' passed',flush=True)
finally:
    for role in ('host','client'):
        try: (folder/f'{role}-command.json').write_text(json.dumps(dict(id=read(role)['command']+1,action='quit')),encoding='utf-8')
        except (OSError,KeyError): pass
