# Delivery: TASK-MODULE-B-001

- 任务：module-b 报表域首个可交付切片（月度汇总 / 分类统计）
- Owner：`worker-module-b`
- 分支：`feature/module-b-TASK-MODULE-B-001`
- 契约提案：`contracts/module-b/proposals/20261127-semantics.md`（orchestrator 2026-11-27 受理，additive / minor）
- 交付提交：`75dd822`（提案 `9449887`、契约 `f3f78d8`、实现与测试 `1359d85`、合入此前已推送提交的合并 `75dd822`）；本报告随后一笔提交入库
- PR：未开（等 `TASK-MODULE-A-003` 的 `error_surface` 合入后一轮收口）

```
TASK: TASK-MODULE-B-001
BRANCH: feature/module-b-TASK-MODULE-B-001  HEAD: 75dd822
CHANGED:
  contracts/module-b/            v1.yaml（semantics ×2 + implementation + 注释）、CHANGELOG.md、proposals/20261127-semantics.md
  modules/module-b/              report.py（ReportService）
  tests/modules/module-b/        test_report_service.py（M1-M10 / C1-C10）
  tests/contracts/module-b/      test_report_contract.py（结构 / 参数 / 形状 / 错误码 / 入口 / 上游调用形态）
  docs/reviews/deliveries/worker-module-b/  TASK-MODULE-B-001-delivery.md
CONTRACTS: contracts/module-b/v1.yaml（v1，文件名与版本不变）| deltas: proposals/20261127-semantics.md（accepted, additive/minor）
VERIFY:
  uv run pytest tests/modules/module-b tests/contracts/module-b   exit=0  35 passed, 3 skipped
  uv run pytest -q                                                exit=0  144 passed, 4 skipped
  uv run ruff check .                                             exit=0  All checks passed!
  uv run ruff format --check .                                    exit=0  9 files already formatted
  uv run mypy .                                                   exit=0  Success: no issues found in 9 source files
  bash scripts/contract-check.sh --base origin/main               exit=0  契约: 2 份，失败 0
  bash scripts/ownership-check.sh origin/main HEAD --owner worker-module-b  exit=0  全部 7 个文件都在所有权范围内
CROSS-MODULE: 只调 contracts/module-a/v1.yaml 的 list_entries（闭区间 :82、严格日期 :85、category 缺省 "" :47/:99、ACCOUNT_NOT_FOUND :110）；未读 modules/module-a/** 源码；开发期替身为 contracts/module-a/mocks/ledger_service.py
RISKS: ACCOUNT_NOT_FOUND 透传等 A-003 的 error_surface（3 个 skip）；构造函数注入未在契约 implementation 中表达；integration / security 门禁仍 TBD
READY_FOR_REVIEW: no
```

## 契约 diff（相对 `origin/main`）

`contracts/module-b/v1.yaml`：+45 / −9，全部为 additive。

```diff
@@ monthly_summary
     side_effects: none
+    semantics:
+      period_window / year_month / income / expense / net / period_field /
+      empty_result / validation_order / error_passthrough / upstream_call
@@ category_breakdown
     side_effects: none
+    semantics:
+      range / date_input / validation_order / scope / grouping /
+      total / order / empty_result / error_passthrough / upstream_call
@@ types
-    period: { type: string }        # YYYY-MM
+    period: { type: string }        # YYYY-MM，见 monthly_summary.semantics.period_field
+    income: { type: integer }       # 非负：income amount 绝对值之和
+    expense: { type: integer }      # 非负：expense amount 绝对值之和
+    net: { type: integer }          # 有符号：income - expense
@@ error_codes（仅注释）
@@ 新增顶层 implementation
+implementation:
+  module_path: modules/module-b
+  factory: "report:ReportService"
+  bootstrap: sys_path
```

语义逐条与提案 YAML fence 比对：`methods` / `semantics` / `implementation` / `types` /
`error_codes` 完全相等（脚本断言，exit 0）。

## 实现

`modules/module-b/report.py`

- `ReportService(ledger)`：上游只经构造注入的 `ledger.list_entries` 访问，不 import module-a。
- `monthly_summary`：自然月闭区间 → 上游 `list_entries(account_id, **{"from": ..., "to": ...})`；
  `income` / `expense` 为非负合计，`net = income - expense`；`period` 4 位年 + 2 位月零填充。
- `category_breakdown`：先校验日期形态与 `from > to`，再取数；只聚合 `expense`，
  `category` 原值分组（含 `""`），`total` 降序 + `category` 码点升序。
- 校验顺序：参数形态 → 参数范围 → 上游取数；非法输入不触达上游（测试用会抛错的 ledger 锁死）。
- `ACCOUNT_NOT_FOUND` 透传**未实现**：A-003 合入前不写 `getattr(exc, "code", ...)`，上游异常原样传播；
  契约测试与 M8/C8 标 `skip`，`READY_FOR_REVIEW: no`。

## 测试清单

`tests/contracts/module-b/test_report_contract.py`（11 个，1 skip）

| 用例 | 断言 |
|---|---|
| `test_contract_declares_accepted_semantics` | 契约含受理的语义键与 `implementation` 三字段 |
| `test_entrypoint_resolves_and_methods_are_callable` | 按 `implementation` 解析、实例化、两个方法 callable |
| `test_method_parameters_match_contract` | `account_id` / `year` / `month` 必填；`category_breakdown` 接受 `**{"from": ...}` |
| `test_category_breakdown_requires_from_and_to` | 缺 `from` 或 `to` → `ValueError` |
| `test_monthly_summary_shape` | 返回键集合与值精确匹配 |
| `test_category_breakdown_shape` | `items` 元素键集合 `{category, total}`，income 不计入 |
| `test_invalid_period_code` | `INVALID_PERIOD` / http 400 / retryable false |
| `test_invalid_date_range_code` | `INVALID_DATE_RANGE` / http 400 / retryable false |
| `test_validation_order_does_not_touch_upstream` | 非法参数不调用 ledger |
| `test_upstream_call_uses_contract_field_names` | 上游调用键恰好 `account_id` / `from` / `to`，无 `limit` |
| `test_account_not_found_passthrough` | **skip**：等待 A-003 契约 `error_surface` 合并 |

`tests/modules/module-b/test_report_service.py`（27 个，2 skip）：M/C 向量见下表。

### M/C 向量覆盖

| 向量 | 用例 | 结果 |
|---|---|---|
| M1 | `test_m1_monthly_summary_counts_only_natural_month` | pass |
| M2 | `test_m2_leap_day_is_included` | pass |
| M3 | `test_m3_empty_account_returns_zeros` | pass |
| M4 | `test_m4_income_only` | pass |
| M5 | `test_m5_period_out_of_range`（4 组参数） | pass |
| M6 | `test_m6_non_integer_period_is_value_error`（4 组参数） | pass |
| M7 | `test_m7_invalid_period_precedes_account_lookup` | pass |
| M8 | `test_m8_unknown_account` | **skip**（A-003） |
| M9 | `test_m9_period_year_is_zero_padded` | pass |
| M10 | `test_m10_cross_year_entries_do_not_leak` | pass |
| C1 | `test_c1_groups_expense_by_category` | pass |
| C2 | `test_c2_single_day_range` | pass |
| C3 | `test_c3_invalid_range_precedes_account_lookup` | pass |
| C4 | `test_c4_non_yyyy_mm_dd_is_value_error`（2 组参数） | pass |
| C5 | `test_c5_income_only_yields_empty_items` | pass |
| C6 | `test_c6_missing_category_is_its_own_bucket` | pass |
| C7 | `test_c7_ties_sort_by_category_code_point` | pass |
| C8 | `test_c8_unknown_account` | **skip**（A-003） |
| C9 | `test_c9_range_includes_both_endpoints` | pass |
| C10 | `test_c10_empty_account_yields_empty_items` | pass |

skip 共 3 个，理由均为「等待 A-003 契约 error_surface 合并」。

## 验证（实跑，退出码为真）

| 命令 | 退出码 | 关键输出 |
|---|---|---|
| `uv run pytest tests/modules/module-b tests/contracts/module-b` | 0 | `35 passed, 3 skipped` |
| `uv run pytest -q` | 0 | `144 passed, 4 skipped` |
| `uv run ruff check .` | 0 | `All checks passed!` |
| `uv run ruff format --check .` | 0 | `9 files already formatted` |
| `uv run mypy .` | 0 | `Success: no issues found in 9 source files` |
| `bash scripts/contract-check.sh --base origin/main` | 0 | `契约: 2 份，失败 0` |
| `bash scripts/ownership-check.sh origin/main HEAD --owner worker-module-b` | 0 | 7 个文件全部在所有权范围内 |
| 提案 ↔ 契约 YAML 逐键比对 | 0 | methods / semantics / implementation / types / error_codes 完全相等 |

## CROSS-MODULE

只依赖 `contracts/module-a/v1.yaml`：

- `list_entries.semantics.range`（`:82`，闭区间）→ `monthly_summary.period_window`、`category_breakdown.range`
- `list_entries.semantics.date_input`（`:85`，严格 `YYYY-MM-DD`）→ 日期校验同口径
- `record_entry.semantics.amount`（`:46`，正整数）→ `total` 为正值
- `types.Entry.category`（`:47`、`:99`，缺省 `""`）→ `""` 作为合法分组
- `error_codes.ACCOUNT_NOT_FOUND`（`:110`）/ `INVALID_DATE_RANGE`（`:113`）→ 透传与错误码取值
- 调用形态按受理裁定：`list_entries(account_id=..., **{"from": ..., "to": ...})`，不依赖 `from_` 别名

未读 `modules/module-a/**` 源码；开发期替身为 `contracts/module-a/mocks/ledger_service.py`。

## 未验证项与偏差

| 项 | 说明 | 需要谁做什么 |
|---|---|---|
| `ACCOUNT_NOT_FOUND` 透传 | A-003 的 `error_surface` 未合入；当前上游异常原样传播，契约行为未实现 | 等 A-003 合入后实现重包并打开 3 个 skip |
| 上游其他业务错误码 | 契约写「抛 RuntimeError」，与透传同批实现 | 同上 |
| 构造函数注入 | 契约 `implementation` 只声明 factory，未声明构造参数；`ReportService(ledger)` 需要下游注入上游实现，`ReportService()` 会 `TypeError` | orchestrator 决定是否给 `implementation` 增加构造约定或 loader 策略（属契约变更） |
| `mocks` 路径 | 契约仍指向 `contracts/module-b/mocks/report_service.py`，当前无消费者、未提供该 mock | 有消费者前补，或由 orchestrator 调整契约 |
| integration / security | `.agent/quality-gates.yaml` 仍为 TBD；cross-module 用例未排期 | orchestrator |
| CI | 仓库无 `.github/workflows/`，PR 未开 | orchestrator 接线后重跑 |
| mock 生命周期 | `contracts/module-a/mocks/ledger_service.py` 与真实实现并存 | B 合入后按 `agent-protocol.md:34` 由 orchestrator 安排删除 |

READY_FOR_REVIEW: no（等 A-003 的 `error_surface`）