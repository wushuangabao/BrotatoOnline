# 6.8.4 装备效果同步验证

日期：2026-11-11。基线为已发布的 `6.8.3` / Git `1d3020a22df8ea5ba605f7f501b9ec238687f644`。本次修改 Friends 通用同步代码，没有修改 Noobs 角色实现。

## 已验证缺陷与修复

1. 普通波次的武器替换增量只更新装备列表，未带上操作后的效果、套装状态。主机出售扳手后，本机结构/护甲/工程学为 `0/0/25`，客户端仍为 `1/3/30`，尽管武器数已是 0。武器替换增量现在带上操作后的完整状态；无尽模式仍可省略未变化的持有道具。已有完整状态时移除多余的库存增量，避免再次换成无关联的新武器对象。
2. 原生反序列化先建立效果引用，Friends 的效果覆盖随后创建私有 Effect 副本，导致 `StructureEffect.unapply()` 按引用删除时找不到目标。覆盖完成后，使用原生序列化匹配规则，将资源型效果重新绑定到对应装备；道具来源（如地雷）也纳入匹配。保留重复效果的数量，不重放 apply/unapply。
3. LinkedStats 位于 PlayerRunData 之外，替换玩家状态不会执行原生装备变更钩子。第一版修复曾出现结构数量为 0、护甲仍为 3。现在根据最终状态重算对应席位的 LinkedStats，并刷新属性缓存，不清除临时战斗增益。
4. 道具数量、不同道具与重复装备缓存也跨 PlayerRunData 存活。扩展测试实际观察到客户端库存中有地雷、数量查询却为 0。现在先清理该席位的这三类缓存，再计算关联属性。
5. 火焰炮塔的嵌套燃烧数据超过原生效果序列化的四层预算，`serialized_effect` 被整段省略，接收端退回本地模板。原始失败中，网络状态含 `custom_args[0]`、装备效果却没有，导致效果内容哈希不同、无法重新绑定。原生序列化字段现在使用 16 层预算；通用导出属性仍维持四层预算。增加包含自定义描述参数和修改过的燃烧伤害的独立往返检查。

生产修改：`scripts/menu_sync_manager.gd`、`scripts/upgrade_runtime_sync.gd`。包版本为 6.8.4，网络协议升级到 6.5.2，所有玩家须一起更新。存档格式不变。

## 最终运行时回归

装备和机械化测试使用独立零售运行器：`E:/github/BrotatoMod/work/friends-equipment-effects-20261111/runner`。两个真实 Brotato 进程通过 localhost ENet 联机，使用隔离用户数据。没有使用或修改其他角色测试的零售运行器。仅为避免同一 Steam 账号创建竞争大厅，测试夹具禁用 Steam 建房；生产 LAN、场景同步、原生商店及战斗逻辑正常执行。

测试包为 Friends 6.8.4 release-candidate1、FiveItemShop 1.1.3、最新 NoobsWantToLive 1.1.2 review。Noobs 输入已冻结到 `work/friends-equipment-effects-20261111/inputs/final-character-review.zip`，SHA256：`6D3C1B5FFC8680D1115AFCF09CFB761F43808D50DBBC57E7E918AF7DA8D62578`。

| 场景 | 通过数 | 证据目录（相对 work/friends-equipment-effects-20261111） |
| --- | ---: | --- |
| 晓天菜，普通波次 | 75 | final-xiao_tian_cai-wave1-20261111-125615 |
| 晓天菜，无尽波次 21 起 | 75 | final-xiao_tian_cai-wave21-20261111-125651 |
| 原版网络主播，普通波次 | 75 | final-streamer-wave1-20261111-125729 |
| 原版网络主播，无尽波次 21 起 | 75 | final-streamer-wave21-20261111-125803 |
| 机械化升级，原有断言 | 48 | meca-retail-20261111-130223 |
| 徒步旅行者收益、死亡重试与等待重连 | 32 | ../movement-rewards-evidence/equipment684-hiker-20261111-130314 |

装备共 300 项断言。每组均覆盖主客双方出售、购买两把同名扳手、合成二级扳手、出售合成结果、购买地雷道具、重复道具与武器数量、关联护甲/工程学、刷新、再次进场和结算。每轮完整状态重复应用三次，两端全部席位都参与；检查效果引用、材料、生命上限和另一席位不被污染。购买验证材料只扣一次。普通和无尽同步分支均直接断言已启用。

商品内容由夹具在两端同步设置，再触发原生购买/合成/回收 UI 信号。重复恢复通过生产 `_apply_one_serialized_player_run_data` 入口注入同一份线格式状态，不冒充网络层重复包测试。两波均使用原生进场、战斗玩家属性和结算，缩短波长、关闭敌人并开启无敌，以隔离装备同步。

机械化回归复用原 `meca_upgrade_lan.gd` 的全部断言，只将固定端口改为本轮环境端口，并等待零售版启动到标题后再接管。覆盖无尽商店、80 件道具、六次机械化升级、双击不重复扣款、完整状态修复及弹窗/焦点保持。收益回归包含实际死亡重试、同进程退出标题重入、报告/确认丢失及波末等待重连，32 项通过。

## 6.8.1 联机旧档补测

使用此前验证过的 `work/NoobsWantToLive-source-runner/Brotato-source.exe` 和独立源项目，先以正式 6.8.1 启动两个真实 LAN 进程创建四人合作存档，再关闭两个进程、切换到当前 6.8.4 源码、重新启动主客并继续存档。主机键盘＋手柄、客户端双手柄；设备输入由夹具模拟，未使用实体设备。创建阶段 4 项、续玩阶段 58 项，共 62 项通过，角色、装备、材料、等级/波次和席位归属恢复正确。证据：`work/friends-input-diagnosis-20261110/evidence/save-compat-keyboard-fixed-20261111-130532/results.json`。

本次新执行断言合计 **442**（装备 300 + 机械化 48 + 收益 32 + 联机旧档 62），不包含前期诊断性重复运行或历史版本的矩阵结果。

## 保留的失败与诊断

没有覆盖原始证据：

- `baseline-20261111-122909`：正式 6.8.3 主机出售后远端残留结构与加成。
- `candidate1-20261111-123122`：引用初修后暴露 LinkedStats 缓存残留；candidate2 的原始九项出售/跨波检查通过。
- `expanded-xiao-20261111-124129`：数量缓存遗漏，客户端地雷数量查询为 0。
- `expanded-xiao-v4-20261111-124318`：测试夹具只在购买方设置固定商品，远端不存在该商品，无法重放主机购买；修正夹具为两端先设置同一商品，未修改生产购买逻辑来掩盖问题。
- `streamer-endless-20261111-124649`、`streamer-endless-diagnostic2-*`、`streamer-endless-diagnostic3-*`：保留火焰炮塔孤立引用、收到的 owner_state 包及逐字段差异。candidate5 被后续修复取代。
- `meca-retail-20261111-125857`、`meca-retail-20261111-130124`：旧独立场景脚本在零售版启动完成前执行，随后被标题场景覆盖；在测试启动层加入标题状态门槛后通过，没有为此改变生产代码。
- GodotSteam 编辑器的额外旧档测试停在 ModLoader 启动阶段；保留失败结果，换回此前使用的游戏运行器验证。

每个装备证据目录包含 `verification.json`、两端状态与日志、`packages.json`；最终四组还包含 `sources.json`。生产候选包 SHA256 为 `DDFB3615A691A74F9D771B3239FA0A7AB09AAF527E1DBCB355067FFAFAA2AC59`。正式包增加本报告等文档，发布时另行校验全部运行时代码与此候选逐字节一致，包哈希以正式 `.sha256` 为准。

## 范围与剩余限制

- 以上是两进程真实 LAN 的自动化测试，UI 输入由信号驱动；没有实体手柄、硬件热插拔或 Steam 跨机器测试。
- 不声称全部第三方 Mod、所有装备与高延迟网络组合均已覆盖。物理输入交换、角色视觉挂点等不属于本次生产修改。
- 本次没有重跑全部历史 944 条旧档设备组合矩阵；不能把 6.8.3 的历史结果计入 6.8.4 新断言数。
- 原版 6.8.3 包、提交和标签保留。临时 review 包不能混装在正式版本旁，主客双方都应使用同一版本。

## Reproduction / English summary

`tests/Test-EquipmentEffectsLan.ps1 -OnlinePackage <zip> -Runner <isolated retail runner> -Character xiao_tian_cai -Wave 1`; repeat with `streamer` and `-Wave 21`. The runner requires the companion Noobs review and FiveItemShop packages under its Workshop layout. `tests/Test-MecaUpgradeRetail.ps1` mounts the existing mechanical-upgrade assertions in that runner. The retail bootstrap waits for the native title transition; production networking is not replaced.

The fixes transfer complete weapon effect state, rebind resource-valued effects after overlays, invalidate per-player inventory caches, rebuild linked stats and preserve deeply nested native effect serialization. The four equipment scenarios passed 300 assertions; mechanical upgrades passed 48 and movement/rejoin rewards passed 32. Native inventory mutations are driven through UI signals; repeated full-state application is controlled injection. An additional real LAN save test created a four-player co-op save with 6.8.1 and resumed it with 6.8.4, passing 62 assertions. The total fresh regression count is 442; historical input matrices are not counted. Physical controllers, Steam WAN and arbitrary Mod combinations remain outside this evidence.
