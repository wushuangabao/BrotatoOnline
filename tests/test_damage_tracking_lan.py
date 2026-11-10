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
    wait(lambda h,c: h['members']==2 and c['members']==2 and c['online'] and h['session']==c['session'] and len(h.get('roster',[]))==2 and len(c.get('roster',[]))==2)
    check('two independent retail processes connected through LAN',True)
    cmd('host','fixture')
    shop()
    wait(lambda h,c: len(c['players'])==2 and all(p['character'].endswith('wang_ye_xiang') for p in c['players']))
    if '--luck-gains' in sys.argv:
        cmd('client','add_luck_item',player=1)
        cmd('client','reroll',player=1)
        wait(lambda h,c: c['players'][1].get('luck')==40)
    for wave in (2,3):
        wait(lambda h,c: bool(c.get('shop_epoch')) and h.get('go_hooked') and c.get('go_hooked') and h['shop_ready'][0] and c['shop_ready'][1])
        cmd('client','go',player=1)
        wait(lambda h,c: len(h.get('pressed',[]))>1 and h['pressed'][1])
        cmd('host','go',player=0)
        wait(lambda h,c: h['scene']=='res://main.tscn' and c['scene']=='res://main.tscn' and h['wave']==wave and c['wave']==wave,30)
        if '--luck-gains' in sys.argv:
            # Compact shop snapshots omit raw stat effects; the pre-battle full
            # personal-state handoff is their actual synchronization boundary.
            h,c=wait(lambda h,c: h['players'][1].get('luck')==40 and c['players'][1].get('luck')==40)
            check(f'wave {wave}: doubled luck survives full pre-battle state handoff',True,[h['players'][1],c['players'][1]])
        time.sleep(3) # Native parachute landing before movement is intentional.
        baseline_owner=read('client')['players'][1]
        before=baseline_owner['total']
        # The other player spawns to our left; walk right to avoid testing ally collision.
        moved=cmd('client','walk',player=1,direction=1)
        check(f'wave {wave}: guest actually walks', moved.get('distance',0)>128,moved)
        h,c=wait(lambda h,c: c['players'][1]['spawned']>=2 and h['players'][1]['spawned']>=2)
        check(f'wave {wave}: guest trail exists on both peers',True,[h['players'][1],c['players'][1]])
        hit=cmd('client','hit_trap',player=1)
        check(f'wave {wave}: guest trail explodes once and damages both enemies',hit.get('damage')==hit_damage and hit.get('area_damage')==hit_damage and hit.get('tracked_delta')==wave_damage and hit.get('consumed'),hit)
        if wave==2:
            # Host checks its independently simulated copy of the guest trail too.
            hosthit=cmd('host','hit_trap',player=1)
            check('host copy of guest trap retains owner and area damage',hosthit.get('damage')==hit_damage and hosthit.get('area_damage')==hit_damage,hosthit)
        if wave==2:
            h,c=wait(lambda h,c:c['players'][1]['total']==wave_damage)
            check('two peers simulate damage but local owner total is not doubled',True)
            native=cmd('client','native_tracking',player=1)
            check('native explosion hit callbacks record five vanilla character keys and one item key',len(native.get('keys',{}))==6 and all(v['damage']==13 and v['gain']==13 for v in native['keys'].values()),native)
            cmd('host','native_tracking',player=1)
            cmd('client','custom_tracking',player=1)
            reports=read('client')['ledger']['reports']
            time.sleep(2)
            check('pure damage and custom statistics generate no in-battle reports',read('client')['ledger']['reports']==reports,read('client')['ledger'])
        if wave==3 and '--hard-rejoin' in sys.argv:
            retry_count=read('client')['retries']
            cmd('client','die');cmd('host','die')
            wait(lambda h,c:h.get('retry_visible') and c.get('retry_visible'),30)
            cmd('client','retry_confirm');cmd('host','retry_confirm')
            wait(lambda h,c:h['retries']==c['retries']==retry_count+1 and not h.get('retry_visible') and not c.get('retry_visible'),30)
            time.sleep(3)
            restored=read('client')['players'][1]
            check('real retry rolls damage and custom counters back to this wave baseline',all(restored[k]==baseline_owner[k] for k in ['total','current','last','custom_array','custom_scalar','stock']),[baseline_owner,restored])
            cmd('client','walk',player=1,direction=1)
            wait(lambda h,c:c['players'][1]['spawned']>=2)
            hit=cmd('client','hit_trap',player=1)
            check('post-retry native damage is counted once',hit.get('tracked_delta')==wave_damage and read('client')['players'][1]['total']==before+wave_damage,hit)
        if wave==2 and '--hard-rejoin' in sys.argv:
            previous=read('client')['players'][1]
            cmd('client','hard_rejoin')
            wait(lambda h,c:c['online'] and c['scene']=='res://main.tscn',30)
            time.sleep(2)
            current=read('client')['players'][1]
            check('title rejoin restores lifetime, current-wave and custom statistics',all(current[k]==previous[k] for k in ['total','current','last','custom_array','custom_scalar','stock']),[previous,current])
        if wave==2 and '--delay-settlement' in sys.argv:
            cmd('client','hold_settlement')
        cmd('host','finish_wave')
        if wave==2 and '--delay-settlement' in sys.argv:
            h,c=wait(lambda h,c: 'coop_shop' in h['scene'] and c['scene']=='res://main.tscn' and c.get('settlement_held'),30)
            check('host reaches shop while client settlement remains deliberately pending',not c['wave_settled'] and c['players'][1]['last']==0,c['players'][1])
            time.sleep(1)
            c=read('client')
            check('client remains in combat until native settlement completes',c['scene']=='res://main.tscn' and c['players'][1]['total']==before+wave_damage,c['players'][1])
            cmd('client','release_settlement')
        shop()
        time.sleep(1)
        h,c=read('host'),read('client')
        check(f'wave {wave}: final owner counters converge without duplicate simulation',h['players'][1]['total']==c['players'][1]['total']==before+wave_damage,[h['players'][1],c['players'][1]])
        if wave==2:
            check('final stock and custom scalar/array counters converge',h['players'][1]['stock']==c['players'][1]['stock'] and all(v==13 for v in c['players'][1]['stock'].values()) and h['players'][1]['custom_array']==[11,22] and h['players'][1]['custom_scalar']==33)
        check(f'wave {wave}: guest last-wave and cumulative counters survive shop transition',c['players'][1]['last']==wave_damage and c['players'][1]['total']==before+wave_damage,c['players'][1])
        check(f'wave {wave}: guest damage does not leak into host character',c['players'][0]['total']==0,c['players'][0])
        compact=cmd('client','compact_check',player=1)
        check(f'wave {wave}: compact inventory carries every dog statistics key',compact.get('included')==[True,True,True],compact)
        if wave==2:
            restore=cmd('client','restore_check',player=1)
            check('stale host snapshot preserves guest local counters; explicit retry restores snapshot',restore.get('preserved') and restore.get('retry_restored') and restore.get('luck_unchanged'),restore)
        cmd('client','reroll',player=1)
        time.sleep(1)
        c=read('client')
        check(f'wave {wave}: personal shop synchronization preserves counters',c['players'][1]['total']==before+wave_damage and c['players'][1]['last']==wave_damage,c['players'][1])
    # Third wave produces no damage: total stays, last-wave counters must become zero.
    before=read('client')['players'][1]['total']
    wait(lambda h,c:bool(c.get('shop_epoch')) and h.get('go_hooked') and c.get('go_hooked') and h['shop_ready'][0] and c['shop_ready'][1])
    cmd('client','go',player=1);wait(lambda h,c:len(h.get('pressed',[]))>1 and h['pressed'][1]);cmd('host','go',player=0)
    wait(lambda h,c:h['scene']=='res://main.tscn' and c['scene']=='res://main.tscn',30)
    wait(lambda h,c:not h['start_guard'] and not c['start_guard'])
    cmd('client','custom_tracking',player=1,zero=True)
    wait(lambda h,c:c['players'][1]['custom_array']==[0,0] and c['players'][1]['custom_scalar']==0)
    check('custom counters can reset to zero without stale values returning',True)
    cmd('client','custom_tracking',player=1,zero=True,array=[])
    cmd('host','finish_wave');shop();time.sleep(1)
    h,c=wait(lambda h,c:h['players'][1]['total']==c['players'][1]['total']==before and h['players'][1]['last']==c['players'][1]['last']==0)
    check('zero-damage wave preserves total and clears previous-wave damage on both peers',True)
    check('empty array replaces the previous array on both peers',h['players'][1]['custom_array']==c['players'][1]['custom_array']==[],[h['players'][1]['custom_array'],c['players'][1]['custom_array']])
    wait(lambda h,c:bool(c.get('shop_epoch')) and h.get('go_hooked') and c.get('go_hooked') and h['shop_ready'][0] and c['shop_ready'][1])
    cmd('client','go',player=1);wait(lambda h,c:len(h.get('pressed',[]))>1 and h['pressed'][1]);cmd('host','go',player=0)
    wait(lambda h,c:h['scene']=='res://main.tscn' and c['scene']=='res://main.tscn',30)
    cmd('client','custom_tracking',player=1,array=list(range(70)),scalar=-3.5)
    cmd('host','finish_wave');shop();time.sleep(2)
    h,c=read('host'),read('client')
    check('numeric arrays longer than 64 and signed fractional counters survive final transfer',all(s['players'][1]['custom_array']==list(range(70)) and s['players'][1]['custom_scalar']==-3.5 for s in [h,c]))
    cmd('client','screenshot',player=1,label='damage-statistics')
    print('RESULT: '+str(len(results))+' passed',flush=True)
finally:
    for role in ('host','client'):
        try:
            (folder/f'{role}-command.json').write_text(json.dumps(dict(id=read(role)['command']+1,action='quit')),encoding='utf-8')
        except (OSError,KeyError):
            pass
