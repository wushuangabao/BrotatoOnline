# Brotato Online Friends

[简体中文](README.md) | **English**

> **Independent fork 6.8.2 (2026-11-10)**. Original author: six666. Fork maintainer: wushuangabao.
> Trusted multiplayer for friends: personal shops and mechanical upgrades apply locally, then synchronize results. Supports multiple local players per client, up to four players total, with retry and automatic battle entry fixes. See [CHANGELOG.md](CHANGELOG.md) for details and validation scope.
> New Mod ID: `wushuangabao-BrotatoOnlineFriends`, intended for a separate Workshop item. Every player must use this version and disable the original or older fixed releases with ID `six666-BrotatoOnline`.
> [Original project](https://github.com/xx666zz/BrotatoOnline) · [Fixed source](https://github.com/wushuangabao/BrotatoOnline) · [GPL-3.0 license](LICENSE)

> Remote and LAN multiplayer support for *Brotato*, using a host-led hybrid synchronization model.

![Brotato](https://img.shields.io/badge/Brotato-1.2.0.1-6c5ce7)
![ModLoader](https://img.shields.io/badge/ModLoader-6.3.0-0984e3)
![Players](https://img.shields.io/badge/Players-1--4-00b894)
![License](https://img.shields.io/badge/License-GPL--3.0-f39c12)

Brotato Online is a mod that adds multiplayer support to *Brotato*. It currently supports Steam friend lobbies, Steam public lobbies, and LAN sessions while synchronizing the main flow from character and weapon selection through combat, upgrades, shops, and continued runs.

The goal is not to replace Brotato's original co-op flow with a completely different multiplayer mode. Instead, the project tries to preserve the vanilla co-op experience and mod compatibility while allowing players on different machines to share the same run.

## Usage

### Selection input and saved-run fixes (6.8.2)

Fixes hidden character lists and extra join panels after client initialization, and prevents local input from affecting remote seats on character/weapon screens. When restoring additional client seats, available connected controllers are tried before falling back to the keyboard; existing in-process device choices retain priority.

Keep the original save and online identity files to continue a 6.8.1 network co-op run. Connect the devices you intend to use now, let the original host choose Continue, and have clients join the newly opened room from the title screen. Saved identity determines character ownership; the current setup can use two controllers or a controller plus keyboard on either peer.

Four original 6.8.1 network saves were each resumed with four host/client input configurations: all 16 paths and 944 runtime assertions passed. Selection regressions passed another 414 assertions. These use independent local processes, real ENet/LAN and injected input. Physical-controller hotplug swaps remain undiagnosed and unfixed; Steam across computers and Workshop installation still need testing. See [save compatibility](docs/save-compatibility-validation.md) and [input validation](docs/selection-input-validation.md).

### Wave settlement fixes (6.8.1)

When the host reaches the shop first, clients finish local wave-end callbacks, harvesting and per-wave cleanup before applying the host's final state and changing scenes. This fixes skipped local step accounting and missing leftover-material ledger synchronization, and prevents repeated settlement. Local two-process LAN checks cover delayed settlement, crates and upgrades, dinosaur eggs and mutations, endless harvesting decay and material conversion. See the [validation report](docs/wave-settlement-validation.md).

### Trusted personal shops (since 6.8.0)

Each client executes its own purchases, rerolls, locks, combines, recycling, dismantling and mechanical upgrades immediately, including random results. The host mirrors and relays per-player results instead of replaying clicks or rolling back local edits. Closely spaced operations share a snapshot; the latest unacknowledged result is retried.

The host still coordinates the shared battle and scene changes. The start handshake collects each client's final shop state before committing, retrying the handoff while a connected peer has not replied. Seat ownership, shop epochs and increasing revisions prevent cross-player updates, duplicates and stale-state rollback. Upgrade rewards and item-box pages retain their existing authority model.

The handoff includes full personal `PlayerRunData` (equipment and modifications, items and effects, health, level/XP, gold and chips), plus offers, locks and reroll counters. The host combines these with shared wave, difficulty, zone, DLC, elite and event configuration to rebuild the start snapshot. Previous-wave enemies, projectiles and temporary scene nodes are not carried as personal state.

This release uses network protocol **`6.5.0`**. Update the host and every client to **6.8.2**; it cannot mix with 6.7.0 or the original Mod. Settings and online identity storage use the new ID and are not automatically migrated. Other mods that declare dependencies/load order or find the API using the old Mod ID need to adopt the new ID.

### Multiple local players on a client

After joining a room, remain on character selection and hold the vanilla co-op join button on each additional device for about 0.7 seconds (controller A/confirm or keyboard Space; follow the in-game prompt). The host assigns each new seat and shares the roster with everyone.

- Keyboard/mouse plus controllers or multiple controllers share the room's four-player limit: host 1 + client 3, or 2 + 2, for example.
- Local players select characters, shop, move, take damage and die independently. Adding seats is limited to character selection, before the run starts.
- The first player uses the configured online input device. Select keyboard/mouse there first if controllers should join as additional players.
- Reconnection retains all seats belonging to that client. Connect enough devices before continuing a saved run. Kicking a client removes all of its seats.
- Update the host and every client to 6.8.2 (network protocol `6.5.0`). It cannot mix with older releases or the original Mod.

Automated verification uses two local Godot processes, real LAN transport and injected device input. Physical controllers and Steam sessions across computers still require testing. See [tests/README.md](tests/README.md) for commands and scope.

### Steam

1. Install and enable Brotato Online for every player.
2. The host creates a lobby in-game.
3. Invite friends through Steam or make the lobby public.
4. Clients join through the Steam invite or the in-game lobby browser.
5. Once everyone is in the same session, use the normal co-op character, weapon, and run flow.

### LAN

LAN sessions can be used directly without Steam lobby discovery.

- Prefer automatic LAN discovery in the lobby browser.
- If broadcast discovery is unavailable, use **Direct Connect (LAN)** with the host IP and port.
- The default game port is `27462`; LAN discovery uses `27463`.

> Steam public lobbies and discovered LAN rooms appear in the same lobby browser.

### Saved Runs and Reconnection

When resuming a multiplayer run, players can rejoin in any order. Characters, equipment, and shop data remain assigned to their original slots.

- When resuming an older save for the first time, the host must assign players on the **Player Ownership** screen. Ownership is remembered for future sessions. To change players or devices, use **Reassign Characters**.

- During combat or in the shop, only the original player can reconnect. To replace a player, return to the main menu and have the host select **Continue** to reassign the character.

- Identity records are stored separately in `user://mod_data/wushuangabao-BrotatoOnlineFriends/`, without modifying the vanilla save structure. Back up this directory when transferring saves.

Character ownership restoration and reassignment were contributed by [@Perdixky](https://github.com/Perdixky) in [PR #12](https://github.com/xx666zz/BrotatoOnline/pull/12).

## Features

### Sessions and lobbies

- Up to 4 players
- Steam friend lobbies and friend invitations
- Steam public lobby browser
- Public lobby host, player count, phase, and latency display
- View the host's loaded mod list before joining
- Automatic LAN lobby discovery
- Manual LAN connection by IP and port
- Shared session logic across Steam and LAN transports
- Clear errors for version/protocol mismatch, full rooms, stale lobbies, and other join failures

### Game-flow synchronization

- Character and weapon selection
- Difficulty, zone, and run configuration
- Game start and scene transitions
- Wave progression and important combat state
- Player HP, death, and failed-wave flow
- Upgrades, item boxes, and shop progression
- Ready/cancel-ready and other online menu actions
- Continuing vanilla co-op saves
- Reserved in-run slots and reconnect flow for continued runs

### Combat synchronization

Brotato Online is not a fully host-authoritative simulation. Different kinds of state use different synchronization strategies. The Host leads shared progression and critical state, while Clients still simulate substantial parts of the game locally so Brotato's original logic can be reused without replicating everything at high frequency.

### Multiplayer UX

- Quick-chat wheel
- Custom quick-chat phrases, up to 20 characters each
- Option to disable custom quick chat and accept only built-in phrases
- Selectable local multiplayer input device
- Keyboard/mouse and gamepad support
- Optional outline for locally controlled characters
- Safe return to the main menu when the host disconnects unexpectedly
- Chinese and English UI text

## Installation

### Steam Workshop

If you use the Workshop build, subscribe to Brotato Online Friends and enable it in ModLoader, with the original and older fixed releases disabled.

### Manual/development build

Install the project as a ModLoader-compatible Godot mod and keep the expected mod directory name:

```text
wushuangabao-BrotatoOnlineFriends
```

Current compatibility:

| Component                       | Version    |
| ------------------------------- | ---------- |
| Brotato (locally tested)         | `1.2.0.1` |
| ModLoader                       | `6.3.0`    |
| Brotato Online release          | `6.8.2`    |
| Brotato Online network protocol | `6.5.0` |
| Maximum players                 | `4`        |

## Network Architecture

```mermaid
flowchart TD
    A[Steam Lobby / SteamNetworkingMessages] --> S[SessionManager]
    B[LAN Discovery / ENet] --> S

    S --> M[MenuSyncManager]
    S --> I[OnlineInputManager]
    S --> R[BattleReplicaManager]

    M --> G[Vanilla Brotato co-op flow]
    I --> G
    R --> G

    S --> API[BrotatoOnlineAPI]
    API --> MOD[Third-party mods]
```

The central rule is simple: **SessionManager owns session state, Host/Client roles, and message routing; Steam/LAN only provide transport; menu, input, and combat each use synchronization suited to their own state.**

This keeps gameplay logic independent from a single networking backend and allows combat synchronization to evolve without rewriting lobby/session handling.

## Main Modules

```text
wushuangabao-BrotatoOnlineFriends/
├─ manifest.json
├─ mod_main.gd
├─ scripts/
│  ├─ session_manager.gd
│  ├─ steam_transport.gd
│  ├─ lan_transport.gd
│  ├─ lan_discovery.gd
│  ├─ public_lobby_browser.gd
│  ├─ menu_sync_manager.gd
│  ├─ online_player_slot_manager.gd
│  ├─ online_input_manager.gd
│  ├─ battle_replica_manager.gd
│  ├─ state_snapshot.gd
│  ├─ upgrade_runtime_sync.gd
│  ├─ online_mod_settings_manager.gd
│  ├─ quick_chat_wheel.gd
│  ├─ brotato_online_api.gd
│  └─ ...
├─ extensions/
│  └─ ...
├─ docs/
│  ├─ API.md
│  └─ API.en.md
└─ translations/
   ├─ brotato_online_zh.txt
   └─ brotato_online_en.txt
```

| Module                           | Role                                                                                         |
| -------------------------------- | -------------------------------------------------------------------------------------------- |
| `session_manager.gd`             | Session ownership, host/client roles, connections, disconnect/reconnect, and message routing |
| `steam_transport.gd`             | Steam lobby callbacks and SteamNetworkingMessages transport                                  |
| `lan_transport.gd`               | LAN/ENet connections and data transport                                                      |
| `lan_discovery.gd`               | LAN lobby broadcast discovery                                                                |
| `public_lobby_browser.gd`        | Steam public lobbies, LAN rooms, latency probing, and host mod information                   |
| `menu_sync_manager.gd`           | Character, weapon, upgrade, shop, and other menu-phase synchronization                       |
| `online_player_slot_manager.gd`  | Player slots, remote placeholders, and input-device mapping                                  |
| `online_input_manager.gd`        | Client input capture and host-side input application                                         |
| `battle_replica_manager.gd`      | Client combat-state application, entity presentation, and battle-end coordination            |
| `state_snapshot.gd`              | Host combat snapshots, important state, and event serialization                              |
| `upgrade_runtime_sync.gd`        | Runtime upgrade-state synchronization                                                        |
| `online_mod_settings_manager.gd` | Input device, player outline, quick-chat, and multiplayer settings                           |
| `brotato_online_api.gd`          | Stable integration API for third-party mods                                                  |

Scripts under `extensions/` handle vanilla edge cases exposed by cross-machine multiplayer, including invalid node access, player-count differences, scene exit, shop interaction, pause-menu focus, and combat cleanup timing.

## Third-party Mod API

Brotato Online exposes a public API so other mods do not need to depend on internal manager nodes.

Full documentation: [`docs/API.en.md`](docs/API.en.md)

### Get the API

```gdscript
var bo_api = null

func _ready():
    var apis = get_tree().get_nodes_in_group("brotato_online_api")
    if apis.size() > 0:
        bo_api = apis[0]
```

### Helper for one-owner gameplay logic in third-party mods

```gdscript
if bo_api == null or bo_api.should_run_authoritative_logic():
    # Offline or host: mutate the real game state
    run_gameplay_logic()
else:
    # Client: local visuals/UI or a request to the host only
    run_client_visual_logic()
```

The API also exposes:

- Online/host/client state
- Current multiplayer phase and context
- Local player indices and ownership checks
- Client-to-host custom messages
- Host broadcast and per-player messages
- Phase, slot-layout, and third-party message events

`should_run_authoritative_logic()` is a safe default helper for third-party mods: if custom logic changes shared game state and must only run once, it should usually run offline or on the Host. The function name does **not** mean that all internal Brotato Online combat simulation is host-authoritative.

Third-party mods should use `BrotatoOnlineAPI` instead of reaching into Brotato Online's internal managers directly.

## Mod Compatibility

Brotato Online tries to preserve vanilla co-op behavior, but online play requires a clear separation between host and client responsibilities.

Mods that are usually easier to support:

- Content mods that only add characters, weapons, or similar data and are installed by all players
- Content additions that do not replace vanilla online menus or critical synchronization flows
- Mods that explicitly integrate through the Brotato Online API

Mods that are more likely to conflict:

- Mods that alter character selection, weapon selection, upgrades, shops, or other UI interactions; button presses, focus, and page state may no longer synchronize correctly between host and clients
- Heavy rewrites of enemies, shops, upgrades, battle-end logic, or scene transitions
- Replacing vanilla co-op player slots or input mapping

Adding new content and replacing an existing flow are very different compatibility cases. A newly added character or weapon can usually reuse Brotato Online's existing selection and synchronization path. A UI mod, however, may replace buttons, focus handling, or page-transition logic and can therefore break synchronized clicks even when it looks purely cosmetic.

The public lobby browser can show the host's mod list before joining, but **matching mod lists do not guarantee compatibility, and different mod lists do not automatically mean the session cannot work**. Compatibility depends on what those mods actually change. 

## Documentation

- [`README.md`](README.md): 中文README
- [`docs/API.md`](docs/API.md): Chinese API documentation
- [`docs/API.en.md`](docs/API.en.md): English API documentation
- [`scripts/brotato_online_api.gd`](scripts/brotato_online_api.gd): API implementation exposed to other mods

## License

This project is licensed under the [GNU General Public License v3.0](LICENSE).
