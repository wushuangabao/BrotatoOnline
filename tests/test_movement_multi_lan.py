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
        for role,i,s in [('host',0,states[0]),('host',1,states[0]),('client',2,states[1]),('client',3,states[1])]:
            if len(s.get('progression_ready',[]))>i and s['progression_ready'][i]:
                cmd(role,'progression_confirm',player=i)
        time.sleep(.1)
    raise TimeoutError('shop transition: '+str(states))

try:
    wait(lambda h,c:'character_selection' in h['scene'] and 'title_screen' in c['scene'],60)
    cmd('host','host');wait(lambda h,c:h.get('lan_host'))
    cmd('host','add_seat');cmd('client','join')
    wait(lambda h,c:h['members']==3 and c['members']==3)
    cmd('client','add_seat');wait(lambda h,c:h['members']==4 and c['members']==4)
    check('two local seats on each LAN peer',True)
    cmd('host','fixture');shop()
    wait(lambda h,c:len(h['shop_ready'])==4 and all(h['shop_ready']) and len(c['shop_ready'])==4 and all(c['shop_ready']))
    for role,i in [('client',2),('client',3),('host',1),('host',0)]:
        cmd(role,'go',player=i)
    wait(lambda h,c:h['scene']=='res://main.tscn' and c['scene']=='res://main.tscn',30)
    time.sleep(3)
    expected=[]
    for role,i in [('host',0),('host',1),('client',2),('client',3)]:
        before=read(role)['players'][i]
        cmd(role,'cat_steps',player=i,steps=80*(i+1)+1)
        after=read(role)['players'][i]
        check(f'P{i+1} independent native reward ledger',after['gold']==before['gold']+48*(i+1) and after['max_hp']==before['max_hp']+i+1,after)
        expected.append(after)
    cmd('client','reconnect')
    wait(lambda h,c:all(h['players'][i]['gold']==c['players'][i]['gold']==expected[i]['gold'] for i in range(4)))
    cmd('client','loss',reports=2);cmd('host','loss',acks=2)
    cmd('host','finish_wave');shop();time.sleep(3)
    for role in ['host','client']:
        after=read(role)['players']
        check(role+' retains four distinct totals after reconnect and final retransmission',all(all(after[i][k]==expected[i][k] for k in ['gold','max_hp','total']) for i in range(4)),after)
    print('RESULT: '+str(len(results))+' passed',flush=True)
finally:
    for role in ('host','client'):
        try:(folder/f'{role}-command.json').write_text(json.dumps(dict(id=read(role)['command']+1,action='quit')),encoding='utf-8')
        except (OSError,KeyError):pass
