# 依赖图与并行批次

源数据在 `.agent/project-dependencies.yaml`，本文是它的人读版本。两者不一致时以 YAML 为准，
并跑 `contract-check.sh --dag` 找原因。

## 当前图

```
shared
 ├── TBD-a
 └── TBD-b
```

## 并行判定

一个模块可以开工，需要同时满足：

1. 它 `deps` 里的每个模块，其契约状态都是 `approved`。
2. 它的可写路径不与任何 `in_progress` 任务重叠。
3. `verify_cmds` 可以执行（依赖已装、测试框架已就位）。

注意「依赖已实现」不是开工条件，「依赖的契约已批准」才是。这是并行度的来源。

## 批次记录

| 批次 | 并行任务 | 开始条件 | 实际开始 / 完成 |
|---|---|---|---|
| B1 | TASK-000 | 无 | TBD |
| B2 | TASK-A-001, TASK-B-001 | 契约 approved | TBD |

## 阻塞与解法

| 阻塞点 | 影响模块 | 解法 |
|---|---|---|
| 上游未实现 | 下游 | 按契约写 Mock 先跑通链路 |
| 契约含糊 | 双方 | 提 proposal，不猜 |
| 共享路径要改 | 全部 | orchestrator 改，Worker 等通知 |