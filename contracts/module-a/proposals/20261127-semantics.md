# Proposal: 把契约留白（排序 / 区间 / 缺省值 / 前置条件）写成契约事实

- 提案人: worker-module-a
- 目标契约: `contracts/module-a/v1.yaml`
- 兼容性判定: additive（minor；只补声明，不删字段、不改类型、不改枚举、不改错误码语义）
- 判定: accepted（orchestrator, 2026-11-27）
- 影响面: `worker-module-b`（月度汇总 / 分类统计直接依赖排序与区间开闭）、
  `worker-module-a`（实现与测试已按这套语义锁死）
- 触发来源: 评审 F2 / F7（`docs/reviews/TASK-MODULE-A-001-review.md:22,27`）

## 动机

`TASK-MODULE-A-001` 的实现与测试已经固定了一批**可观察行为**，契约里却一字未写：

| 行为 | 当前实现 | 契约现状 |
|---|---|---|
| `list_entries` 排序 | `occurred_on` 升序，同日按写入顺序（稳定排序） | 未声明 |
| `from` / `to` | 闭区间，单边可省略 | 未声明 |
| `get_balance(as_of)` | 含当天（`occurred_on <= as_of`） | 未声明 |
| `category` / `memo` 缺省 | 输出 `""` | 只写了 `type: string` |
| `memo` 归一化 | 入库前 `strip()` | 未声明 |
| `kind` 非枚举 / 日期非法 / `limit <= 0` | 抛 `ValueError` | 未声明 |

module-b 的 `monthly_summary` / `category_breakdown` 直接建立在前四条之上：
区间开闭差一天、排序不稳定，汇总数字就会静默错位。按
`agent-protocol.md:8`（契约优先）与 `:38`（语义含糊要提提案），这些必须进契约，
而不是留在实现与 README 里。

## 变更内容（before → after）

### 1. `record_entry.semantics`

```yaml
methods:
  - name: record_entry
    # ... 现有 input / output / errors 不变 ...
    semantics:
      amount: "最小货币单位正整数；<= 0、非整数、bool 均 INVALID_AMOUNT"
      category_default: "未提供时 Entry.category 输出空字符串"
      category_normalization: "去首尾空白；去空白后为空、超 64 字符或含控制字符 → INVALID_CATEGORY"
      memo_default: "未提供时 Entry.memo 输出空字符串"
      memo_normalization: "提供时去首尾空白后保存"
      date_input: "YYYY-MM-DD（严格形态：长度 10、第 5/8 位为 -）或 datetime.date；其他形态 → ValueError"
      precondition_violation: "kind 不是 income|expense → ValueError"
```

### 2. `get_balance.semantics`

```yaml
  - name: get_balance
    # ... 现有 input / output / errors 不变 ...
    semantics:
      as_of: "含当天：只累计 occurred_on <= as_of 的流水；as_of 未提供时累计全部"
      date_input: "YYYY-MM-DD（严格形态：长度 10、第 5/8 位为 -）或 datetime.date；其他形态 → ValueError"
      amount: "有符号：income 合计 - expense 合计"
```

### 3. `list_entries.semantics`

```yaml
  - name: list_entries
    # ... 现有 input / output / errors 不变 ...
    semantics:
      range: "闭区间：from <= occurred_on <= to；任一端可省略，两端都可省略时返回全部"
      order: "按 occurred_on 升序；同一日期内保持写入（创建）顺序，排序必须稳定"
      limit: "在上述排序之后取前 N 条；提供时必须为正整数，否则 ValueError"
      date_input: "YYYY-MM-DD（严格形态：长度 10、第 5/8 位为 -）或 datetime.date；其他形态 → ValueError"
```

### 4. `types.Entry` 的缺省值注释

```yaml
types:
  Entry:
    # ...
    category: { type: string }   # 缺省 ""；归一化规则见 record_entry.semantics
    memo: { type: string }       # 缺省 ""；提供时去首尾空白
```

### 5. 为什么 `ValueError` 不进 `error_codes`

`kind` 非枚举、日期非法、`limit <= 0` 是**调用方违反契约已声明的类型/格式**，
不是业务结果。新增错误码会让 `error_codes` 从「业务失败可枚举」退化成
「所有编程错误也要编码」，并迫使 module-b 为每种参数错误写分支。因此保持：

- 业务失败 → `LedgerError`，`code` 只取 `error_codes` 的 6 个键；
- 前置条件违反 → `ValueError`，不进 `error_codes`，也不承诺 `http` 映射。

评审已认可这一判定（`TASK-MODULE-A-001-review.md:34`），本提案把它写成契约文字，
避免下一位消费者再从实现里反推。

### 6. F7：日期输入收紧为 `YYYY-MM-DD`

实测当前 `date.fromisoformat` 除 `2026-01-01` 外还接受：

```
'20260101'   -> 2026-01-01     （紧凑格式）
'2026-W01-4' -> 2026-01-01     （ISO 周日期）
```

两者契约都没写。**决定：收紧为 `YYYY-MM-DD` 严格形态**——长度必须为 10，
且第 5、8 位必须是 `-`，再过 `date.fromisoformat`。紧凑格式与 ISO 周日期一律
`ValueError`。

> 落地时发现：`'2026-W01-4'` 长度也是 10，只卡 `len(value) != 10` 拦不住它
> （实测第一版用例 8 条 red）。因此判定标准补成「长度 10 + 两位分隔符」，
> 契约 `semantics.date_input` 同步写成「严格形态：长度 10、第 5/8 位为 -」。

理由：允许紧凑格式就必须同时把 ISO 周日期一并写进契约并承诺稳定——那是
Python 3.11+ 的解析细节，把它写进稳定契约，未来收紧就是 breaking。宁可现在收紧。

范围：**全部日期输入**（`occurred_on` / `from` / `to` / `as_of`）共用同一校验，
因此 `get_balance.semantics` 也带 `date_input`。

受理后要改的一处（本轮已按此落地，real 与 mock 同提交）：

```diff
--- a/modules/module-a/ledger.py
+++ b/modules/module-a/ledger.py
@@
     if not isinstance(value, str):
         raise ValueError(f"{field} 必须是 ISO 8601 日期字符串")
+    # 契约只接受 YYYY-MM-DD：光卡长度不够，ISO 周日期（2026-W01-4）也是 10 字符
+    if len(value) != 10 or value[4] != "-" or value[7] != "-":
+        raise ValueError(f"{field} 必须是 YYYY-MM-DD: {value!r}")
     try:
         return date.fromisoformat(value)
```

同一提交同步了 `contracts/module-a/mocks/ledger_service.py`（`ledger.py` 的逐行
镜像），并加了两组用例：`test_record_entry_rejects_non_yyyy_mm_dd`、
`test_read_side_rejects_non_yyyy_mm_dd`（真实实现与 mock 各跑一遍），
parity 场景 `date_input_rejects_non_yyyy_mm_dd`。

**第二轮为什么没动代码**：mock 当时被冻结（「不动 mock 文件本身」），而只改
`ledger.py` 会制造新的 real↔mock 漂移——那正是 F3 要消灭的问题。本轮受理后
real 与 mock 原子同步。

## 兼容性判定

- 全部为 **additive / minor**：新增 `semantics` 键与注释，不删不改任何
  `input` / `output` / `errors` / `types` 字段或类型。
- 对 module-b：受理后行为不变（实现早已如此），只是从「契约外」变成「契约内」；
  唯一行为变化是 F7 收紧，仅影响传紧凑格式/周日期的调用方，而这类输入从未在
  契约里合法过，按 `contract-format.md:69`「改语义 → major」的严格解读也不构成
  breaking（非法输入从「意外成功」变成「按契约报错」）。
- `scripts/contract-check.sh` 不校验 `semantics` 键，无脚本改动。

## 迁移步骤

1. orchestrator 在提案上标 `accepted`；
2. worker-module-a 把上面 4 个 YAML 片段落进 `v1.yaml`（`semantics` 与
   `errors` / `idempotent` 同级）；
3. 同一次提交里按第 6 节改 `ledger.py` + `mocks/ledger_service.py`，并加
   「紧凑格式 / 周日期被拒绝」的用例（真实实现与 mock 各跑一遍）；
4. 跑 `uv run pytest tests/contracts/module-a tests/modules/module-a`、
   `bash scripts/contract-check.sh`，把提案判定抄进 `CHANGELOG.md`；
5. 通知 worker-module-b：排序 / 区间 / 缺省值已进契约，`ValueError` 属前置条件违反。

## 回滚方式

删除 `semantics` 键即可回到当前状态；第 6 节的代码收紧可单独回滚（恢复
`date.fromisoformat` 宽松解析），两者互不依赖。回滚后 real↔mock 仍保持镜像，
parity 测试不受影响。