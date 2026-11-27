# Task: TASK-MODULE-B-001 — module-b 报表域首个可交付切片（月度汇总 / 分类统计）

- **Owner**: `worker-module-b`
- **Module**: `module-b`
- **State**: `backlog`（`contracts/module-a/mocks/ledger_service.py` 就绪后转 `ready`）
- **Branch**: `feature/module-b-TASK-MODULE-B-001`
- **Contracts**: `contracts/module-b/v1.yaml`（`approved`）、消费 `contracts/module-a/v1.yaml`

## 目标

实现记账 API 的报表域：按月汇总某账户收支、按分类统计区间支出；取数只通过 `module-a` 的契约。

## 依赖

- 任务：`[TASK-000]`（已完成）
- 契约：`contracts/module-b/v1.yaml`（`approved`）
- 上游 mock：`contracts/module-a/mocks/ledger_service.py`（由 A 交付，当前不存在）

## 所有权边界

- 允许：`modules/module-b/**`、`tests/modules/module-b/**`、`tests/contracts/module-b/**`、`contracts/module-b/**`
- 禁止：`shared/**`、`modules/module-a/**`、`contracts/module-a/**`、`tests/modules/module-a/**`、`tests/contracts/module-a/**`、`scripts/**`、`.agent/**`

## 验收标准

1. 正常路径：给定账户与月份，`monthly_summary` 返回 income/expense/net；`category_breakdown` 按分类汇总。
2. 错误路径：`ACCOUNT_NOT_FOUND`、`INVALID_PERIOD`、`INVALID_DATE_RANGE` 各命中一次，返回码与契约一致。
3. 跨模块：只调用 `contracts/module-a/v1.yaml` 声明的方法；不读 `modules/module-a/**` 源码。
4. 契约测试：两个方法存在，参数名与必填性与契约一致。
5. 不回归：自查受影响用例仍通过。

## 验证

| 检查 | 精确命令 | 期望证据 |
|---|---|---|
| 契约 | `uv run pytest tests/contracts/module-b` | 全部通过，exit 0 |
| 越界 | `bash scripts/ownership-check.sh origin/main HEAD --owner worker-module-b` | 无无主路径、无越界 |
| 单测 | `uv run pytest tests/modules/module-b` | 全部通过，exit 0 |
| Lint | `uv run ruff check modules/module-b tests/modules/module-b tests/contracts/module-b` | 0 errors |
| 类型 | `uv run mypy modules/module-b` | exit 0 |
| 集成 | `TBD`（跨模块用例待 A 实现落地后补） | — |

## Mock

- 需要：`yes`
- 位置：`contracts/module-a/mocks/ledger_service.py`

## 交付

- 分支与 commit SHA
- 报告（五段格式，见 `docs/protocol/agent-protocol.md`）
- 契约增量：`none` 或提案 id

## 停止条件

契约要改、路径要越界、需要共享层改动、mock 与上游实现语义不符时，停下并报告。