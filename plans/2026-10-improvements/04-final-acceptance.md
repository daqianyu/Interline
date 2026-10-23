# 最终验收记录

记录日期：2026-10-22（Asia/Shanghai）。

**整体结论：尚未最终验收。** 本文件已建立，后续随每项实际交付更新。
它不是预填通过的模板；计划中未实施项仍待开发，真机项目仍待外部条件。

## 基线证据（不代表本轮改动已通过）

- 代码：`2532e49e9f99f7a632b11a8ac13a07d53ddf0652`。
- [主分支 CI](https://github.com/daqianyu/Interline/actions/runs/39604573238)：
  76 项单元、9 项 UI 测试通过。
- [设备归档](https://github.com/daqianyu/Interline/actions/runs/39604573255)：
  iPhoneOS arm64 无签名归档成功，不可直接安装。
- 前期模拟器截图已观察到列表颜色、工具栏密度和选字流程问题；真机舒适度/耗电未测。

## 本轮范围与证据

| 项目 | 当前结论 | 证据/剩余条件 |
|---|---|---|
| 计划、需求、开发、测试、验收及执行日志 | 文档检查通过 | 36 个唯一 ID；本地链接存在；需求与测试覆盖全部 ID；diff 检查通过 |
| D01 损坏原始键值保护 | VERIFIED（约定的自动回归） | HardeningPlanTests 前 4 项覆盖 T-D01-01–04；完整 82 单元、9 UI 通过 |
| D02 真实回滚提示 | VERIFIED（约定的自动回归） | HardeningPlanTests 后 2 项覆盖 T-D02-01–03；无效备份用例覆盖 T-D02-04；完整回归通过 |
| Q02 无障碍检查矩阵 | 矩阵子步骤完成，整体未验收 | 14 个逐页 AX 用例、6 组环境；源码缺口登记，真人辅助导航尚未测试 |
| Q04 失败分类与证据 | VERIFIED | 12 项工具测试及 workflow 集成通过；下载产物确认 summary.json 为 success，SHA/运行链接正确；原失败记录保留 |
| D03 草稿后台保存 | VERIFIED（功能自动回归） | 8 项 DraftPersistenceTests、2 项新增 UI 用例通过；全量 90 单元、11 UI、12 工具测试通过；恢复/失败截图已检查 |
| D04 备份安全与内存 | VERIFIED（约定的自动回归、模拟器证据及固定样本测量） | 62954b9：111 单元、12 UI、12 工具、3 项测量通过；文件窗口/笔记重启/深色大字与横屏截图已检查 |
| D05 | VERIFIED（约定的自动回归） | d7148c6：121 单元、13 UI、12 工具通过；读取/取消和草稿恢复提交重启截图已检查 |
| D06 | VERIFIED（约定的故障回归与局部视觉验收） | 16a7b55：129 单元、15 UI、12 工具全通过；浅色键盘、实际深色最大字号及横屏截图已检查 |
| Q01、Q03 | IN_PROGRESS，整体未验收 | Q01 矩阵/固定样本、Q03 备份复测/待测范围已准备；实际提供器、启动/阅读性能与真机项目未完成 |
| P01–P04、U01–U08、A01–A03 | 未验收 | 代码与界面改进、视觉/功能回归 |
| F01–F09、U09、P05 | 未验收 | 扩展设计细化、开发、兼容和发行验证 |

## 每项证据必须包含

本轮 [PR #6](https://github.com/daqianyu/Interline/pull/6)：

- `e1f504aa13b52610559dae0786028c2ae92e686a` 的
  [CI 39638159549](https://github.com/daqianyu/Interline/actions/runs/39638159549)：
  82 单元通过；9 UI 中笔记重启用例未打开目录。原始点击坐标落在动画结束后的按钮下方。
- `17a183a156547ffed0dbc7263d618b74f44ff8a7` 的
  [CI 39645321845](https://github.com/daqianyu/Interline/actions/runs/39645321845)：
  82 单元通过；同一 UI 用例在稳定性检查超时，一次查询约 4.3 秒，未发生目录点击。
- 已验证代码 `bc882682fb92401643315f9c0e35ed8bcea7b50a` 的
  [CI 39648634021](https://github.com/daqianyu/Interline/actions/runs/39648634021)：
  **82 项单元、9 项 UI 全部通过，构建成功**。调整初始采样和同步预算，保留全部业务断言，
  `testNoteCanBeWrittenAndPersistedThroughRelaunch` 复验通过；D01/D02 标为 VERIFIED。
  此后提交仅新增计划/验收记录、Q02 矩阵和 Q04 CI 工具，不改应用或 iOS 测试源代码；
  Q04 的 workflow 集成结果单独补录，不能使用本次运行冒充已执行新增 CI 步骤。

D01 的保全文件可以手动导出，不代表原损坏内容已自动修复，也不会自动纳入现有
完整书库 JSON 备份。D04/F07 后续负责进一步完善备份范围与格式。

合并后主分支 `33dd9f9ed84f85e96521dedb2df4551562d0f63c`：
[CI 39708761093](https://github.com/daqianyu/Interline/actions/runs/39708761093) 再次通过
82 单元、9 UI 和 12 项分类器测试；摘要生成/上传成功，下载产物 12395989121 核实
summary.json 的分类、SHA 与运行链接正确。Q04 完成集成验收。
[设备归档 39708761112](https://github.com/daqianyu/Interline/actions/runs/39708761112)
成功；仍为无签名产物，不代表可直接安装或真机已测试。上述结果不覆盖后续 D03 代码。

### D03 交付证据

- [PR #7](https://github.com/daqianyu/Interline/pull/7)，应用/测试代码
  `0462e03ef0ff49305bc4b0ad11c09654b1653c21`。
- [CI 39710154884](https://github.com/daqianyu/Interline/actions/runs/39710154884)，
  job 119600367064：Xcode 27.0 构建成功，**90 单元、11 UI、12 工具测试全部通过**。
  PR 测试使用合并引用 `091cb018e9d8e1a90e9b119acb86bc824f97102e`；摘要中的 SHA
  为该引用，不与 PR 源分支 SHA 混淆。
- 新增 8 项 DraftPersistenceTests 覆盖合并、后台线程、并发版本、写入互斥、
  失败重试、提交后清理、备份刷新、损坏字节保护及独立草稿；真实临时文件验证通过。
- 新增 UI `testCancelledDraftSurvivesRelaunchAndCanBeResumed` 与
  `testFailedDraftSaveShowsRetryAndCancelKeepsInput` 均通过；原有 9 UI 用例保留并通过。
- 下载产物 12397736608，summary.json 为 success；检查 iPhone 18 Pro 模拟器截图
  `ResumedDraft`（E36FE58E…png）：原摘录和 Retained draft 仍在，状态已保存；
  `DraftSaveFailure`（30DF571D…png）：键盘出现时错误/重试仍可见，原输入未丢失。
- 视觉范围仅上述浅色竖屏；顶部导航留白偏大、失败态摘录分组标题贴近状态区，
  作为 U07 布局复验记录，不声称全尺寸/深色/最大字号已验收。
- 后续交付提交只更新计划文档，应用和 iOS 测试代码与上述通过版本一致。
  系统立即强杀、真机后台时限、VoiceOver 仍未验证；D05 的目标章节同步读取仍待优化。
  下一项 D04；整个发行计划仍未最终验收。

D03 合并后的主分支 `6d8def4765098235b5fe30a7cee4adfaedf762c4`：
[CI 39712034006](https://github.com/daqianyu/Interline/actions/runs/39712034006) 和
[无签名设备归档 39712034031](https://github.com/daqianyu/Interline/actions/runs/39712034031)
均成功；不覆盖后续 D04 修改。

### D04 兼容安全子阶段证据

- [PR #8](https://github.com/daqianyu/Interline/pull/8)，应用/测试代码
  `78ca50cba5ae26e006d228d7b1647ad22bcb26be`。
- [CI 39738030878](https://github.com/daqianyu/Interline/actions/runs/39738030878)，
  job 119688255212：Xcode 27.0 构建成功，**98 单元、11 UI、12 工具测试全部通过**。
  8 项 BackupBudgetTests 全部通过，原完整恢复/幂等/回滚/草稿用例保持通过；
  验证产物 12408252746 已上传。
- 此后的交付提交仅更新计划，应用/iOS 测试源码与上述版本一致；本阶段无界面改动。
- 仍保留完整输出 Data；没有峰值测量结论，未实现 v2 文件式导出/恢复，未关闭 D04。
  第二阶段文件结构、临时生命周期和测试要求见 `07-backup-v2-format.md`。

需求 ID、实际范围、受影响文件、测试名称、源代码提交/PR、CI 运行链接、
测试数量与结果、截图（如适用）、未验证条件和下一步。后续文档提交可引用此前
同一代码树的测试，但必须明确是纯文档修改；不可把旧代码证据用于新增代码。

## 最终发行门槛

- [ ] 当前发行范围的需求已逐项完成，任何延期项有明确范围说明。
- [ ] 存储故障保护、回滚、迁移与备份往返通过。
- [ ] 完整自动回归、相关视觉检查及无障碍用例通过。
- [ ] 真机导入、升级保留数据、VoiceOver、长读与能耗完成。
- [ ] 发行图标、版本、反馈、说明和签名分发准备完成。
- [ ] 构建与验收证据对应同一交付版本，剩余缺陷已明确记录。

## 已知外部阻塞

用户目前没有 Apple 开发者签名条件。暂不能完成签名安装和相应真机验收。
该阻塞不阻止其他计划开发；不要求用户重复确认已经授权的 GitHub 操作。

### D04 v2 修复前记录（历史，最终状态见下文）

- PR #9 远端 head：f91fa2c0338ccc4309c7e9b91e42e01617eb7df7，仍为草稿，未合并。
- 功能运行 [39748495920](https://github.com/daqianyu/Interline/actions/runs/39748495920)：
  111 单元和 12 工具通过，12 UI 中 2 项失败；产物 12414260231 已下载检查。
- 固定样本三变体内存运行 39744592118、39748495866 均成功；原始数值与限制见
  `08-d04-memory-results.md`。不能将模拟器约 31 MB 样本推断为所有书库或真机表现。
- 实际检查导出/导入窗口截图，文件选择和取消返回数据页已通过；最大字号数据页
  已打开，但备份格式说明 cell 尚未创建，原测试在滚动前要求存在而失败。
- 笔记录屏显示保存后编辑器退下但选字页仍在；改为等子 sheet 的 onDismiss 后再关闭父层，
  UI 仍要求两层消失、重启后笔记数量和内容正确。大字测试先确认数据页，再滚动 Form。
- 上述修复仅完成本地编辑及 12 项工具测试/diff 检查。当前 Linux 环境没有 Xcode，
  不能报告新版本已编译或 iOS 测试通过。需提交 PR #9 后执行全量 CI、检查新截图。
- 自动审批两次拒绝公开仓库上传；第二次已核实仓库属于当前 GitHub 账户且有写权限，
  审批仍要求用户明确授权本次公开上传。未通过 shell、其他 API 或其他分支绕过。
- D04 尚未验收。用户授权后提交修复与计划记录，完整验证通过再合并，然后执行 D05。

### D04 v2 最终交付证据

- [PR #9](https://github.com/daqianyu/Interline/pull/9)，应用/测试源码
  `62954b9fd7ad45caa1c8de3d9602ee3c283c066e`；后续交付仅补文档，不改该源码。
- [功能回归 39807664224](https://github.com/daqianyu/Interline/actions/runs/39807664224)，
  job 119925110685：Xcode 27 完整编译成功，**111 单元、12 UI、12 工具测试全部通过**。
  PR 合并测试引用 `57cbd71dbc13594f2c999788aa9604b8ffd02752`；产物 12439541772 已下载，
  summary.json 为 success，运行链接与引用 SHA 正确。
- 新增 13 个 BackupContainerTests 覆盖 v2 往返、v1 兼容、格式/hash/章节/摘录拒绝、
  暂存生命周期、冲突与回滚、元数据预算和类型声明；此前 98 单元均保留。
- 实际检查 `BackupFileExportPicker` / `BackupFileImportPicker` 的系统文件窗口及取消返回；
  同一用例继续检查实际深色最大字号和横屏，说明可通过滚动读取。观察深色截图
  8247CA73…png / 26DA8839…png，确认不是仅以 Dark 命名的浅色画面。
- SavedNotes（F87F0F54…png）：两层编辑/选字弹窗退出后，重启显示笔记 (1)，
  A reading note 内容仍在。原并发关闭问题已通过保留的持久化断言复验。
- [内存测量 39807664213](https://github.com/daqianyu/Interline/actions/runs/39807664213)，
  job 119925110966，产物 12438134390：3 个变体各 3 次成功。最终峰值均值 kB：
  旧全量 95088.725、逐书 v1 38787.584、文件 v2 32397.824；约 31 MB 固定样本下
  v2 比旧全量低约 65.9%。所有原值、耗时和方法限制见 08-d04-memory-results.md。
- 不声称恒定内存、近 256 MiB 上限、恢复峰值、真机速度/耗电或完整无障碍已通过。
  v1 导入仍有全量解码缓冲；新格式单本与元数据仍有临时对象，原始损坏资料单独导出。
- D04 按约定范围 VERIFIED；整个发行计划仍未最终验收。下一项 D05；
  真机文件提供器/签名安装等外部条件继续由 Q01/P05 记录。

### D05 本地准备记录（未公开提交、未验收）

- 异步读取目标章节并在后台验证 UTF-16 范围、组合字符与 quote；复用已载章节。
- 主线程提交前核对目标书、维护/导入版本、草稿版本及原标注身份，避免取消、删除、
  换库、丢弃草稿或新编辑后继续写入旧结果；格式和 D03 保存屏障保持。
- 编辑器持有可取消任务，读取期间显示状态；失败保留输入。新增 DraftChapterTests 10 项，
  新增读取取消 UI，并把恢复草稿 UI 延伸至提交后重启内容校验。
- 本地 12 项工具及 diff 检查通过；没有 Xcode 编译或 iOS 运行结果，预期 121/13/12
  不可写成已通过。D06 已补实施设计，尚无实现或验收。
- 公开上传 D05 源码/测试/计划的自动审批被拒绝，理由为此前公开授权只覆盖 D04。
  未尝试替代上传通道；远端 D05 空分支仍指向旧 D04，未创建 PR；需要明确公开授权。
- D04 已合并为 1c53c008e6d2a077f546186b46af3b58f5a66bf7（PR #9），后续提交以此为基线。

2026-10-23：用户已明确授权 D05 及后续计划持续公开提交与验证后合并；上述 D05 公开授权阻塞已解除，iOS 编译/测试仍待本轮验证。

### D05 最终交付证据

- [PR #10](https://github.com/daqianyu/Interline/pull/10)，源码 d7148c6f67765a2372e89895aa1e622e68e42672。
- [功能运行 39814308841](https://github.com/daqianyu/Interline/actions/runs/39814308841)，job 119948642517：
  编译成功，121 单元、13 UI、12 工具全部通过。独立备份测量 39814308912 同样成功。
- 下载产物 12442236746，摘要 success，测试合并引用 92038be5cf0776d410aa6d4d429e5ddd1fcb4039。
- 实际查看 DraftChapterLoading（09F0BEA6…png）显示读取原文及可用取消入口；
  DraftChapterCancelled（F29483DB…png）保留原输入、已保存状态且保存按钮恢复；
  UI 另断言取消后重启笔记数为 0。CommittedResumedDraft（0410DFCB…png）显示笔记 (1)
  和 Retained draft 内容，证明管理页恢复后提交、重启持久化正确。
- 10 个新单测包括后台读取、切书、取消、移出/永久删除、完成维护/导入后的旧结果、
  草稿更新/丢弃、无效章节/摘录/组合字符、原标注身份、缓存复用和真实写入失败重试。
- 仍整书解码、保留单本暂存；已经开始的同步解码不被强行终止，但取消后不提交。
  导航留白/正文颜色仍归 U01/U07，不宣称真机性能或全无障碍已通过。
- D05 PR #10 已以 merge 合并至 a1f52f99f79641fe814df17a1069c8dc72ae5817；
  为不打断 D06 验证，本记录随 D06 的纯文档收尾一起提交。下一项 D06。

### D06 最大字号失败与修复记录（非最终通过）

- d54cf6e 的 [运行 39819343651](https://github.com/daqianyu/Interline/actions/runs/39819343651)，
  job 119967277441：129 单元和 12 工具通过，15 UI 中 14 通过、1 失败。
  testDetailRemovalFailureKeepsPageAndBook 在竖屏最大字号 retryPageOperation.isHittable 失败；
  草稿关闭/提交/重启及详情元数据故障用例均通过，但不代表整项验收通过。
- 全部 UI 执行 575.6 秒后，xcodebuild 收尾未结束，最终触及 20 分钟步骤上限；
  产物 12445745669 摘要正确分类 test_failure，合并测试引用 b00bc6875b8ad956024f9d030fd8d7f841b22c91。
- 已实际解出并查看 DetailRemovalFailureDarkLarge（278EF5B3…png）：错误区与 Form 行重叠，
  重试被遮挡；不是将可点击断言解释成环境误报。
- 16a7b553c4ad2654c447576c5fda53f2fa4aa38c 将详情错误区放入独立布局空间，完整原因可滚动，
  横屏限制说明区高度、保留两个操作并使用不透明底色；按钮至少 44×44 pt。
  原断言保留，增加实际点击重试及横屏关闭；[复验 39823324689](https://github.com/daqianyu/Interline/actions/runs/39823324689) 进行中。
- d54cf6e 的独立备份复测 39819343542 成功；原值和工具链记录在 10-performance-baseline.md。
  后续布局源码仍需自己的编译/回归证据，不能用该性能通过掩盖 UI 失败。

### D06 最终交付证据

- [PR #11](https://github.com/daqianyu/Interline/pull/11)，应用/iOS 测试源码
  `16a7b553c4ad2654c447576c5fda53f2fa4aa38c`；基线为 D05 合并后的 main。
- [功能回归 39823324689](https://github.com/daqianyu/Interline/actions/runs/39823324689)，
  job 119979983328：Xcode 27.0（27A266a）编译成功，**129 单元、15 UI、12 工具全通过**。
  合并测试引用 `55cf6c8cad4965077df944f2b6ad3ab30f36cefc`；下载产物 12445689200，
  summary.json 为 success，引用 SHA 和运行链接已核对。
- 新增 PageOperationTests 8 项覆盖真实存储障碍、原字节保留、重试后持久化、待清理删除、
  写入屏障、取消正文读取与文件取消 domain/code；原 121 单元保留并通过。
- 新增详情元数据故障和移出故障两个 UI；保留原 13 项。实际点击重试仍失败时页面保持；
  关闭错误后仍留在详情，回书架原书仍在。最大字号竖屏/横屏的两个按钮均可点击。
- 实际查看 iPhone 18 Pro 模拟器截图：DetailMetadataFailure（0A9929A4…png）在键盘上方
  显示错误与两项操作；输入保留由 UI 值断言验证。DetailRemovalFailureDarkLarge
  （6B2928A2…png）、Landscape（73CDAE65…png）确为深色最大字号，错误与列表不再交叠，
  重试和关闭清楚可见；完整原因可滚动，不缩小系统最大字号。
- 修改涵盖 LibraryActionResult、AppState 的书库/维护/笔记/书签操作及详情、数据管理、
  笔记/书签/标注、导入页；共用 OperationErrorBanner，避免将无关全局提示配到当前操作。
  删除/保存失败不先发布成功；永久删除后的待清理可用同一 ID 重试；文件取消不误报故障。
- 同源码 [独立备份测量 39823324867](https://github.com/daqianyu/Interline/actions/runs/39823324867)，
  job 119979984907、产物 12445209666：Xcode 27.0、三变体各三次通过；原值见
  10-performance-baseline.md，不外推真机或阅读性能。
- 后续收尾仅补计划、验收及 Q01 样本生成器；应用和 iOS 测试源码与 16a7b55 保持一致。
  生成器的字节/编码/尺寸/拒绝覆盖检查另列，不冒充实际系统文件提供器验收。
- D06 按约定范围 VERIFIED；整个发行计划未最终验收。下一项 Q01 的实际选择/导入/恢复，
  iCloud、签名真机、VoiceOver、完整 44 pt 触控审核及长读/能耗仍未通过。

### Q01 本地 TXT 专项启动（2026-10-23）

新增独立系统提供器 UI 测试（5 项）、DEBUG 隔离样本入口、专用 workflow 和源文件哈希检查。
覆盖四种编码、编辑标题、重启阅读、重复文件、取消、空文件与超限拒绝。
本地既有 12 项工具测试通过；iOS 编译、专项及全量回归尚待 CI，不据此关闭 Q01。
下一步取得实际运行与截图证据，随后继续备份选择恢复和剩余提供器矩阵。
