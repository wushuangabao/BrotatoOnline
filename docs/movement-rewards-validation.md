# 客户端收益与统计同步验证（6.8.3）

2026-11-10。以下记录 6.8.3 的修复与回归证据。原测试候选沿用 6.8.2 文件名，现正式打包为 6.8.3，网络协议升为 6.5.1，拒绝旧版混入。6.8.2 历史 ZIP、Tag 和存档格式不变。打包不代表已经上传创意工坊或推送 Git。

## 已验证的缺陷与修复

1. 原生步数产生的材料/属性原来未可靠交接，远端重复模拟及主机绝对快照会撤销或重复计算收益。新增按玩家归属执行的原生步数扩展，以及按房间、战斗代次、波次、重试次数隔离的累计账本。
2. 完整 RunData 快照已包含收益时，随后经济账本可能再次加属性；经济账本先到时，旧完整快照又会撤销属性。完整快照携带累计账本水位，接收端只补差额。
3. 主机独立采样的旧最大生命可能反向覆盖客户端实体，造成数据为 11、实体仍为 10。客户端已有当波属性收益时使用本机原生派生生命上限，保留倍率等原生计算。
4. 商店统计白名单丢弃自定义附属键；扁平化数组无法表达空数组与长度变化。通用同步保留数字、数字数组及自定义整数哈希键，按所有者最终值替换，不把双方战斗模拟相加。
5. 退出标题重入时开战代次和账本未正确恢复；原生 Main 初始化又会清空本波统计。通过共享场景握手恢复代次，只恢复身份、房间及同一尝试匹配的未确认账本，并在原生初始化后恢复当前波统计一次。
6. 重试或波末重入后，两个短暂场景保护条件可能阻止正确切入商店。经身份/代次校验的波末交接解除这些临时保护。
7. 主机等待断线玩家最终记录时，原生清场尚未开始，战斗计时器仍会运行。现在暂停战斗、保留网络处理；收到全部最终记录后释放等待暂停，再执行原生结算。离开场景/房间也释放此暂停。

Noobs 源码已删除 `extensions/online_friends_tracking.gd` 及安装入口，保留本地计算与显示。测试包无旧适配，避免由旧补丁掩盖 Online 缺陷。

## 同步频率与边界

- 当波材料、属性会影响实际战斗：所有本地席位合包，未确认且有变化时每秒最多一次；确认后停止重发。
- 纯显示统计：本地观察，波末交接，不因显示数字变化单独发送战斗中报告。
- 最终记录立即发出，未确认则每秒重发；主机波末请求也限为每秒一次。原生结算后的统计变化继续交接。
- 批量报告先校验全部席位、归属、类型、有限数值、代次和版本，再修改状态。重复、旧版本、其他玩家席位和旧尝试报告不能重复获益。
- 最终记录未收齐时保留断线席位并等待，显示中文/英文提示；不会为了超时切商店而静默丢掉未知统计。

## 两种重新加入路径不是同一项测试

| 情况 | 恢复依据 | 未确认收益 |
| --- | --- | --- |
| 同一游戏进程退出标题，再加入主机仍在进行的原房间 | 原身份、原房间及同一战斗尝试 | 内存账本补交，已确认部分不重复加 |
| 主机用 6.8.1 合作存档重新开房，客户端重新加入 | 存档检查点和新的开战代次 | 不沿用旧尝试临时账本，避免把已回滚收益补回 |

入房、身份校验有公共代码，但代次和恢复分支不同。旧档路径必须独立创建真实联机存档并续玩，不能拿同进程断线重连代替。重新加入时的设备选择以当前可用设备为准，不能假定继续使用原设备。

## 零售游戏双进程 ENet 回归

冻结运行包：`work/movement-rewards-candidate18/wushuangabao-BrotatoOnlineFriends-6.8.2.zip`，SHA256 `FEAE4676EB77AEED8848F62A86D9AF17680935B9BCFF6AFD4FD0494AABADB369`。6.8.3 与此包的运行代码差异仅为 `protocol.gd` 的包版本及网络协议常量；全部其他运行脚本逐字节相同。版本更新后另作下述复核。

两端同时加载 Online 候选、FiveItemShop **1.1.3**、Noobs **1.1.0 review**（旧适配已删除）及测试探针。日志确认 FiveItemShop 实际加载；每个目录的 `packages.json` 固定全部 ZIP 哈希。探针使用真实原生场景、移动/伤害/结算回调；报告丢失、乱序和重放为受控注入。

证据根目录：`E:/github/BrotatoMod/work/movement-rewards-evidence`。

| 证据子目录 | 通过 | 覆盖 |
| --- | ---: | --- |
| candidate18-three-mods-hiker-20261110-162543 | 32 | 双方原生材料/最大生命、实体生命上限、连续两波、完整快照与账本两种顺序、确认后停发、自动重连、已确认与真正未确认收益下退出标题重入、真实死亡重试及旧尝试迟到、其他来源材料 +17、报告/确认丢失、断线波末等待及重新入房完成结算、等待时战斗计时器停止 |
| candidate18-three-mods-tracking-20261110-162744 | 34 | 望夜香真实路径陷阱及范围伤害、双方重复模拟不重复累计、原版 5 角色及 1 道具的公共原生爆炸伤害统计回调、自定义数字/数组、同进程标题重入保留当前波、延迟原生结算、真实重试回滚、零伤害波、归零、空数组、70 项数组和负小数 |
| candidate18-three-mods-multi-20261110-163009 | 7 | 主机两位/客户端两位分别获得 48/96/144/192 材料和 1/2/3/4 最大生命；重连、丢失最终报告/确认后仍各自准确 |
| candidate18-three-mods-cat-20261110-163102 | 18 | 暗猫双方原生步数暴击收益、连续两波、过期和重复完整快照、装备新增属性、商店刷新和明确恢复快照 |

合计 **91 条断言通过**，两端无 GDScript 错误。等待提示截图已人工检查，文字正常显示，双方实际生命上限一致。

## 既有源码回归与旧档验证

源码项目：`work/friends-input-diagnosis-20261110`，使用 GodotSteam 3.6 的两个独立进程及真实 ENet。结算/商店/重试单独启用 Online；选择和旧档测试启用原始 FiveItemShop 1.1.3、Noobs 1.1.0 和输入探针（因此不把这组结果当作“无 Noobs 适配”的收益证明）。

- `work/logs/wave-settlement-lan/20261110-162959`：rewards，主客 PASS；原生波末效果、收获、升级和箱子选择、变异/恐龙蛋、延迟与重复回调，最终物品和材料一致。
- `work/logs/wave-settlement-lan/20261110-163134`：endless，主客 PASS；含 Demon 材料转生命、收获衰减与原生重复回调去重。
- `work/logs/retry-reload-regression/20261110-163524-shop`：40 条通过。
- `work/logs/retry-reload-regression/20261110-163538-reload`：10 条通过。
- `work/friends-input-diagnosis-20261110/evidence/selection-single-20261110-163605`：179 条通过。
- `work/friends-input-diagnosis-20261110/evidence/save-compat-matrix-fixed-20261110-163623`：旧档矩阵 **944 条断言通过**（4 次建档各 4 条、16 条续档路径各 58 条）。每份存档均由原始 6.8.1 真正建立 LAN 房间后保存；客户端重新启动并加入修复版主机，比较角色、装备、材料、等级/经验、波次、难度、身份及玩家实际移动控制。四种建档输入与四种续档输入交叉验证，不固定使用原设备。

## 6.8.3 打包复核

- `work/movement-rewards-evidence/release683-hiker-20261110-165805`：新包双进程零售 LAN 的 32 条收益、实体生命、重试、退出标题重入和波末等待断言通过，无 GDScript 错误。
- `work/friends-input-diagnosis-20261110/evidence/save-compat-both_keyboard-fixed-20261110-165821`：原始 6.8.1 建立联机存档，再用 6.8.3 主客双方手柄加键盘续玩，建档 4 条、续玩 58 条通过。
- `work/release-6.8.3-protocol-check`：实际生产协议脚本配受控游戏版本单例，4 项通过：包版本、接受 6.5.1、拒绝 6.5.0、拒绝不同游戏版本。这是协议函数检查，不是旧版 Steam 双机混连测试。
- 新包联机协议为 6.5.1；复用已有 LAN/Steam 入房校验拒绝旧协议。存档格式不变，协议升级不阻止读取旧检查点。
- 最终发布 ZIP、SHA256、逐文件内容清单和验证摘要保存在 `dist/wushuangabao-BrotatoOnlineFriends-6.8.3.zip*`。打包未上传创意工坊，未替换历史 6.8.2 ZIP。

## 失败记录保留

- candidate08/09：重入丢失数组统计、开战代次未恢复；candidate12：原生 ready 清空当前波；随后修复并重测。
- candidate13-array-reset：空数组被还原成旧数组长度；改为保留原生数组形状。
- candidate14-snapshot-order-valid：完整快照与账本重复增加最大生命；修复水位合并。之前缺少 export 参数的测试不作为这项通过证据。
- candidate15-final-tracking：真实重试后快速波末被第二个场景保护拦住；修复后 tracking 重测通过。
- candidate16-wait-world 和重复运行：新增实体生命检查发现 RunData/实体不一致；candidate17 修复并验证。
- candidate17-wait-world：新增等待计时器断言失败；candidate18 暂停战斗后同项通过。
- 源码结算 20261110-162602：受限进程环境停在加载阶段，未进入用例；同代码在正常权限下 20261110-162959 rewards 通过。该超时不计入通过数。
- 初期探针设备编号、浮点步数临界值、Windows 文件替换与启动超时问题的原始目录保留；修正探针后另建结果目录，没有覆盖首次失败。

## 未覆盖、不可据此保证的情况

- 实体双手柄/键盘切换、A 键硬件故障、USB 短断连后的设备编号互换；现有输入测试用模拟事件。
- Steam 跨电脑/公网、真实网络分区、路由器故障。共享场景握手已由 LAN 路径执行，但不等于 Steam 传输实测。
- 客户端进程崩溃、断电或退出整个游戏后，内存中未交接收益不能保证恢复；当前没有新增磁盘日志。
- 任意第三方 Mod 的任意副作用。本次实时收益捕获覆盖原生步数效果；其他收益继续使用原有对应机制。原版伤害用例覆盖公共原生回调，并未逐角色自然触发所有技能。
- 完全离线的玩家无法上传本机最终统计。当前行为是等待重入，不能凭主机推算丢失数字。

## English summary

Version 6.8.3 makes native movement rewards owner-local and transfers acknowledged cumulative deltas. Numeric tracking, including custom keys and arrays, is sent at wave end. Full-state watermarks prevent double application and stale overwrites. Same-process rejoin restores only the exact attempt's pending journal; saved-game resume and retry use their checkpoint. Combat pauses while final owner records are missing, while networking remains active.

The frozen candidate passed 91 assertions in two real retail processes over localhost ENet with FiveItemShop 1.1.3 and an adapter-free Noobs review package. Packet faults and input devices are controlled test injections. Physical controllers, Steam WAN, crash/power-loss durability and arbitrary mod effects are not verified. The existing public 6.8.2 ZIP and tag are unchanged.

The independent source-runtime save matrix created four actual LAN cooperative saves with original 6.8.1 and resumed each using four current input configurations: all 16 paths and 944 assertions passed. Existing selection, shop and retry suites passed another 179, 40 and 10 assertions. Native rewards/endless settlement passed on both peers. These source tests are separate from the adapter-free retail movement/tracking evidence above.

After changing the package version to 6.8.3 and wire protocol to 6.5.1, another 32 retail LAN assertions, 62 original-save creation/resume assertions and 4 production-protocol function checks passed. Other runtime scripts are byte-identical to the fully tested candidate. The final archive includes both Workshop descriptions; building it does not upload a Workshop item.
