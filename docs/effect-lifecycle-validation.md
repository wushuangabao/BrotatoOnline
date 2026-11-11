# 6.8.4 发布前独立审核与效果生命周期验证

日期：2026-11-11。本次覆盖此前已打包、已推送 Git 但尚未正式发布的 6.8.4。版本号保持 6.8.4，网络协议从测试包的 6.5.2 更新到 6.5.3；6.8.3 包和 Git 记录不变。只修改 Friends 通用同步层，没有修改 Noobs 角色代码。

## 已复现的两个问题

1. **6.8.4 新回归**：原生 `Effect.serialize()` 保存已生成的描述参数，却未保存 `_custom_args_added`。恢复后再次 `get_text()` 会追加参数。原始零售探针中，火焰炮塔参数从 1 增到 11，序列化大小每轮增加 71 字节；没有据此推断伤害、崩溃或性能结果。现在同时发送和恢复初始化标志，未渲染状态保留 false。
2. **6.8.3 已存在的旧问题**：原生 `EffectWithSubEffects.deserialize_and_merge()` 追加子效果，目标模板本身已有子效果，重复恢复造成海贝等子效果 1→2→3→4。现在完整原生状态存在时，先赋新空数组再恢复。使用新数组保护共享模板；properties-only 旧数据仍保留模板内容。

生产代码仅在 `scripts/upgrade_runtime_sync.gd` 增加上述两处处理，以及在 `scripts/protocol.gd` 更新协议。缺少初始化标志的旧状态只验证可读性，不承诺其参数往返幂等；6.5.3 严格握手阻止旧测试包参与新会话。存档格式不变。不会按猜测去重旧档中已经累积的数值或子效果，因为合法 Mod 也可能使用重复效果。

两位 sub-agent 分别只读审核了生产补丁，未发现新增实际代码缺陷。其中一位指出测试需检查完整状态确实被应用，已补上每轮、每端、每席位 `applied == 3`，并获复核确认。

## 冻结候选与新运行证据

测试使用 `review-fix-candidate3/wushuangabao-BrotatoOnlineFriends-6.8.4.zip`，SHA256 `608C5EBE4288FD9A3ECBD6B602DD54FA94A3FD2B17D4C72AE227D0C3CDA75A77`。最终包仅更新说明文档和 manifest 的说明字段，全部 GDScript、翻译、版本与依赖须与已测候选一致，发布校验记录见包旁 `.validation.json`。

零售测试使用独立 runner 中两个真实 Brotato 进程，经 localhost ENet 联机；共装 Friends、FiveItemShop 1.1.3、冻结的 NoobsWantToLive 1.1.2 review。Noobs 输入 SHA256 为 `6D3C1B5FFC8680D1115AFCF09CFB761F43808D50DBBC57E7E918AF7DA8D62578`。测试夹具另外提供命令与状态观测，不打入发布包。

| 测试 | 通过断言 | 证据目录（相对 work） |
| --- | ---: | --- |
| verified-lifecycle-wave1 | 92 | `friends-equipment-effects-20261111/verified-lifecycle-wave1-20261111-133517` |
| verified-lifecycle-wave21 | 92 | `friends-equipment-effects-20261111/verified-lifecycle-wave21-20261111-133555` |
| verified-xiao_tian_cai-wave1 | 75 | `friends-equipment-effects-20261111/verified-xiao_tian_cai-wave1-20261111-133633` |
| verified-xiao_tian_cai-wave21 | 75 | `friends-equipment-effects-20261111/verified-xiao_tian_cai-wave21-20261111-133709` |
| verified-streamer-wave1 | 75 | `friends-equipment-effects-20261111/verified-streamer-wave1-20261111-133747` |
| verified-streamer-wave21 | 75 | `friends-equipment-effects-20261111/verified-streamer-wave21-20261111-133822` |
| mechanical_upgrades | 48 | `friends-equipment-effects-20261111/meca-retail-20261111-133859` |
| movement_rewards_rejoin | 32 | `movement-rewards-evidence/verified684-hiker-20261111-133926` |
| lan_save_create_resume | 62 | `friends-input-diagnosis-20261110/evidence/save-compat-keyboard-fixed-20261111-133528` |

**本轮合计 626 项通过**：效果生命周期 184、装备 300、机械化升级 48、收益重连 32、联机旧档 62。未累加诊断重跑或历史测试。

新增生命周期测试覆盖：已渲染/未渲染描述的 25 次往返，文本、参数数量、载荷大小稳定；零/单/多子效果与共享模板隔离；缺标志和 properties-only 旧数据；海贝原生特殊射击 4 弹丸、临时属性还原和引用移除；标枪特殊射击 100% 暴击（引擎内部值 1.0）；建造者实际材料转换产生两项属性各 +1、追踪统计 +2 并正确注销。两端还验证协议接受 6.5.3、拒绝 6.5.2。

真实 LAN 流程使用诅咒海贝和火焰扳手，在普通/无尽模式每端每席位重复恢复三次、读取描述，连续六轮，再经历两次原生战斗/结算和双方原生出售操作。数值和引用保持一致。重复状态由生产接收入口注入，不能冒充网络重复包；弹丸数与暴击通过原生 WeaponService 计算验证，不声称实体飞行弹丸已逐个目视检查。

装备四组覆盖原版网络主播与晓天菜的普通/无尽模式、购买/合成/出售、地雷、数量缓存、关联属性和跨波。机械化与收益测试保持既有真实 LAN 路径，包括死亡重试、退出标题重入、报告/确认丢失及波末等待重连。

旧档测试先用正式 6.8.1 在两个真实 LAN 进程创建四人合作存档，再关闭进程，换本次修复源码重启主客并继续。主机键盘加手柄、客户端双手柄，输入事件由夹具模拟；创建 4 项、续玩 58 项，检查角色、装备、材料、等级/波次和玩家归属。

## 失败证据与限制

- `independent-review/roundtrip-result.json` 保留两个原始代码问题；`superseded-6.8.4` 保留此前未发布的包、校验记录和旧提交信息。
- `lifecycle-first-20261111-132639` 为新增夹具使用保留字参数造成的解析失败；`lifecycle-normal-20261111-132707` 为测试误把内部暴击率 1.0 期望为 100。均修正测试后新建证据，没有改生产行为来迁就断言。
- 最终各组未发现 `SCRIPT ERROR:`；保留零售环境原有启动/退出警告，不宣称所有日志零警告。
- 没有实体手柄、硬件热插拔、Steam 跨机器或公网高延迟测试；不保证任意第三方 Mod 组合。没有重跑历史 16 路、944 项存档/输入切换矩阵。
- 两位审核未发现新增缺陷并不等于能够证明所有情况都无 Bug。此次只修复已复现缺陷，没有推测性改动嵌套效果标志或历史存档。

复现入口：`tests/Test-EquipmentEffectsLan.ps1 -Suite lifecycle -Wave 1 -OnlinePackage <zip>`，再以 `-Wave 21` 运行无尽模式。其余命令见早期装备验证报告和本仓库测试脚本。

## English summary

This is the final pre-release 6.8.4 build, replacing an earlier packaged and Git-tagged build that was never publicly released. It preserves the native description-initialization flag and replaces subeffect arrays before native deserialization. Two independent reviewers found no further actionable production defects; a missing receiver-application assertion was added and re-reviewed. Protocol 6.5.3 separates this build from earlier test packages; the save format is unchanged.

Fresh regressions passed 626 assertions: 184 lifecycle, 300 equipment, 48 mechanical upgrades, 32 rewards/rejoin and 62 real LAN save create/resume checks. Tests include native projectile/critical calculations, Builder conversion and tracking, repeated rendering/restoration, shared-template isolation and normal/endless wave handoffs. The old-save test creates with 6.8.1 and resumes with the fixed code; it is a network co-op save, not a local-only save. Inputs are simulated. Physical controllers, hardware reconnects, Steam WAN, arbitrary Mod combinations and the full historical input-switch matrix remain unverified in this run. Already accumulated anomalies in old saves are not guessed away.
