# module-a 契约变更记录

版本策略见 `docs/contracts/contract-format.md`（`semver_method`）。版本号仍是 `v1`，
文件名不变；两次变更都是 additive / minor，无 breaking。

## v1（文件名不变）

| 日期 | 提案 | 判定 | 变更 |
|---|---|---|---|
| 2026-11-27 | [`proposals/20261127-entrypoint.md`](proposals/20261127-entrypoint.md) | accepted（orchestrator，方案 A） | 新增顶层 `implementation: {module_path, factory, bootstrap}`，下游接入方式由契约决定；附带两条约束：`factory` 必须写 `<import 名>:<类名>`、必须存在入口契约测试 |
| 2026-11-27 | [`proposals/20261127-semantics.md`](proposals/20261127-semantics.md) | accepted（additive / minor） | 新增 `record_entry` / `get_balance` / `list_entries` 的 `semantics` 块（排序、区间开闭、缺省值、前置条件）；`types.Entry.category` / `memo` 标注缺省 `""`；全部日期输入（`occurred_on` / `from` / `to` / `as_of`）收紧为 `YYYY-MM-DD` 严格形态（长度 10、第 5/8 位为 `-`） |

### 兼容性

- 两次变更均只新增声明字段/注释，不删除、不改类型、不改枚举、不改已有错误码语义。
- `implementation` 对已有消费者是纯增量：受理前用
  `contracts/module-a/mocks/ledger_service.py`，受理后按 `implementation` 接入真实实现。
- 日期输入收紧只影响从未在契约里合法过的输入（紧凑 `20260101`、ISO 周日期
  `2026-W01-4`）：从「意外成功」变为按契约 `ValueError`，不构成 breaking。

### 未排期

- `TASK-MODULE-A-002`（backlog）：把实现改成可导入包 `modules/module_a/`，
  届时 `implementation.module_path` 改为 `modules`、`factory` 改为
  `module_a:LedgerService`。触发条件：module-a 出现第二个实现文件，或 module-b
  集成测试落地前。