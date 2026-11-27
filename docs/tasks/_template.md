# Task: <TASK-ID> — <TITLE>

- **Owner**: `<worker-id>`
- **Module**: `<module-id>`
- **State**: `backlog` | `ready`
- **Branch**: `feature/<module>-<task-id>`
- **Contracts**: `contracts/<module>/v1.yaml`

## 目标

一句话说清可观察的结果。

## 依赖

- 任务：`[]`
- 契约：`[]`（状态必须是 `approved`）

## 所有权边界

- 允许：`...`
- 禁止：`...`

## 验收标准

1. 正常路径。
2. 错误路径（契约里声明的错误码必须各命中一次）。
3. 不回归（受影响的既有用例仍通过）。

## 验证

| 检查 | 精确命令 | 期望证据 |
|---|---|---|
| 契约 | `TBD` | 契约测试通过 |
| 越界 | `TBD` | ownership 通过 |
| 单测 | `TBD` | exit 0 |
| 集成 | `TBD` | 跨模块用例通过 |

## Mock

- 需要：`yes|no`
- 位置：`contracts/<upstream>/mocks/`

## 交付

- 分支与 commit SHA
- 报告（五段格式）
- 契约增量：`none` 或提案 id

## 停止条件

契约要改、路径要越界、需要共享层改动、需要跑有副作用的命令时，停下并报告。