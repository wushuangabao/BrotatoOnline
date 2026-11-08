# Brotato Online — 非官方修复版 / Unofficial Fixed Release

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
