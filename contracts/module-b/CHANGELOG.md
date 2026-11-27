# module-b 契约变更记录

版本策略见 `docs/contracts/contract-format.md`（`semver_method`）。版本号仍是 `v1`，
文件名不变。

## v1（文件名不变）

| 日期 | 提案 | 判定 | 变更 |
|---|---|---|---|
| 2026-11-27 | [`proposals/20261127-semantics.md`](proposals/20261127-semantics.md) | accepted（additive / minor） | 新增 `monthly_summary` / `category_breakdown` 的 `semantics`（自然月闭区间、`year` 1..9999、`month` 1..12、`income`/`expense` 非负、`net = income - expense`、`period` 零填充、空结果、校验顺序、错误透传、上游调用形态）；新增顶层 `implementation`（`modules/module-b` + `report:ReportService` + `sys_path`）；`types` / `error_codes` 补注释 |

### 兼容性

- 只新增 `semantics`、`implementation` 与注释，不删字段、不改类型、不改枚举、
  不改任何 `error_codes` 键；`contract.consumers` 为空，无下游代码受影响。
- `scripts/contract-check.sh --base origin/main` 判定无 breaking（见提案 VERIFY）。
- `category_breakdown` 只统计 `expense`；v1 不提供 `income` 维度，需要时另开方法或提案。

### 注记：`ACCOUNT_NOT_FOUND` 透传等 A-003

`semantics.error_passthrough` 已进契约，但错误载体的形态由
`TASK-MODULE-A-003` 在 `contracts/module-a/v1.yaml` 的顶层 `error_surface` 声明。
A-003 合入前，`contracts/module-b` 的透传测试保持 `skip`，不按 mock 的 `.code` 猜。