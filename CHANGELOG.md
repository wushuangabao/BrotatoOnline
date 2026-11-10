# Brotato Online — 非官方修复版 / Unofficial Fixed Release

## 6.8.2 — 2026-11-10 — 选人输入与联机旧档续玩修复

- 客户端选人初始化清空阵容时延后恢复权威布局，并重新同步界面与焦点，修复角色列表隐藏和多余加入框。
- 选人和武器页面按本机席位隔离输入；移除会同时别名本机键盘与第一手柄的远程占位设备 0，安全占位不足时拒绝不完整布局，避免串号。
- 修复客户端重启续档后第二个席位优先绑定键盘、忽略已连接第二手柄的问题：保留当前进程已有选择，否则先用空闲已连接手柄，最后回退键盘。
- 未改变存档格式或身份记录。原始 6.8.1 创建的四份真实 LAN 合作存档，分别以四种主客输入组合续档，16 条路径、944 条断言通过；角色、装备、进度与归属保持正确，设备按本次配置恢复。选人/武器及加入顺序回归另有 414 条通过。
- Mod ID 保持 `wushuangabao-BrotatoOnlineFriends`，网络协议保持 `6.5.0`；主机和所有客户端一起更新至 6.8.2。继续旧档需保留原存档和身份文件，客户端从主菜单加入主机重开的房间。
- 验证使用本机独立引擎进程、真实 ENet/LAN 和模拟设备输入；实体 A 键故障、短断连后手柄互换、Steam 跨机器及创意工坊安装尚未验证。未对未定位的热插拔问题作推测性修改。详见 `docs/selection-input-validation.md` 与 `docs/save-compatibility-validation.md`。

Fixes client character-screen initialization, isolates local selection input from remote seats, and uses available connected controllers before the keyboard fallback when restoring additional client seats. Save format and player identities are unchanged. All 16 cross-configuration paths from original 6.8.1 network saves passed, including changing devices on either peer; 944 save/resume assertions and 414 selection assertions passed. Update all peers to 6.8.2. Physical hotplug behavior, Steam WAN and Workshop installation remain unverified.

## 6.8.1 — 2026-11-09 — 波次结算同步修复

- Steam 已初始化且可取得有效 Steam ID 时直接复用现有实例，不再重复调用 `steamInitEx()` / `steamInit()`；未就绪时保留原有初始化及 LAN 回退流程。此修订沿用 6.8.1 并重新打包。
- 房主先进入商店时，客户端等待本机波末效果、收获计时器与 `RunData.on_wave_end()` 完成，再应用房主最终状态和切换场景，保留本地回调、步数进度及每波计数清理。
- 成功结束战斗的房主终态先于客户端计时器到达时，客户端仍执行原版波末效果；三个结算计时器入口增加单波去重，避免重复奖励和副作用。
- 场景同步补充未拾取材料账本 `bonus_gold` / `total_bonus_gold`。随机变异和恐龙蛋仍由房主结算并同步，客户端不重复抽取。
- 新增双进程 LAN 延迟结算与重复回调回归测试。详细验证范围和证据见 `docs/wave-settlement-validation.md`。
- Mod ID 保持 `wushuangabao-BrotatoOnlineFriends`，网络协议保持 `6.5.0`；房主和所有客户端均应更新至 6.8.1，确保各端都具备本次结算修复。

Clients now finish native local wave settlement before applying the host's shop state. Successful cleanup entries execute native wave-end effects, duplicate timer callbacks are ignored, and scene synchronization includes the leftover-material ledger. Host-owned mutation and dinosaur-egg results remain authoritative. The Mod ID and wire protocol remain unchanged; update every peer to 6.8.1 so all peers receive these fixes.

The revised 6.8.1 package also reuses an already initialized Steam instance with a valid Steam ID, avoiding repeated initialization while retaining initialization and LAN fallback for unavailable instances.

## 6.8.0 — 2026-11-09 — Brotato Online Friends

原作者 / Original author: **six666**。独立维护 / Fork maintainer: **wushuangabao**。本版本基于原项目修改，保留作者与许可证声明，遵循 GNU GPL v3。

- 个人商店操作改为客户端本地执行并同步结果，涵盖购买、刷新、锁定、合成、回收、拆解和机械升级；房主不重复抽取随机结果或回放这些操作。
- 合并短时间内的操作快照，重发未确认结果；按玩家归属、商店批次和版本号处理重复及过期包，防止旧快照和场景 RunData 撤销本地操作。
- 开打前收集客户端完整个人运行状态，包括武器、道具、属性效果、材料、机械芯片、生命、等级和经验，再构建进场数据；等待结果时重试交接，避免丢失最后一次购买或升级。
- 修复机械升级旧武器引用误匹配、迟到回包关闭当前弹窗、拒绝回包重建武器栏后丢失焦点，以及原版移除旧武器时的邻近槽位跳转。
- 使用独立 Mod ID **`wushuangabao-BrotatoOnlineFriends`**，可新建创意工坊条目发布。资源路径、节点查找、API 标识、设置与身份存储、大厅元数据和测试入口均切换到新 ID；声明与 `six666-BrotatoOnline` 互斥，避免同时加载两套联机逻辑。
- 网络协议升至 `6.5.0`；所有参与者须更新至 6.8.0。独立 ID 不自动迁移旧版 Mod 设置与身份文件；按旧 ID 集成的第三方 Mod 需要适配。

Personal shops now execute locally and synchronize owner results, including random rerolls and mechanical choices. Coalesced snapshots, acknowledgement retries, per-shop epochs and per-player revisions preserve local edits. The start handshake gathers full personal run state before building battle data. Mechanical upgrades preserve weapon identity and focus across delayed messages. This independent release uses Mod ID **`wushuangabao-BrotatoOnlineFriends`** and wire protocol **`6.5.0`**. Runtime paths, API IDs, settings/identity storage and lobby metadata use the new ID. Disable `six666-BrotatoOnline`; the manifest declares it incompatible. All peers must update to 6.8.0. Settings/identity data are not automatically migrated, and third-party integrations using the original ID need updating.

验证范围：GodotSteam 3.6、本机独立进程和真实 LAN；覆盖本地即时操作、完整个人状态交接、机械升级、1＋3／2＋2 本地多人、重连、失败重试和迟到客户端恢复。测试使用受控场景与输入，不代表实体手柄、Steam 跨机器网络或创意工坊订阅安装已验证。发布 ZIP 不包含游戏、测试、存档或日志。

Validation uses GodotSteam 3.6, independent local processes and real LAN with controlled fixtures/input. Coverage includes immediate shop actions, full personal-state handoff, mechanical upgrades, 1+3/2+2 local co-op, reconnect, retry and late-client recovery. Physical controllers, Steam WAN and Workshop subscription installation remain unverified. The ZIP excludes the game, tests, saves and logs.

## 6.7.0 — 2026-11-09

原作者 / Original author: **six666**。修复维护者 / Fix maintainer: **wushuangabao**。

This unofficial release was modified by wushuangabao on 2026-11-09. Original authorship and existing notices are retained. Distributed under the GNU GPL v3; see [LICENSE](LICENSE).

### 新增与修复

1. **客户端本地多人**：进入房间的角色选择页后，额外设备长按原版加入键约 0.7 秒即可加入。支持键鼠加手柄或多个手柄，全房间合计最多四人，例如房主一人加客户端三人、双方各两人。
2. **按角色同步与校验**：同一连接可拥有多个角色，各自独立选人、购物、移动、受伤和死亡；房主按连接归属校验角色编号，防止误操作其他玩家。同步补齐升级交互、DLC 拾取、暂停焦点和本地角色描边的多人归属处理。
3. **归属与重连**：为同一客户端的不同角色保留独立座位标识；断线重连恢复全部角色，存档归属布局支持一个客户端对应多个角色。踢出客户端会移除其全部角色。
4. **加入边界**：仅在角色选择阶段增加玩家，开局后固定阵容；重复加入请求不创建重复角色，迟到的拒绝消息不清除已确认座位。修复新增设备重建选人界面时的失效焦点引用。
5. 包含 6.6.8 的商店锁定与购买同步修复，以及此前的暂停商店同步、失败重试和客户端自动进场修复。

### 安装与兼容

- **房主和所有客户端均须更新至 6.7.0**。网络协议从 `6.3.0` 升至 `6.4.0`，不兼容 6.6.8 及更早版本；LAN 协议仍为 `4`。
- 内部 Mod ID 保持 `six666-BrotatoOnline`，请勿与原版同时启用。首名玩家使用联机设置中的输入设备；继续多人存档前请连接足够数量的设备。
- 发布 ZIP 仅含 Mod 源码、许可证、文档和打包脚本，不含游戏、测试场景、存档、日志或其他 Mod。

### 验证与范围

- GodotSteam 3.6、恢复的 Brotato 1.2.0.1 项目：两个独立本地进程通过真实 LAN 验证 **1＋3** 和 **2＋2** 组合，仅启用 BrotatoOnline，使用隔离存档。
- 注入设备长按事件经过原版加入计时器；选人、购物、开战、独立移动与受伤、次要角色死亡和重连采用实际生产代码。另验证人数上限、重复加入、归属越界拒绝、DLC 拾取校验和存档角色布局恢复。
- 原有商店同步 40 项、失败重试 10 项、自动进场 18 项受控运行时回归通过。复现脚本与准确验证边界见源码仓库 `tests/README.md`。
- 测试使用模拟输入、受控商店与伤害场景、主动触发的断线重连；存档测试覆盖归属布局恢复，未覆盖重启双方后点击继续的完整流程。实体手柄、Steam 跨机器联机、所有 DLC/第三方 Mod 组合及最终 ZIP 的创意工坊订阅安装尚未验证。

### Changes (English)

- Multiple local players can join one client by holding the vanilla co-op join button on additional devices during character selection. Keyboard/mouse plus controllers and multiple controllers share a four-player room limit.
- Track ownership per seat for independent character selection, shopping, movement, damage and death. Extend progression interactions, DLC pickup validation, pause focus and local outlines to all local seats.
- Preserve every seat on reconnect and distinguish seats in saved ownership layouts. Kicking a client removes all its seats. Reject over-capacity and in-run additions, handle duplicate requests safely, and clear stale focus references before selection controls are freed.
- Includes all 6.6.8 shop fixes and earlier retry/catchup fixes. Update **all peers to 6.7.0**: network protocol is now `6.4.0`, incompatible with 6.6.8 and earlier. LAN protocol and internal Mod ID remain unchanged.

Validation: two independent local LAN processes pass host 1 + client 3 and host 2 + client 2 scenarios with injected device input and controlled gameplay fixtures. Checks include per-seat actions, damage/death, reconnect, capacity, ownership rejection, DLC pickup routing and saved-layout restoration. The existing 68 shop/retry/catchup checks also pass. Physical controllers, Steam sessions across computers, a full restart-and-Continue flow, all DLC/third-party Mod combinations and Workshop installation of the final ZIP have not been tested.

## 6.6.8 — 2026-11-08

原作者 / Original author: **six666**。修复维护者 / Fix maintainer: **wushuangabao**。

This unofficial release was modified by wushuangabao on 2026-11-08. Original authorship and existing notices are retained. Distributed under the GNU GPL v3; see [LICENSE](LICENSE).

### 修复内容

1. **锁定商品恢复操作**：主机拒绝解锁或购买请求后，即使返回的权威状态与先前相同，也会恢复客户端的锁定标记、商品可用状态和按钮，避免纠正消息被缓存去重跳过。
2. **已购武器同步恢复**：修复较早的合成结果覆盖客户端随后购买的武器，而主机购买成功回复未能纠正的情况。购买成功后核对背包、金币和商品状态；不一致时自动向主机请求完整恢复，不重复购买或扣款。
3. **延迟消息保护**：通过主机状态版本防止旧消息回滚已恢复的数据。较新的局部消息抢先到达时，会补取完整状态；延迟购买回执和恢复响应不会仅因动作顺序而被丢弃。
4. 包含 6.6.7 的暂停商店同步、失败重试场景重载和客户端自动进场修复。

### 安装与兼容

- 房主和所有客户端均应更新至 **6.6.8**；购买回执恢复需要两端使用更新后的 Mod。
- 内部 Mod ID 仍为 `six666-BrotatoOnline`，请勿与原版同时启用。
- 网络协议仍为 `6.3.0`，LAN 协议仍为 `4`；协议号相同不代表旧版本具备本次修复。
- 更新现有创意工坊条目的 Mod ZIP 即可。ZIP 不含游戏本体、其他 Mod、测试场景、测试存档或日志。

### 已完成验证与范围

- 修复代码提交：`fff4e83`。GodotSteam 3.6、恢复的 Brotato 1.2.0.1 项目，40 项商店运行时检查通过；此前的 10 项重试和 18 项自动进场回归也通过。
- 商店测试仅启用 BrotatoOnline，使用隔离存档；普通冲锋枪和眼镜从上一波锁定保留，受控投递主机拒绝/纠正消息，验证恢复后可再次解锁和购买。
- 两个独立本地 Godot 进程通过真实 LAN 执行“合成两把手枪后立即购买锁定冲锋枪”：两端均保留二级手枪和冲锋枪，金币一致为 9920；没有重复购买。
- 覆盖延迟消息、完整恢复与局部锁定消息交错、重复恢复抑制以及上一波回执忽略。复现脚本和说明位于源码仓库的 `tests/`，不放入发布 ZIP。
- 锁定测试验证的是拒绝请求后的恢复路径，尚未还原用户长时间游玩的全部前置过程。本次没有验证 Steam 外网、不同物理机器或最终 ZIP 的创意工坊订阅安装。

### Changes (English)

- Restore locked offers and their buttons after rejected unlock/purchase requests, even when the host correction matches a previously cached state.
- Recover purchased weapons overwritten by an earlier combine result. Successful purchases include a compact inventory, gold and shop receipt; mismatches trigger a private authoritative repair without buying or charging twice.
- Prevent delayed messages from undoing repaired state. Request current full state when a newer partial delta overtakes a receipt or repair, and process delayed purchase results instead of dropping them solely because of action ordering.
- Includes all fixes from 6.6.7. Update **both the host and every client to 6.6.8**. The internal Mod ID and wire protocol versions remain unchanged; enable this release instead of the original.

Validation covers gameplay commit `fff4e83`: 40 shop checks plus the existing 28 retry/catchup checks passed. Two independent local LAN processes completed the combine-then-buy scenario with identical weapons and gold. Shop tests use isolated saves with only BrotatoOnline enabled. The lock regression uses controlled host rejection delivery, not the complete preceding long-play sequence. Steam WAN, separate-machine play and installation of the final ZIP through Workshop have not been tested in this release.

## 6.6.7 — 2026-11-06

原作者 / Original author: **six666**

修复维护者 / Fix maintainer: **wushuangabao**

This is a modified, unofficial release of Brotato Online, maintained by wushuangabao. The changes below were made on 2026-11-06. Original authorship and existing notices are retained. Distributed under the GNU GPL v3; see [LICENSE](LICENSE).

原项目 / Upstream: https://github.com/xx666zz/BrotatoOnline

修复版源码 / Fork source: https://github.com/wushuangabao/BrotatoOnline

### 修复内容

1. **暂停状态下商店同步**：暂停时继续处理商店同步，避免房主购物只修改本地状态。
2. **失败后重试重载**：新战斗批次绕过旧场景切换的去重窗口；重复或过期的重试消息不会再次重载或回写旧数据。
3. **客户端自动进场**：房主开打后，继续向尚未确认进场的客户端补发开始指令；客户端成功进场后补同步已有实体和当前战场状态。就绪回报丢失时可重新确认，不重复重载。

### 安装与兼容

- 创意工坊建议标题：**Brotato Online — 非官方联机修复版**。
- 保留内部 Mod ID `six666-BrotatoOnline`，请勿与原版同时启用。
- 房主和所有客户端应使用同一修复版本；不保证与未修复客户端混用的行为。
- 发布版本为 `6.6.7`；网络协议仍为 `6.3.0`，LAN 协议仍为 `4`。
- ZIP 仅含 Mod 源码和文档，不含游戏本体、其他 Mod、测试存档或测试场景。

### 已完成验证

- GodotSteam 3.6、恢复的 Brotato 1.2.0.1 项目：28 项受控运行时回归通过。
- 两个独立本地进程通过 LAN 在无尽第 22 波验证死亡、失败结算、双方点击重试和重新进场。
- 拦截客户端 18 次开局消息后解除拦截：客户端无需再次点击即可自动进入房主正在进行的战斗，采样倒计时差约 0.08 秒。
- 自动进场后客户端受到 1000 点伤害，房主正确同步血量；重复开局消息未造成再次重载。
- 测试使用隔离存档、增加的最大生命值和受控致命伤害，未开启无敌；Steam 外网和不同物理机器尚未验证。
- 上述游戏行为验证针对修复代码提交 `5ed7228ab01c615f605573aa9c0a4262ed2269dc`；本次发布额外更新版本与说明元数据。发布 ZIP 仍需在 Steam 游戏中进行订阅安装验证。

### Changes (English)

- Keep shop synchronization processing while paused, including host purchases.
- Allow new retry generations to reload the battle immediately, while ignoring duplicate/stale retry commands and their old RunData.
- Resend battle-start commands to unready clients after the host starts; accept late readiness acknowledgments and send existing entities plus current battle state. Repeated commands do not reload a client that already entered.

Enable this release **instead of** the original, and use the same release on every peer. The internal Mod ID and network protocol remain unchanged. Local two-process LAN tests passed, including controlled start-message loss and synchronized client damage after recovery. Steam WAN testing has not been performed. The 28 runtime checks and LAN tests cover gameplay code at commit `5ed7228`; this release additionally updates package metadata. Installation of the final ZIP through Steam still needs testing.
