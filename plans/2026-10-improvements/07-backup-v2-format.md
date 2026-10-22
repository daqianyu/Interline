# D04 文件式备份 v2 设计

状态：设计已选定，待第一阶段验收后实现；本文件不代表 v2 已交付。

## 目的与兼容

使用单个 `.interlinebackup` 文件，内容为 manifest 加按序独立章节 JSON。
不压缩、不执行内容、不引入依赖；使用固定长度框架以便顺序读取，并避免压缩展开风险。
新版本默认导出 v2，继续接受 v1 JSON；旧版本应用不能读取 v2，界面说明兼容范围。
包含活动/已移出书籍、阅读位置、书签、笔记、草稿和设置；Recovery 原始保全资料仍通过
现有单独入口导出，自动纳入与部分导出策略归 F07，不将损坏资料称为可恢复正文。

## 文件结构

1. 固定 UTF-8 魔数 `InterlineBackup2\n`，无 BOM。
2. 8 字节无符号大端整数：manifest 的字节数；解析前验证范围，再转为 Int。
3. UTF-8 JSON manifest。
4. 按 manifest 的 entries 顺序连续存放正文 JSON；每个条目的长度来自 manifest。
5. 最后一条正文之后必须 EOF；多余字节、截断、长度不符均拒绝。

manifest 字段：`version=2`、`createdAt`、`complete=true`、`books`、`removedBooks`、
`preferences`、`bookmarks`、`annotations`、`drafts`、`entries`。
books 只含 Book metadata（chapters 必须为空）；entries 每项包含 `bookID`、`byteCount`、
`sha256`，其 bookID 与 books + removedBooks 的顺序一一对应。不得存在重复/遗漏/额外条目。
正文为现有 `[Chapter]` JSON，UTF-16 canonical text 与存储格式不变。
SHA-256 校验原始正文 JSON 字节，只用于发现损坏，不表示来源已认证或文件已加密。
格式不携带文件路径；暂存文件名由程序按索引生成，书 ID 不用于拼接文件路径。

资源上限：整个文件仍为 256 MiB；manifest 最多 32 MiB；书数最多 10,000；
单书 canonical UTF-16 长度仍为 24 Mi；读取/复制块至多 64 KiB。
每次追加检查剩余预算，整数运算先用减法核验，未知版本和 partial 标记直接拒绝。
单书解析仍需一次加载该书，元数据/笔记仍需驻留；不称为恒定内存。

## 导出与临时文件

在独立 UUID 临时目录中逐书读取、验证、编码、计算校验并暂存正文，再编码 manifest，
最后写入容器并逐文件分块复制。完成关闭文件后才把导出结果交给系统文档选择器。
使用系统“存储到文件”流程导出 URL，避免 FileDocument 再生成整份 Data。
使用 Apple 已公开的 `UIDocumentPickerViewController(forExporting:asCopy:)`，并以
`asCopy: true` 导出；参见 [官方 API](https://developer.apple.com/documentation/uikit/uidocumentpickerviewcontroller/init(forexporting:ascopy:))。
导出文件持有专用临时目录；系统完成/取消及视图释放后清理，正在使用时不得提前删除。
任何失败/取消只清理本次 UUID 目录，原书库不变；磁盘不足明确失败。

## 读取、校验和恢复

文件选择后在安全作用域/NSFileCoordinator 范围内读取。识别魔数，v2 顺序校验长度、
SHA-256、JSON、章节、摘录引用并暂存；v1 继续走既有验证，再逐书转换成同一暂存结果。
v1 全量解码的内存限制如实保留。两种输入都只在验证完成后出现恢复确认。
暂存结果持有只读元数据和按书独立文件，不携带全部正文对象；对象释放时清理目录。
恢复先核对已有同 ID 正文是否一致，再写事务日志。逐书写入新正文或修复缺失正文，
保持当前元数据/笔记优先及空库恢复设置语义；提交后重新加载。
失败按 D02 回滚规则处理，日志无法清除时继续阻止写入。调用方取消传递给后台任务。

## 验收

- v1/v2 导入同一资料结果相同；v2 默认导出往返，空库与幂等合并通过。
- 错误版本、complete=false、重复/缺失条目、非空 metadata.chapters、错误 hash、
  截断、尾随字节、异常长度、manifest 超限均在事务前失败，原库字节不变。
- 有效 hash 但不合法 JSON/章节/摘录也拒绝，不能只验证校验和。
- 临时文件在成功导出生命周期结束、取消、失败后释放；源文件保留。
- 模拟器实际确认导出/恢复入口与新的文件类型；真机文件提供器归 Q01 待签名后验证。
- 固定样本对比旧全量、逐书 v1 和文件式 v2 的内存指标，记录运行环境与测量限制。
  没有数值前不声称节省百分比；测量后根据实际结果决定后续优化。

## 内存测量执行方案

使用 XCTest 的 `XCTMemoryMetric`，同时保存峰值和起止增量；两者含义不同，不互相替代。
参见 [Apple：Preventing memory-use regressions](https://developer.apple.com/documentation/xcode/preventing-memory-use-regressions)。
样本固定为 20 本互异 ID、每本 4 章、每章 128 Ki 个中文字符，使用磁盘正文及 metadata
入口，正文生成和文件准备在测量区间之外。旧全量实现只保留在测量辅助代码中，不作为
生产回退路径。分别测旧 v1、逐书 v1、文件 v2，记录输出字节数、峰值、增量与耗时。
每种至少 3 次；最好单独启动测试进程，避免前一次大分配留下的分配器缓存污染比较。
结果属于指定模拟器/构建，不推断所有手机；若数据噪声过大或峰值没有下降，保留结果并
检查分配器缓存、正文生成是否落入区间及文件导出是否又被读成完整 Data，再决定下一步。
