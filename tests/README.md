# Retry scene reload regression

## Trusted personal shop results

```powershell
./tests/Test-TrustedShopLan.ps1 -ProjectPath E:/github/BrotatoMod/RecoveredProject
```

Two isolated Godot processes use production ENet and native shop callbacks. Assertions cover immediate lock/unlock (including the native retained-offer list), random reroll and charge, locked-offer retention, combine-then-buy, recycling, stale shop/scene-state suppression, host mirroring, duplicate/older revisions, old shop epochs, and seat ownership. The final recycle result is deliberately withheld from the normal publisher; the real start ACK must deliver it before both processes enter the battle. Controlled personal health, level/XP, chips and an armor effect also verify the handoff covers more than equipment and gold. A forced clock-ACK deadline verifies the host retries rather than committing old inventory. Publication timing, fixture data and the timeout are controlled; no gameplay or transport helper is substituted. Logs and source hashes are retained in `logs/trusted-shop-lan`.

The 40-check reconciliation suite below deliberately omits owner-epoch negotiation in its test manager and continues to cover the bootstrap/fallback reconciliation path. Its rejection behavior is not the normal owner-operated shop behavior. All LAN suites share port 27462 and must run sequentially.

## Mechanical weapon upgrades

```powershell
./tests/Test-MecaUpgradeLan.ps1 -ProjectPath E:/github/BrotatoMod/RecoveredProject
```

Uses two independent GodotSteam processes and production ENet on localhost port 27462 (run LAN suites sequentially). Deploy the current scripts and fixture first; the runner checks hashes and isolates profiles with only BrotatoOnline enabled and saving disabled. Evidence is retained in `logs/meca-upgrade-lan`.

The controlled endless-wave-21 shop fixture has a normal pistol, an SMG, a mechanical pistol and 80 items. Native focus and button signals drive six upgrades, alternating attribute choices. Preview and upgrade must complete in the input frame, before a host response. Host snapshots are deliberately sent before preview and during an open choice; an invalid legacy confirmation tests rejection traffic, and a double press tests single charging. Both peers must agree on rank, attributes and chips, with focus retained on the upgraded weapon. Additional boundary checks cover a late success while another weapon popup is open, stable identity lookup after Resource replacement, and ambiguous identical copies. These last checks inject state at the production helper boundary; they are not a natural packet-delay reproduction. No production helper is substituted. This does not establish physical mouse/controller, Steam WAN or arbitrary Mod compatibility.

## Multiple local client players

```powershell
./tests/Test-ClientCoopLan.ps1 -ProjectPath E:/github/BrotatoMod/RecoveredProject -HostPlayers 1 -ClientPlayers 3
./tests/Test-ClientCoopLan.ps1 -ProjectPath E:/github/BrotatoMod/RecoveredProject -HostPlayers 2 -ClientPlayers 2
```

Run these sequentially: both use localhost port 27462. The runner verifies every deployed production GDScript plus the fixture, isolates profiles with only BrotatoOnline enabled, and records source hashes, both process logs, JSON results and screenshots in `logs/client-local-coop-lan`. Saving is disabled.

The client injects held joypad accept events through Godot Input and vanilla's 0.7-second join timer. Physical controllers are not simulated as attached hardware, so vanilla may display keyboard icons for these injected devices. Selection and purchase use production UI callbacks. A controlled endless-wave-21 fixture supplies ordinary retained locked weapons and separate gold/inventories. Movement, damage, secondary-player death, host automatic battle start and reconnect use real production nodes and ENet transport. Reconnection is triggered explicitly; this is not an uncontrolled network-failure test.

Assertions cover independent seats, character confirmations, purchases, movement and damage; four-player capacity and duplicate joins; fixed battle rosters; authenticated ownership rejecting host-slot input/death spoofing; secondary-seat DLC pickup validation; saved ownership/layout restoration; and reconnect retaining all seats. The saved-layout check does not exercise restarting both applications and clicking Continue. Host extra seats are fixture-created. These tests do not establish physical-controller, Steam WAN, all-DLC or third-party-Mod compatibility.

## Retry reload

Install this checkout at `<Godot project>/mods-unpacked/wushuangabao-BrotatoOnlineFriends`, including `tests`, then run:

```powershell
./tests/Test-RetryReload.ps1 -ProjectPath E:/github/BrotatoMod/RecoveredProject
```

Requires the recovered Brotato project and GodotSteam 3.6 (override `-Godot` as needed). The runner isolates user data, disables saving, verifies the deployed dispatcher hash, and writes timestamped logs and screenshots beside the project under `logs/retry-reload-regression`.

This is a controlled runtime regression using actual battle scenes and the unmodified production scene dispatcher. It constructs a failed-wave UI state, supplies the retry message at the menu-sync boundary, and checks scene instance IDs. A test subclass isolates network roster lookup and RunData deserialization. It does not claim to exercise natural combat deaths, Steam/LAN delivery, or the full host/client ready handshake.

Coverage: a new retry within the previous 12-second flight window; repeated requests before/after scene creation; ordinary scene refresh; successive generations with identical path/config; late duplicate and stale generations after natural window expiry; session reset allowing start IDs to restart. Old duplicate/stale retries must not reapply RunData.

## Automatic late-client recovery

```powershell
./tests/Test-RetryReload.ps1 -ProjectPath E:/github/BrotatoMod/RecoveredProject -Suite recovery
```

The recovery suite runs host and client session state machines in one Godot process, with controlled message delivery. It drops the first start commit, forces the host ready deadline to expire, and verifies that a retry brings the client into a real new battle scene. It then drops the first ready ACK and verifies recovery without another scene reload. Other checks cover resend rate limits, queued-message backpressure, wrong-peer/stale ACKs, stale prepare/commit messages, finished battles, generation changes, session reset, and the reliable entity plus current-snapshot catchup packets.

The test substitutes transport delivery, host scene execution (the shared SceneTree belongs to the client), inventory deserialization and snapshot contents. Production recovery, timeout, commit, ACK, scene dispatch and catchup serialization execute unchanged. This is not a two-computer LAN/Steam or natural-combat test.

## Shop lock and purchase reconciliation

Before owner-epoch handoff, failed lock/buy corrections must bypass both whole-state and slot-state deduplication: identical host snapshots can still repair a locally changed card. The retained fallback protocol uses purchase receipts, private repairs and host revisions. The 40-check suite explicitly exercises that bootstrap/fallback path; normal personal shops now use owner results as described above.

```powershell
./tests/Test-RetryReload.ps1 -ProjectPath E:/github/BrotatoMod/RecoveredProject -Suite shop
./tests/Test-ShopPurchaseLan.ps1 -ProjectPath E:/github/BrotatoMod/RecoveredProject
```

Both shop runners use isolated saves and enable only BrotatoOnline. Install the current scripts and test scenes in the project before running them. The LAN suite uses localhost port 27462, which must be free.

The 40-check shop suite uses actual CoopShop, ordinary SMG/Lens offers retained from the previous wave, and native purchase/lock code. Controlled delivery of host rejection snapshots verifies that identical cached states restore lock visuals, sold/active state, button availability, gold and inventory. It also covers a state arriving after a successful purchase receipt, one outstanding repair, no duplicate purchase, no repair loop, old corrections/receipts/rerolls after a newer repair, partial lock deltas overtaking receipts or repairs, and ignoring receipts from a previous wave. Identity lookup is isolated in a test manager; transport rejection and the earlier cause of stale input are not simulated as natural gameplay.

The LAN suite launches two independent Godot processes. A controlled wave-21 fixture gives the client two pistols and a locked SMG from wave 20. Client production UI callbacks combine the pistols and buy the SMG in one turn, before receiving either reply. With owner handoff enabled, production ENet, native local actions, result mirroring and gear UI run unchanged. Both peers must finish with a tier-II pistol, one SMG and 9920 gold. Logs, source hashes, JSON snapshots and rendered screenshots are retained. This is not a Steam WAN or separate-machine test.
