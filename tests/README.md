# Retry scene reload regression

## Multiple local client players

```powershell
./tests/Test-ClientCoopLan.ps1 -ProjectPath E:/github/BrotatoMod/RecoveredProject -HostPlayers 1 -ClientPlayers 3
./tests/Test-ClientCoopLan.ps1 -ProjectPath E:/github/BrotatoMod/RecoveredProject -HostPlayers 2 -ClientPlayers 2
```

Run these sequentially: both use localhost port 27462. The runner verifies every deployed production GDScript plus the fixture, isolates profiles with only BrotatoOnline enabled, and records source hashes, both process logs, JSON results and screenshots in `logs/client-local-coop-lan`. Saving is disabled.

The client injects held joypad accept events through Godot Input and vanilla's 0.7-second join timer. Physical controllers are not simulated as attached hardware, so vanilla may display keyboard icons for these injected devices. Selection and purchase use production UI callbacks. A controlled endless-wave-21 fixture supplies ordinary retained locked weapons and separate gold/inventories. Movement, damage, secondary-player death, host automatic battle start and reconnect use real production nodes and ENet transport. Reconnection is triggered explicitly; this is not an uncontrolled network-failure test.

Assertions cover independent seats, character confirmations, purchases, movement and damage; four-player capacity and duplicate joins; fixed battle rosters; authenticated ownership rejecting host-slot input/death spoofing; secondary-seat DLC pickup validation; saved ownership/layout restoration; and reconnect retaining all seats. The saved-layout check does not exercise restarting both applications and clicking Continue. Host extra seats are fixture-created. These tests do not establish physical-controller, Steam WAN, all-DLC or third-party-Mod compatibility.

## Retry reload

Install this checkout at `<Godot project>/mods-unpacked/six666-BrotatoOnline`, including `tests`, then run:

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

Failed lock/buy corrections must bypass both whole-state and slot-state deduplication: identical host snapshots can still repair a locally changed card. Successful purchases carry a compact inventory/slot/gold receipt; a mismatch requests a private full repair instead of repeating the purchase. Host revisions prevent old packets from undoing a repair. A newer partial delta does not prove that older inventory fields arrived, so an uncovered stale receipt/repair requests current full state. These checks apply to the purchasing client's own prediction; observer synchronization is unchanged. Both peers need the updated Mod for receipt-based recovery.

```powershell
./tests/Test-RetryReload.ps1 -ProjectPath E:/github/BrotatoMod/RecoveredProject -Suite shop
./tests/Test-ShopPurchaseLan.ps1 -ProjectPath E:/github/BrotatoMod/RecoveredProject
```

Both shop runners use isolated saves and enable only BrotatoOnline. Install the current scripts and test scenes in the project before running them. The LAN suite uses localhost port 27462, which must be free.

The 40-check shop suite uses actual CoopShop, ordinary SMG/Lens offers retained from the previous wave, and native purchase/lock code. Controlled delivery of host rejection snapshots verifies that identical cached states restore lock visuals, sold/active state, button availability, gold and inventory. It also covers a state arriving after a successful purchase receipt, one outstanding repair, no duplicate purchase, no repair loop, old corrections/receipts/rerolls after a newer repair, partial lock deltas overtaking receipts or repairs, and ignoring receipts from a previous wave. Identity lookup is isolated in a test manager; transport rejection and the earlier cause of stale input are not simulated as natural gameplay.

The LAN suite launches two independent Godot processes. A controlled wave-21 fixture gives the client two pistols and a locked SMG from wave 20. Client production UI callbacks combine the pistols and buy the SMG in one turn, before receiving either reply. Production ENet transport, action execution, receipt comparison, private repair request/response, inventory restoration and gear UI all run unchanged. Both peers must finish with a tier-II pistol, one SMG and 9920 gold. Logs, source hashes, JSON snapshots and rendered screenshots are retained. This is not a Steam WAN or separate-machine test.
