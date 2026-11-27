# module-b 契约变更记录

版本策略见 `docs/contracts/contract-format.md`（`semver_method`）。版本号仍是 `v1`，
文件名不变。

## v1（文件名不变）

| 日期 | 提案 | 判定 | 变更 |
|---|---|---|---|
| 2026-11-27 | [`proposals/20261127-semantics.md`](proposals/20261127-semantics.md) | accepted（additive / minor） | 新增 `monthly_summary` / `category_breakdown` 的 `semantics`（自然月闭区间、`year` 1..9999、`month` 1..12、`income`/`expense` 非负、`net = income - expense`、`period` 零填充、空结果、校验顺序、错误透传、上游调用形态）；新增顶层 `implementation`（`modules/module-b` + `report:ReportService` + `sys_path`）；`types` / `error_codes` 补注释 |
| 2026-11-27 | 同上（收口轮，orchestrator 预批） | accepted（additive / minor） | `implementation` 增 `requires: [ledger ← contracts/module-a/v1.yaml]`；新增顶层 `error_surface`（`mechanism=exception`、`attributes=[code, http_status, retryable]`、`code_domain=error_codes`）；删除指向不存在文件的 `mocks` 节 |

### 兼容性

- 只新增 `semantics`、`implementation`（含 `requires`）、`error_surface` 与注释，
  不删字段、不改类型、不改枚举、不改任何 `error_codes` 键；`contract.consumers`
  为空，无下游代码受影响。
- `scripts/contract-check.sh --base origin/main` 判定无 breaking（见提案 VERIFY）。
- `category_breakdown` 只统计 `expense`；v1 不提供 `income` 维度，需要时另开方法或提案。

### 删除 `mocks` 的理由

`mocks.path` 原指向 `contracts/module-b/mocks/report_service.py`，该文件从未存在。
B 当前没有消费者，不需要下游 mock；按 `docs/protocol/agent-protocol.md:32-34`，
mock 与真实实现并存本就视为缺陷。若将来出现消费者，再按契约提供 mock 并写
parity 测试，避免两份实现漂移。

### 注记：`ACCOUNT_NOT_FOUND` 透传已落地

错误载体形态以 `contracts/module-a/v1.yaml` 顶层 `error_surface` 为准（A-003，
`75dd608`）。B 只按 `attributes` 读 `code`：`ACCOUNT_NOT_FOUND` 重包为 B 的
`ReportError`，其余上游业务错误码抛 `RuntimeError`；测试不断言 A 的异常类名。