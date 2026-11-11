"""Two retail LAN peers: native equipment UI and full-state receiver regression."""
import json
import os
import sys
import time
from pathlib import Path

folder = Path(sys.argv[1])
results = []
last_states = {}
streamer = os.environ.get('BROTATO_TEST_CHARACTER') == 'streamer'
base_engineering, armor_per_structure, engineering_per_structure = (0, 2, 0) if streamer else (25, 3, 3)
expected_inventory = [[1, 0, 0], [1, 1, 0]] # wrench count, landmine count, wrench tier
tool_tables = None

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

def expect(label, combat=False):
    def matches(h,c):
        for state in [h,c]:
            if len(state.get('players',[]))!=2:return False
            for i,(p,(weapons,mines,tier)) in enumerate(zip(state['players'],expected_inventory)):
                count=weapons+mines
                armor=count*armor_per_structure
                n=weapons+tool_tables[i]['tool_set_bonus']
                bonus=tool_tables[i]['tool_engineering'][min(n-2,len(tool_tables[i]['tool_engineering'])-1)] if weapons and n>=2 else 0
                engineering=base_engineering+count*engineering_per_structure+bonus
                if (p.get('structures'),p.get('armor'),p.get('engineering'))!=(count,armor,engineering):return False
                if p.get('weapon_count')!=weapons or p.get('landmines')!=mines:return False
                if p.get('duplicate_count')!=max(0,weapons-1)+max(0,mines-1):return False
                if p.get('different_items')!=int(mines>0):return False
                if p.get('weapons')!=[[f'weapon_wrench_{tier+1}',tier]]*weapons:return False
                if len(p.get('structure_refs',[]))!=count or any(not r['owners'] for r in p['structure_refs']):return False
                if p.get('damage_gain')!=1:return False
                if combat and p.get('live_armor')!=armor:return False
        return True
    h,c=wait(matches,20)
    check(label,True,{'host':h['players'],'client':c['players']})

def repeat_all(label):
    before={role:read(role)['players'] for role in ('host','client')}
    for role in ('host','client'):
        for index in range(2):
            check(label+f': {role} P{index+1} applied three snapshots',cmd(role,'repeat_snapshot',player=index).get('applied')==3)
    expect(label+': no duplicate effects or cross-player stat changes')
    for role in ('host','client'):
        after=read(role)['players']
        check(label+f': {role} gold/max HP unchanged',all((a['gold'],a['max_hp'])==(b['gold'],b['max_hp']) for a,b in zip(before[role],after)))

def buy(role,index,item='wrench'):
    # Seed the same offer on both peers before sending a native purchase event.
    for peer in ('host','client'):
        cmd(peer,'set_offer',player=index,item=item)
    h,c=wait(lambda h,c:all(a['gold']==b['gold'] for a,b in zip(h['players'],c['players'])))
    gold=[p['gold'] for p in h['players']]
    price=cmd(role,'buy',player=index)['price']
    gold[index]-=price
    h,c=wait(lambda h,c:all([p['gold'] for p in state['players']]==gold for state in (h,c)))
    check(role+' '+item+' purchase charges exactly once and leaves other player gold unchanged',price>0)
    return price

def enter_wave():
    wait(lambda h,c: bool(c.get('shop_epoch')) and h.get('go_hooked') and c.get('go_hooked') and h['shop_ready'][0] and c['shop_ready'][1])
    cmd('client','go',player=1)
    wait(lambda h,c:len(h.get('pressed',[]))>1 and h['pressed'][1])
    cmd('host','go',player=0)
    wait(lambda h,c:h['scene']=='res://main.tscn' and c['scene']=='res://main.tscn',30)
    wait(lambda h,c:all('live_armor' in p for p in h['players']+c['players']),15)

try:
    wait(lambda h,c:'character_selection' in h['scene'] and 'title_screen' in c['scene'],60)
    cmd('host','host')
    wait(lambda h,c:h.get('lan_host') and h['online'])
    cmd('client','join')
    wait(lambda h,c:h['members']==2 and c['members']==2 and c['online'] and h['session']==c['session'] and len(h.get('roster',[]))==2 and len(c.get('roster',[]))==2)
    check('Two retail LAN peers connected with candidate Friends',True)
    for role in ('host','client'):
        nested=cmd(role,'nested_effect_roundtrip')
        check(role+' flame turret preserves deep native state and custom args',nested.get('serialized_nested_effect') and nested.get('same_native_state') and nested.get('burning_damage')==17 and nested.get('custom_args')==1,nested)
    cmd('host','fixture')
    shop()
    check('Requested normal/endless sync branch active on both peers',all(read(r).get('endless_sync')==(int(os.environ.get('BROTATO_TEST_WAVE','1'))>=21) for r in ('host','client')))
    tool_tables=read('host')['players']
    check('Character fixture matches requested vanilla/Noobs character',all(p['character']==('character_streamer' if streamer else 'character_wushuangabao_nwtl_xiao_tian_cai') for p in tool_tables))
    expect('Initial independent structure bonuses and inventory-effect references')
    repeat_all('Initial full-state roundtrip')
    enter_wave()
    expect('First wave: owner and remote live armor and engineering agree',True)
    cmd('host','finish_wave')
    shop()
    expect('Wave settlement preserves structure links without duplication')
    for role,index in [('host',0),('client',1)]:
        cmd(role,'sell_wrench',player=index)
        expected_inventory[index][0]=0
        expect(role+' native weapon sale removes only its own bonuses')
    for role,index in [('host',0),('client',1)]:
        for n in (1,2):
            price=buy(role,index)
            expected_inventory[index][0]=n
            expect(role+f' native purchase #{n} binds duplicate weapon effects')
            check(role+f' purchase #{n} has positive price',price>0)
        repeat_all(role+' duplicate identical wrenches')
        cmd(role,'combine',player=index)
        expected_inventory[index][0]=1
        expected_inventory[index][2]=1
        expect(role+' combine replaces two structures with one upgraded structure')
        repeat_all(role+' combined wrench')
        cmd(role,'sell_wrench',player=index)
        expected_inventory[index][0]=0
        expected_inventory[index][2]=0
        expect(role+' sale after combine and repeated full sync leaves no ghost structure')
        buy(role,index,item='landmines')
        expected_inventory[index][1]+=1
        expect(role+' native landmine purchase adds only its own item structure')
    repeat_all('Item-source duplicate effects')
    cmd('client','reroll',player=1)
    expect('Reroll does not restore removed structure bonuses')
    enter_wave()
    expect('Second wave reflects all equipment changes',True)
    cmd('host','finish_wave')
    shop()
    expect('Second settlement remains stable on both peers')
    print('RESULT: '+str(len(results))+' passed',flush=True)
except Exception as exc:
    (folder/'failure.json').write_text(json.dumps({'error':str(exc),'last_states':last_states},ensure_ascii=False,indent=2),encoding='utf8')
    raise
finally:
    for role in ('host','client'):
        try:
            path=folder/f'{role}-command.json'; temp=path.with_suffix('.tmp')
            temp.write_text(json.dumps(dict(id=read(role)['command']+1,action='quit')),encoding='utf-8'); temp.replace(path)
        except (OSError,KeyError):pass
