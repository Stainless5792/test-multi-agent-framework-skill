# module-a 契约变更记录

版本策略见 `docs/contracts/contract-format.md`（`semver_method`）。版本号仍是 `v1`，
文件名不变；四次变更都是 additive / minor，无 breaking。

## v1（文件名不变）

| 日期 | 提案 | 判定 | 变更 |
|---|---|---|---|
| 2026-11-27 | [`proposals/20261127-entrypoint.md`](proposals/20261127-entrypoint.md) | accepted（orchestrator，方案 A） | 新增顶层 `implementation: {module_path, factory, bootstrap}`，下游接入方式由契约决定；附带两条约束：`factory` 必须写 `<import 名>:<类名>`、必须存在入口契约测试 |
| 2026-11-27 | [`proposals/20261127-semantics.md`](proposals/20261127-semantics.md) | accepted（additive / minor） | 新增 `record_entry` / `get_balance` / `list_entries` 的 `semantics` 块（排序、区间开闭、缺省值、前置条件）；`types.Entry.category` / `memo` 标注缺省 `""`；全部日期输入（`occurred_on` / `from` / `to` / `as_of`）收紧为 `YYYY-MM-DD` 严格形态（长度 10、第 5/8 位为 `-`） |
| 2026-11-27 | [`proposals/20261127-create-account-semantics.md`](proposals/20261127-create-account-semantics.md) | accepted（additive / minor） | 新增 `create_account.semantics`：`name` 去空白、唯一性范围（同一实例内 + 跨币种）、`currency` 不做大小写归一化、校验顺序 `name → currency → 重名`、生成字段、必填值缺失抛 `ValueError` |
| 2026-11-27 | [`proposals/20261127-error-surface.md`](proposals/20261127-error-surface.md) | accepted（orchestrator 预批，additive / minor） | 新增顶层 `error_surface`：业务失败以 `exception` 交付，异常必须暴露 `code` / `http_status` / `retryable`，`code` 取值域就是 `error_codes`，**类名不是契约事实**；`list_entries.semantics.from_parameter` 声明 `**{"from": d}` 与 `from_=d` 等价 |

### 兼容性

- 四次变更均只新增声明字段/注释，不删除、不改类型、不改枚举、不改已有错误码语义。
- `implementation` 对已有消费者是纯增量：受理前用
  `contracts/module-a/mocks/ledger_service.py`，受理后按 `implementation` 接入真实实现。
- 日期输入收紧只影响从未在契约里合法过的输入（紧凑 `20260101`、ISO 周日期
  `2026-W01-4`）：从「意外成功」变为按契约 `ValueError`，不构成 breaking。
- `create_account.semantics` 只是把既有行为写进契约，实现未改，对消费者零行为变化。

### 注记：唯一性范围在 v1 冻结

`create_account.semantics.name_uniqueness` 在 v1 冻结为「同一 `LedgerService`
实例内、跨币种唯一」。**在引入持久化或 `TASK-MODULE-A-002` 之前，若要改唯一性范围
（例如改为按币种分区、或跨实例全局），必须单独提案重定；届时属 breaking**
（契约 `stability: stable`，`versioning.strategy: semver_method`），需要 major 升版
与一个窗口期的旧版本保留。

### 未排期

- `TASK-MODULE-A-002`（backlog）：把实现改成可导入包 `modules/module_a/`，
  届时 `implementation.module_path` 改为 `modules`、`factory` 改为
  `module_a:LedgerService`。触发条件：module-a 出现第二个实现文件，或 module-b
  集成测试落地前。