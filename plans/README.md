# Interline 项目计划

当前计划：[2026-10 产品完善计划](2026-10-improvements/00-roadmap.md)。

所有后续开发、修复、优化、测试和验收均从本目录开始。用户的新指令优先，
但必须同步更新计划，避免聊天结论与仓库状态脱节。

## 阅读顺序

1. [开发路线与状态](2026-10-improvements/00-roadmap.md)：执行顺序、依赖、当前步骤。
2. [大需求设计](2026-10-improvements/01-requirements.md)：问题、目标、方案和边界。
3. [开发设计](2026-10-improvements/02-development-design.md)：实现、兼容和失败处理。
4. [测试验收设计](2026-10-improvements/03-test-acceptance-design.md)：用例、环境与门槛。
5. [最终验收记录](2026-10-improvements/04-final-acceptance.md)：真实证据和发布结论。
6. [执行日志](2026-10-improvements/05-execution-log.md)：每次完成项、变更与下一步。
7. [无障碍检查矩阵](2026-10-improvements/06-accessibility-matrix.md)：Q02 分页面用例、证据和后续修复归属。

## 状态规则

- `TODO`：尚未实施。
- `IN_PROGRESS`：已选定并开始实施。
- `IMPLEMENTED`：代码完成，要求的验证尚未全部通过。
- `VERIFIED`：该项约定的验收已通过，并有对应版本的证据。
- `BLOCKED`：存在明确外部前置条件，必须写明原因与解除方式。

`00-roadmap.md` 是需求状态的唯一清单；验收文档记录证据与剩余条件。
不能把“文档完成”写成“全部功能完成”，不能用旧版本测试替代新修改的验证。
当一项包含多个交付步骤时，按完成的子步骤记录，不提前关闭整项。
