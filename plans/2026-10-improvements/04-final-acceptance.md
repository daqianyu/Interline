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
| D04 备份安全与内存 | IN_PROGRESS | v1 预检/逐书编码已实现，8 项新增测试待 CI；文件式格式与峰值测量尚未完成 |
| D05–D06、Q01、Q03 | 未验收 | 依路线逐项实施；真机用例单独保留 |
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
