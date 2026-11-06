# Brotato Online — 非官方修复版 / Unofficial Fixed Release

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
