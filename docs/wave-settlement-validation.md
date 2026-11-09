# Friends 6.8.1 波次结算修复验证

日期：2026-11-09。基础提交：`b4139b76d153258d4b199f2e48e0ab5bae91d5d9`（Friends 6.8.0），分支 `feat/client-local-coop`。下列结算修复随 6.8.1 发布，Mod ID 与网络协议保持不变。

## 环境与方法

- GodotSteam 3.6：`D:/GodotSteam/godotsteam.36.editor.windows.64.exe`。
- 恢复项目：`E:/github/BrotatoMod/RecoveredProject`，仅启用 `wushuangabao-BrotatoOnlineFriends`。
- 每个用例启动独立房主、客户端两个实际 Godot 进程，使用 localhost ENet，隔离 APPDATA，禁止保存进度。测试以 `--no-window` 运行，不是人工点击或屏幕截图验证。
- 初始人物、库存、波数由夹具设置；开打使用生产状态交接，波次通过原版计时器和清场结束。客户端结算被故意延迟，房主先进入真实商店并通过 ENet 广播完整商店状态。
- 客户端必须保留原战场直到解除延迟，之后完成结算并进入商店。比较两端状态；再次调用三个原版计时器入口，并向生产接收入口重复交付三次商店状态，检查不多发奖励、不重复累计本地进度。
- 每次运行目录包含源文件 SHA256、stdout/stderr、最终状态 JSON；新增 runner 还写入 `scenario.txt`。

## 修复前的真实失败

证据：`E:/github/BrotatoMod/logs/wave-settlement-lan/20261109-154117`。

客户端 EndWaveTimer 被暂停后，房主进入商店；客户端接到场景状态便直接切商店，原战场提前释放。结果：

1. 客户端没有完成原版 `RunData.on_wave_end()` 的本地步数累计和每波计数重置。
2. 房主未拾取材料账本为 13，客户端 `bonus_gold`、`total_bonus_gold` 都仍为 0。
3. 个人材料、XP、护甲、收获最终看起来正常，因为房主状态覆盖了客户端；不能以商店数值一致推断本机结算已运行。

该次 `end_of_the_wave` 信号已经执行一次；这份证据证明的是后续本地回调遗漏，不证明修复前所有回调都会遗漏，也不证明已经发生重复发奖。重复消息检查当时失败，是因为缺失的步数仍未恢复。

## 实现

- `main_safe_pool_exit.gd` 提供商店转换就绪检查：原版波末效果已启动、`RunData.on_wave_end()` 已完成、收获计时器已结束，才允许消费房主商店场景。若本机波末入口还未执行，则启动原版路径，仍保留既有物理帧清场屏障。
- 三个结算计时器入口按当前 Main 实例去重；失败重试的 UI 路径保留，重载战场后标志重新初始化。
- `wave_mutations.gd` 在原版 `RunData.on_wave_end()` 返回后标记本机结算完成。变异与恐龙蛋继续由房主计算，客户端只接收其结果。
- `battle_replica_manager.gd` 的成功清场分支补走原版波末效果，避免直接清场绕过效果和信号。
- `menu_sync_manager.gd` 在应用房主 RunData 之前等待上述条件，同时同步 `bonus_gold` 和 `total_bonus_gold`，采用赋值而非重复触发材料转换。

## 运行结果

所有路径以下述目录为前缀：`E:/github/BrotatoMod/logs/`。

| 用例 | 证据目录 | 结果 |
| --- | --- | --- |
| 延迟 EndWaveTimer，房主先切商店 | `wave-settlement-lan/20261109-160421` | 双端 PASS |
| 延迟 HarvestingTimer | `wave-settlement-lan/20261109-160629` | 双端 PASS |
| 延迟客户端整个 WaveTimer 回调入口 | `wave-settlement-lan/20261109-160004` | 双端 PASS |
| 待领取宝箱及升级，同时延迟收获结算 | `wave-settlement-lan/20261109-160345` | 双端 PASS |
| 无尽波次、材料转换与收获衰减 | `wave-settlement-lan/20261109-160552` | 双端 PASS |
| 成功清场绕过计时器入口，补走原版波末效果 | `wave-settlement-lan/20261109-160843` | 双端 PASS，日志确认 `kind=room_cleanup` |
| 客户端负责商店结果及开打前完整状态交接 | `trusted-shop-lan/20261109-160458` | 双端 PASS |
| 失败重试场景重载与重复提交 | `retry-reload-regression/20261109-160517-reload` | 10 项 PASS |
| 迟到客户端自动进场及确认重发 | `retry-reload-regression/20261109-155446-recovery` | 18 项 PASS |
| 6.8.1 发布元数据下重跑普通延迟结算 | `wave-settlement-lan/20261109-161738` | 双端 PASS |
| 6.8.1 发布元数据下重跑无尽结算 | `wave-settlement-lan/20261109-161815` | 双端 PASS |

主要断言：

- 每端 `end_of_the_wave` 信号一次；本地 ProgressData 步数增加 37；每波步数归零、`wave_in_progress` 清除。
- 普通模式：1000 材料增加至 1020，收获获得 20 XP，波末护甲增加 7，收获从 20 增长至 21。
- 奖励模式：初始等级 1 / XP 24，结算为等级 2 / XP 19，客户端通过实际按钮信号领取一份蛋糕、选择一次 +15 范围升级，两端一致。
- 无尽模式：原版恶魔效果将 494 材料转换为 38 最大生命，再获得 20 收获材料，最终材料 526；收获从 20 衰减至 16。
- 恐龙蛋推进一阶段；一次待变异作用于一个合法目标；全局材料账本两端均为 13。
- 重复调用三个结算入口及重复交付商店消息不再改变已测状态，也不重复计步或发出波末信号。

## 证据边界及测试调整

测试使用无敌人战场、缩短波次、预设未拾取材料账本和宝箱待处理队列。因此验证了结算及同步，不包含真实地面拾取竞争、Steam 跨机器网络或全部角色/道具组合。挑战检查代码随原版波末入口执行，但未逐项验证所有成就，亦未验证 Steam 成就服务写入。失败重试和迟到进场附加套件使用单进程受控消息交付；结算与商店套件使用双进程真实 ENet。

开发夹具时保留了失败日志：变异可合法选中人物，并可能额外产生肿瘤，不能仅以镜片是否变异判断同步；反序列化后的升级资源可能没有原路径，按钮驱动须按升级 ID 识别。奖励用例延迟收获计时器，允许原版 EndWaveTimer 打开奖励 UI，避免测试自身造成“等房主进商店、房主又等客户端选奖励”的循环等待。

`20261109-155446-reload` 首次并行回归的“重试仍在旧 12 秒窗口内”前置断言失败，其余重载行为通过。保持生产代码不变，改为顺序执行后，`20261109-160517-reload` 的全部 10 项通过；首次失败日志保留。

隔离配置首次启动产生的 CrashReporter/settings 提示、恢复资源 Attach 警告及 Godot 退出时资源回收告警仍在 stderr 中；通过标准是进程成功退出、所有业务断言通过且无 SCRIPT ERROR，不声称日志零告警。

## 部署一致性

本次四个生产脚本已经复制至本地 Godot 项目；最终 SHA256 与测试记录及项目文件一致：

| 文件 | SHA256 |
| --- | --- |
| `extensions/main_safe_pool_exit.gd` | `4BC10E3DDEB31A701337D39255DB83945322C043CA42FE94F75CF5ED03CCBD8B` |
| `extensions/wave_mutations.gd` | `781B31D11EA0FB30EA1F2FB6A38E8BE8FA6549EA1941619FA766D7C1F0F9A2B6` |
| `scripts/battle_replica_manager.gd` | `7EF7428777BEF5B04F512BBE3665A60352C0DCA8879E0224A609A339E06EF658` |
| `scripts/menu_sync_manager.gd` | `FEACC216049E60A7396E23BD34DEB64B65660E7ED080115B72A6A35B90BBA3EE` |

测试夹具在补充场景时有增量修改，具体版本以每次 `source.txt` 的哈希为准；上述生产补丁在列出的通过用例之间未改变。运行方法见 `tests/README.md`。
