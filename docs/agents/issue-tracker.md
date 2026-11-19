# 本地 Markdown 工单

每个功能使用一个 `.scratch/<feature>/` 目录。

- 规格写入 `spec.md`。
- 每张实施工单单独写入 `issues/<NN>-<slug>.md`，编号从 `01` 开始。
- 在工单开头用 `Status:` 记录[分类标签](triage-labels.md)，在文末的 `## Comments` 下追加讨论。
- 技能要求发布规格或工单时，按上述路径创建文件。读取工单时，按给定路径或功能目录内的编号查找。

## Wayfinder

在功能目录的 `map.md` 中维护 `Notes`、`Decisions-so-far` 和 `Fog`。
每个待解决的问题占一张子工单，正文写明问题，`Type:` 取 `research`、`prototype`、`grilling` 或 `task`。

用 `Blocked by: 01, 02` 这样的行记录依赖。所有列出的工单均为 `resolved` 后，阻塞解除。
从未解决、未认领且无阻塞的工单中选编号最小的一张，先保存 `Status: claimed`，再开始工作。
完成后在 `## Answer` 下追加答案，保存 `Status: resolved`，并将结论摘要和工单链接追加到 `map.md` 的 `Decisions-so-far`。
