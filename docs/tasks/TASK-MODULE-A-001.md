# Task: TASK-MODULE-A-001 — module-a 账目域首个可交付切片（账户 / 流水 / 余额）

- **Owner**: `worker-module-a`
- **Module**: `module-a`
- **State**: `ready`
- **Branch**: `feature/module-a-TASK-MODULE-A-001`
- **Contracts**: `contracts/module-a/v1.yaml`（`approved`）

## 目标

实现记账 API 的账目域：开账户、记流水、查余额、查流水列表，行为与契约 `v1` 一致；并交付 `module-b` 可用的 mock。

## 依赖

- 任务：`[TASK-000]`（已完成）
- 契约：`contracts/module-a/v1.yaml`（`approved`）

## 所有权边界

- 允许：`modules/module-a/**`、`tests/modules/module-a/**`、`tests/contracts/module-a/**`、`contracts/module-a/**`
- 禁止：`shared/**`、`modules/module-b/**`、`contracts/module-b/**`、`scripts/**`、`.agent/**`、`pyproject.toml`、`*.lock`

## 验收标准

1. 正常路径：开账户 → 记收入/支出 → 余额等于 income 合计减 expense 合计 → `list_entries` 按时间范围返回。
2. 错误路径：`INVALID_CURRENCY`、`DUPLICATE_ACCOUNT_NAME`、`ACCOUNT_NOT_FOUND`、`INVALID_AMOUNT`、`INVALID_CATEGORY`、`INVALID_DATE_RANGE` 各命中一次，返回码与契约一致。
3. 契约测试：四个方法存在，参数名与必填性与契约一致。
4. 交付 mock：`contracts/module-a/mocks/ledger_service.py`，字段与错误码与契约同源。
5. 不回归：自查受影响用例仍通过。

## 验证

| 检查 | 精确命令 | 期望证据 |
|---|---|---|
| 契约 | `uv run pytest tests/contracts/module-a` | 全部通过，exit 0 |
| 越界 | `bash scripts/ownership-check.sh origin/main HEAD --owner worker-module-a` | 无无主路径、无越界 |
| 单测 | `uv run pytest tests/modules/module-a` | 全部通过，exit 0 |
| Lint | `uv run ruff check modules/module-a tests/modules/module-a tests/contracts/module-a` | 0 errors |
| 类型 | `uv run mypy modules/module-a` | exit 0 |
| 集成 | `TBD`（跨模块用例待 B 落地后补） | — |

## Mock

- 需要：`no`（本模块是上游，需**产出** mock 给 `worker-module-b`）
- 位置：`contracts/module-a/mocks/ledger_service.py`

## 交付

- 分支与 commit SHA
- 报告（五段格式，见 `docs/protocol/agent-protocol.md`）
- 契约增量：`none` 或提案 id

## 停止条件

契约要改、路径要越界、需要共享层改动、需要跑有副作用的命令时，停下并报告。