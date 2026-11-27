# Proposal: 把 `create_account` 的契约留白（币种大小写 / 名称归一化 / 唯一性范围）写成契约事实

- 提案人: worker-module-a
- 目标契约: `contracts/module-a/v1.yaml`
- 兼容性判定: additive（minor；只补声明，不删字段、不改类型、不改枚举、不改错误码语义）
- 判定: accepted（orchestrator, 2026-11-27）；建议 1/3 不采纳，建议 2 按 v1 冻结、建议 4 按现状写进契约
- 影响面: `worker-module-a`（实现方）、`worker-module-b`（本契约消费者）。
  按 `contracts/module-b/v1.yaml`，B 的方法只接收 `account_id`，不调用
  `create_account`；但 B 的测试夹具若自行造账户，会直接踩这里的三条规则。
- 触发来源: 评审 F2 的后续（`20261127-semantics.md` 只覆盖了
  `record_entry` / `get_balance` / `list_entries`，`create_account.semantics`
  仍为空），以及第四轮返工要求。

## 动机

`create_account` 现在只有 `input` 的 `required` 与 `format: iso4217`，
实现在 `modules/module-a/ledger.py:152-169` 里另外定了三条调用方必须知道的规则：

1. `currency` **不做大小写归一化**：`"usd"` 直接 `INVALID_CURRENCY`；
2. `name` 去首尾空白后保存，去空白后为空 → `ValueError`（不是契约错误码）；
3. 名称唯一性是**每个 `LedgerService` 实例全局**的，**跨币种也唯一**：
   同名 + 不同币种仍然 `DUPLICATE_ACCOUNT_NAME`。

这三条目前只写在 `modules/module-a/README.md`（「仍不在契约、由实现补齐的只有」
那张表），下游要按契约取数就得读 A 的 README，与铁律 2 冲突；而且唯一性范围
不写清，一旦以后加持久化（DB 唯一约束放在哪一列）就会变成隐性 breaking。

## 变更内容（before → after）

`v1.yaml` 的 `methods[]` 里，`create_account` 段现在没有 `semantics`；新增：

```yaml
methods:
  - name: create_account
    # ... 现有 input / output / errors / idempotent / side_effects 不变 ...
    semantics:
      name_normalization: "去首尾空白后保存；两个仅相差首尾空白的名字视为同名"
      name_uniqueness: "同一 LedgerService 实例内唯一，且跨币种唯一（不按币种分区）；重名 → DUPLICATE_ACCOUNT_NAME"
      currency: "必须是现行 ISO 4217 三字母大写代码，不做大小写归一化；未知代码或非字符串 → INVALID_CURRENCY"
      field_order: "校验顺序 name → currency → 重名；前一项失败后不再校验后续项"
      generated_fields: "id 为 uuid4 字符串；created_at 为带 UTC 偏移的 ISO 8601 字符串"
      precondition_violation: "name 非字符串或去空白后为空 → ValueError（契约无对应错误码）"
```

`types.Account` 无需改：字段集与 `types` 已一致，`currency` 存的是调用方传入的
原始字符串（因为不做归一化）。

### 与 `error_codes` 口径的一致性核对

| 项 | 契约 | 实现 | 是否一致 |
|---|---|---|---|
| `INVALID_CURRENCY` | http 400, retryable false | `LedgerError("INVALID_CURRENCY")` → 400 | 一致 |
| `DUPLICATE_ACCOUNT_NAME` | http 409, retryable false | `LedgerError(...)` → 409 | 一致 |
| 名称非法（空 / 非字符串） | **无对应错误码** | `ValueError` | 口径不完全对齐（见建议 1） |
| `currency` 大小写 | `format: iso4217` 未定义大小写 | 只接受大写，不归一化 | 需在契约写明（本提案） |
| 唯一性范围 | 未定义 | 实例内全局 + 跨币种 | 需在契约写明（本提案） |

`create_account.errors` 只声明了 `[INVALID_CURRENCY, DUPLICATE_ACCOUNT_NAME]`，
所以空名走 `ValueError` 与 `20261127-semantics.md` 已受理的口径一致（前置条件
违反不进 `error_codes`）。这不是 bug，但调用方必须知道两种异常并存。

## 兼容性判定

additive / minor：只新增 `semantics` 键，不删字段、不改 `input` / `output` /
`errors` / `types`、不改任何错误码含义。现有调用方行为不变（实现未改）。

对 module-b：纯增量。B 目前不调用 `create_account`；若 B 的夹具造账户，需要知道
`"usd"` 不合法、`"Cash "` 与 `"Cash"` 同名、不同币种不能重用同名。

## 迁移步骤

1. orchestrator 在提案上标 `accepted`；
2. worker-module-a 把上面的 `semantics` 块落进 `v1.yaml`，抄进
   `contracts/module-a/CHANGELOG.md`（2026-11-27 第三条）；
3. 同一次提交在 `tests/contracts/module-a/test_ledger_contract.py` 的
   `test_contract_declares_semantics_for_stateful_methods` 里补
   `create_account` 的键集合断言（防止契约被改而测试不察觉）；
4. 通知 worker-module-b：造夹具账户时按上面三条规则。

## 回滚方式

删除 `create_account.semantics` 键即可；不涉及代码与测试行为，回滚零影响。

## 建议（不擅自改行为，等判定）

1. **空名是否要可枚举错误码**：现在 `create_account(name="")` 抛 `ValueError`，
   而 `record_entry` 的 `category` 非法走 `INVALID_CATEGORY`。两种风格并存会让
   HTTP 适配层要分别映射。若要统一，可新增 `INVALID_NAME`（http 400）——
   属「新增错误码」，需单独立项评估对 B 的影响；本提案不包含。
2. **唯一性范围**：实例内全局是本实现的自然结果，不是业务决策。若将来加持久化，
   DB 唯一索引应建在「规范化后的 name」上，并且**明确是否跨币种**；现在选
   「跨币种唯一」，若业务实际想要「同币种下可同名」，那会是 breaking（改语义），
   建议在写库前定死。
3. **大小写归一化**：严格大写符合 ISO 4217 字面，但对用户输入的容错差。
   若决定接受 `"usd"` 并归一化为 `"USD"`，那是放宽输入（语义变更），
   应在入库前定，不要等到有历史数据再改。
4. **校验顺序**会影响错误码归属：`create_account(name="", currency="usd")` 现在
   返回 `ValueError` 而不是 `INVALID_CURRENCY`。若下游按「先报币种错」的假设写
   分支，会与实际不符；本提案把顺序写进 `semantics.field_order` 就是为了消除
   这种猜测。

## 受理记录

- 2026-11-27 accepted（orchestrator）。四条建议的处置如下。

### 建议① 新增 `INVALID_NAME`：**不采纳**

`name` 是必填字段，去空白后为空属「必填值缺失」，与 `category`（可选、有命名规则）
不同类。新增错误码会把「业务失败可枚举」扩成参数校验清单，且现有 6 个错误码是
`TASK-MODULE-A-001` 的验收基线。**口径：必填值缺失抛 `ValueError`**，已写进
`modules/module-a/README.md`，并在契约 `semantics.precondition_violation` 里固定。

### 建议② 唯一性范围：**v1 冻结**

冻结为「同一 `LedgerService` 实例内、跨币种唯一」，作为契约事实写进
`semantics.name_uniqueness`。**在引入持久化或 `TASK-MODULE-A-002` 之前必须单独
提案重定，届时属 breaking**（契约 `stability: stable`，
`versioning.strategy: semver_method`）。同一注记已写进
`contracts/module-a/CHANGELOG.md`。

### 建议③ 币种大小写：**不归一化**

`INVALID_CURRENCY` 覆盖：非字符串、非三字母大写、未知代码。放宽容错（例如接受
`"usd"` 并归一化为 `"USD"`）属后续语义变更，走提案，不随本提案夹带。

### 建议④ 校验顺序：**按现状写进契约**

顺序为 `name → currency → 重名`，错误码归属由顺序决定：
`create_account(name="", currency="usd")` 返回 `ValueError` 而非 `INVALID_CURRENCY`。

### 落地结果

- `contracts/module-a/v1.yaml` 的 `create_account.semantics`（2026-11-27）
- `contracts/module-a/CHANGELOG.md` 第三条 additive 变更 + 持久化注记
- `tests/contracts/module-a/test_ledger_contract.py::test_contract_declares_semantics_for_stateful_methods`
  的键集合断言扩展到四个方法
- `modules/module-a/README.md`：「必填值缺失抛 `ValueError`」口径