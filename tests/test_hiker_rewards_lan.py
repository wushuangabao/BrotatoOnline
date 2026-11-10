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
    cmd('host','host'); wait(lambda h,c:h.get('lan_host') and h['online'])
    cmd('client','join'); wait(lambda h,c:h['members']==2 and c['members']==2)
    cmd('host','fixture'); shop()
    for wave in (2,3):
        wait(lambda h,c:bool(c.get('shop_epoch')) and h.get('go_hooked') and c.get('go_hooked') and h['shop_ready'][0] and c['shop_ready'][1])
        cmd('client','go',player=1); wait(lambda h,c:len(h.get('pressed',[]))>1 and h['pressed'][1]); cmd('host','go',player=0)
        wait(lambda h,c:h['scene']=='res://main.tscn' and c['scene']=='res://main.tscn' and h['wave']==wave and c['wave']==wave,30)
        time.sleep(3)
        before=[read('host')['players'][0],read('client')['players'][1]]
        for role,index in [('host',0),('client',1)]:
            cmd(role,'cat_steps',player=index,steps=79)
            cmd(role,'walk',player=index,direction=-1 if index==0 else 1)
            earned=read(role)['players'][index]
            check(f'wave {wave} P{index+1}: native 10-step gold and 80-step health',earned['max_hp']==before[index]['max_hp']+1 and earned['gold']==before[index]['gold']+48 and earned['total']==[before[index]['total'][0]+48,before[index]['total'][1]+1],earned)
        full=cmd('host','export_full',player=0)['state']
        order=cmd('client','snapshot_order',player=0,state=full)
        check('full RunData snapshot followed by its reward ledger does not apply attributes twice',order.get('valid') and order.get('stable'),order)
        check('older full snapshot cannot undo a newer reward ledger',order.get('older_snapshot'),order)
        h,c=wait(lambda h,c:all(h['players'][i]['gold']==c['players'][i]['gold'] and h['players'][i]['max_hp']==c['players'][i]['max_hp'] for i in (0,1)))
        wait(lambda h,c:all(p.get('actor_max_hp')==p['max_hp'] for s in [h,c] for p in s['players']))
        check(f'wave {wave}: live player maximum health matches synchronized RunData',True)
        expected=[dict(h['players'][0]),dict(c['players'][1])]
        time.sleep(2)
        count=read('client')['ledger']['reports']
        time.sleep(2)
        check(f'wave {wave}: acknowledged gameplay rewards stop resending',read('client')['ledger']['reports']==count,read('client')['ledger'])
        if '--hard-rejoin' in sys.argv and wave==2:
            cmd('client','hard_rejoin')
            wait(lambda h,c:c['online'] and c['scene']=='res://main.tscn',30)
        connected=cmd('client','reconnect')
        check(f'wave {wave}: same-process ENet reconnect completes',connected.get('online'),connected)
        time.sleep(2)
        h,c=read('host'),read('client')
        check(f'wave {wave}: reconnect preserves earned gold, health and owner array',all(c['players'][1][k]==expected[1][k] for k in ['gold','max_hp','total']),c['players'][1])
        check(f'wave {wave}: gameplay rewards converge before settlement',True)
        guard=cmd('host','ledger_guards')
        check(f'wave {wave}: replay, stale, foreign-owner and retry fences',all(guard.get(x) for x in ['duplicate','stale','wrong_owner','wrong_generation']),guard)
        if wave==2:
            cmd('host','capture_report')
            cmd('client','die');cmd('host','die')
            wait(lambda h,c:h.get('retry_visible') and c.get('retry_visible'),30)
            cmd('client','retry_confirm');cmd('host','retry_confirm')
            wait(lambda h,c:h.get('retries')==1 and c.get('retries')==1 and not h.get('retry_visible') and not c.get('retry_visible'),30)
            time.sleep(3)
            h,c=read('host'),read('client')
            check('real death and retry roll back earned gold, health and array counters',all(all(s['players'][i][k]==before[i][k] for k in ['gold','max_hp','total']) for i,s in [(0,h),(1,c)]),[h['players'],c['players']])
            replay=cmd('host','replay_prior')
            check('late packets from actual prior attempt cannot restore rolled-back rewards',replay.get('unchanged'),replay)
            cmd('client','loss',reports=100);cmd('host','loss',acks=2)
            for role,index in [('host',0),('client',1)]:
                cmd(role,'cat_steps',player=index,steps=79)
                cmd(role,'walk',player=index,direction=-1 if index==0 else 1)
            h,c=read('host'),read('client')
            check('reconnect starts with truly unacknowledged owner rewards',h['players'][1]['gold']==before[1]['gold'] and c['players'][1]['gold']==before[1]['gold']+48,[h['players'][1],c['players'][1]])
            if '--hard-rejoin' in sys.argv:
                cmd('client','hard_rejoin')
                wait(lambda h,c:c['online'] and c['scene']=='res://main.tscn',30)
            else:
                cmd('client','reconnect')
            cmd('client','loss',reports=2)
            h,c=wait(lambda h,c:all(h['players'][i]['gold']==c['players'][i]['gold'] and h['players'][i]['max_hp']==c['players'][i]['max_hp'] for i in (0,1)))
            expected=[dict(h['players'][0]),dict(c['players'][1])]
            check('lost reward reports are retried after real retry',c['dropped_reports']>=2,c['dropped_reports'])
        # Host-authoritative materials from another source must survive the next reward packet.
        cmd('host','gold_bonus',player=1,amount=17)
        wait(lambda h,c:c['players'][1]['gold']==expected[1]['gold']+17)
        expected[1]['gold']+=17
        cmd('client','loss',reports=2);cmd('host','loss',acks=2)
        if '--wait-rejoin' in sys.argv and wave==3:
            cmd('host','combat_timer')
            cmd('client','disconnect');wait(lambda h,c:'title_screen' in c['scene'])
            cmd('host','finish_wave')
            wait(lambda h,c:h['ledger']['waiting'])
            ticks=read('host')['combat_ticks']
            time.sleep(2)
            check('combat scene timers stop while waiting for disconnected owner',read('host')['combat_ticks']==ticks and read('host')['paused'])
            check('wave end waits for disconnected owner instead of discarding final statistics',read('host')['scene']=='res://main.tscn' and read('host')['ledger']['waiting'])
            cmd('host','capture_screen',label='waiting-for-rewards')
            cmd('client','join')
        else:
            cmd('host','finish_wave')
        shop(); time.sleep(3)
        check(f'wave {wave}: final record and acknowledgement loss exercised',read('client')['dropped_reports']>=2 and read('host')['dropped_acks']>=2)
        for role in ['host','client']:
            after=read(role)['players']
            check(f'wave {wave}: {role} keeps materials, max HP and array tracking in shop',all(all(after[i][k]==expected[i][k] for k in ['gold','max_hp','total']) for i in (0,1)),after)
    print('RESULT: '+str(len(results))+' passed',flush=True)
finally:
    for role in ('host','client'):
        try:(folder/f'{role}-command.json').write_text(json.dumps(dict(id=read(role)['command']+1,action='quit')),encoding='utf-8')
        except (OSError,KeyError):pass
