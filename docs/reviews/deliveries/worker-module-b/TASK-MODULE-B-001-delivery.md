# Delivery: TASK-MODULE-B-001

- 任务：module-b 报表域首个可交付切片（月度汇总 / 分类统计）
- Owner：`worker-module-b`
- 分支：`feature/module-b-TASK-MODULE-B-001`
- 契约提案：`contracts/module-b/proposals/20261127-semantics.md`（orchestrator 2026-11-27 受理，additive / minor；收口轮两项变更预批）
- 上游：PR #2 → `75dd608`，`contracts/module-a/v1.yaml` 提供 `error_surface` 与 `list_entries.semantics.from_parameter`；主线 `aa89a36` 已 merge（`adbefb0`）
- 交付提交：`008009b`（复审收口；实现与测试初版 `1359d85`、透传收口 `41aa630`、契约 `1fe31dd`）；本报告随后一笔提交入库
- PR：[#3](https://github.com/Stainless5792/test-multi-agent-framework-skill/pull/3)（`feat(module-b): report domain per contract v1 (TASK-MODULE-B-001)`）

```
TASK: TASK-MODULE-B-001
BRANCH: feature/module-b-TASK-MODULE-B-001  HEAD: 008009b
CHANGED:
  contracts/module-b/            v1.yaml（semantics ×2、implementation + requires、error_surface、删 mocks）、
                                 CHANGELOG.md、proposals/20261127-semantics.md（受理记录 + 收口轮）
  modules/module-b/              report.py（ReportService + 上游错误翻译）
  tests/modules/module-b/        test_report_service.py（M1-M10 / C1-C10，0 skip）
  tests/contracts/module-b/      test_report_contract.py（结构 / error_surface / requires 入口 / 透传 / 形状）
  docs/reviews/deliveries/worker-module-b/  TASK-MODULE-B-001-delivery.md
CONTRACTS: contracts/module-b/v1.yaml（v1，文件名与版本不变）| deltas: proposals/20261127-semantics.md（accepted, additive/minor）
VERIFY:
  uv run pytest tests/modules/module-b tests/contracts/module-b   exit=0  43 passed, 0 skipped
  uv run pytest -q                                                exit=0  157 passed, 1 skipped（A 的既有 skip）
  uv run ruff check .                                             exit=0  All checks passed!
  uv run ruff format --check .                                    exit=0  9 files already formatted
  uv run mypy .                                                   exit=0  Success: no issues found in 9 source files
  bash scripts/contract-check.sh --base origin/main               exit=0  契约: 2 份，失败 0
  bash scripts/ownership-check.sh origin/main HEAD --owner worker-module-b  exit=0  7 个文件全部在所有权范围内
  提案 ↔ v1.yaml 逐键断言（含 requires / error_surface / mocks 缺席）             exit=0  完全相等
  grep -rn "skip" tests/modules/module-b tests/contracts/module-b  exit=1（无匹配）  B 套件 skip 归零
CROSS-MODULE: 只调 contracts/module-a/v1.yaml 的 list_entries（range :82、date_input :85、from_parameter :86、amount :46、category :47/:100、ACCOUNT_NOT_FOUND :111、INVALID_DATE_RANGE :114、error_surface :118-122）；未读 modules/module-a/** 源码
RISKS: integration / security 门禁仍 TBD；CI 未接线；A 的 mock 与真实实现并存，待 orchestrator 安排删除
READY_FOR_REVIEW: YES
```

## 收口轮契约 diff（相对 `origin/main`）

`contracts/module-b/v1.yaml`：+56 / −11，全部 additive；本轮新增两块、删一节。

```diff
@@ error_codes 之后
+error_surface:
+  mechanism: exception
+  attributes: [code, http_status, retryable]
+  code_domain: error_codes
+  notes: "异常类名不是契约事实，消费者不得依赖类型名或继承关系"
@@ implementation
   module_path: modules/module-b
   factory: "report:ReportService"
   bootstrap: sys_path
+  requires:
+    - name: ledger
+      from: contracts/module-a/v1.yaml
+      description: "构造时注入的上游实例，按该契约的 implementation 字段解析"
@@ 文件末尾
-mocks:
-  path: contracts/module-b/mocks/report_service.py
```

`mocks` 已删除。理由写入 `CHANGELOG.md`：原路径指向从未存在的文件，B 无消费者，
按 `agent-protocol.md:32-34` 不在没有 parity 测试的前提下保留第二份实现；
出现消费者时再按契约提供 mock + parity。

## `requires` 的解析方式

入口契约测试 `test_entrypoint_resolves_with_requires`：

1. 读 `contracts/module-b/v1.yaml`，取 `implementation.requires[0]`
   （`name=ledger`、`from=contracts/module-a/v1.yaml`）。
2. 读该 `from` 指向的 A 契约，取 `implementation` 的 `module_path` / `factory`。
3. 把 `module_path` 加入 `sys.path`，按 `factory` 的 `<import 名>:<类名>` 解析并
   实例化上游。
4. `ReportService(ledger=<上游实例>)`，断言两个方法 callable。

测试只读两份契约的 `implementation` 字段，不读 A 的源码，不写死模块名。

## `ACCOUNT_NOT_FOUND` 透传

实现 `_raise_upstream_error(exc)`：

- `code = getattr(exc, "code", None)`；没有 `code` 的原样重抛（不是业务错误）。
- `code == "ACCOUNT_NOT_FOUND"` → `ReportError("ACCOUNT_NOT_FOUND", str(exc))`，
  `http_status=404`、`retryable=False`，取自 B 自己的 `error_codes`。
- 其余带 `code` 的业务错误 → `RuntimeError`，消息带原错误码，不新增契约错误码。
- 不 `isinstance`、不 `except` 具体上游类、不 import A 的异常类；测试断言里没有
  A 的异常类名（`grep -rn "LedgerError" tests/...` 无匹配）。

## Skip 归零证明

收口前 3 个 skip：`test_account_not_found_passthrough`、`test_m8_unknown_account`、
`test_c8_unknown_account`。现在：

```
$ uv run pytest tests/modules/module-b tests/contracts/module-b -v
tests/contracts/module-b/test_report_contract.py ................        [100%]
============================== 43 passed in 0.14s ==============================

$ grep -rn "skip" tests/modules/module-b tests/contracts/module-b
（无匹配，exit 1）
```

全仓 `uv run pytest -q` 为 `157 passed, 1 skipped`；唯一 skip 是 module-a 的既有用例。

## 测试清单

`tests/contracts/module-b/test_report_contract.py`（16 个，0 skip）

| 用例 | 断言 |
|---|---|
| `test_contract_declares_accepted_semantics` | 语义键、`implementation` 三字段、`requires` 指向 A 契约 |
| `test_contract_declares_error_surface` | `mechanism` / `attributes` / `code_domain`，且 `error_codes` 表存在 |
| `test_entrypoint_resolves_with_requires` | 按 `requires` 解析上游并注入，两个方法 callable |
| `test_method_parameters_match_contract` | 遍历契约 `input`，断言每个参数名可被接收；`account_id` 由签名保证必填；`from` 经 `**kwargs` 接收 |
| `test_monthly_summary_missing_period_argument_is_type_error` | 缺 `year` / `month` → `TypeError`（不是 `ValueError`） |
| `test_category_breakdown_from_alias_and_unknown_kwarg` | `from_` 与 `**{"from": ...}` 等价；未知关键字参数 → `TypeError` |
| `test_category_breakdown_requires_from_and_to` | 缺 `from` / `to` → `ValueError` |
| `test_monthly_summary_shape` | 返回键集合与值精确匹配 |
| `test_category_breakdown_shape` | `items` 键集合 `{category, total}`，income 不计入 |
| `test_invalid_period_code` | `INVALID_PERIOD` / 400 / false |
| `test_invalid_date_range_code` | `INVALID_DATE_RANGE` / 400 / false |
| `test_validation_order_does_not_touch_upstream` | 非法参数不调用 ledger |
| `test_upstream_call_uses_contract_field_names` | 上游调用键恰好 `account_id` / `from` / `to`，无 `limit` |
| `test_account_not_found_passthrough` | 上游 `code=ACCOUNT_NOT_FOUND` → B 的 `code=ACCOUNT_NOT_FOUND` / 404 / false |
| `test_other_upstream_business_code_is_runtime_error` | 其他业务码 → `RuntimeError`，消息含原码 |
| `test_upstream_exception_without_code_propagates_unchanged` | 无 `code` 的上游异常原样冒泡，类型与实例不变 |

`tests/modules/module-b/test_report_service.py`（27 个，0 skip）

### M/C 向量覆盖

| 向量 | 用例 | 结果 |
|---|---|---|
| M1 | `test_m1_monthly_summary_counts_only_natural_month` | pass |
| M2 | `test_m2_leap_day_is_included` | pass |
| M3 | `test_m3_empty_account_returns_zeros` | pass |
| M4 | `test_m4_income_only` | pass |
| M5 | `test_m5_period_out_of_range`（4 组） | pass |
| M6 | `test_m6_non_integer_period_is_value_error`（4 组） | pass |
| M7 | `test_m7_invalid_period_precedes_account_lookup` | pass |
| M8 | `test_m8_unknown_account` | pass（原 skip） |
| M9 | `test_m9_period_year_is_zero_padded` | pass |
| M10 | `test_m10_cross_year_entries_do_not_leak` | pass |
| C1 | `test_c1_groups_expense_by_category` | pass |
| C2 | `test_c2_single_day_range` | pass |
| C3 | `test_c3_invalid_range_precedes_account_lookup` | pass |
| C4 | `test_c4_non_yyyy_mm_dd_is_value_error`（2 组） | pass |
| C5 | `test_c5_income_only_yields_empty_items` | pass |
| C6 | `test_c6_missing_category_is_its_own_bucket` | pass |
| C7 | `test_c7_ties_sort_by_category_code_point` | pass |
| C8 | `test_c8_unknown_account` | pass（原 skip） |
| C9 | `test_c9_range_includes_both_endpoints` | pass |
| C10 | `test_c10_empty_account_yields_empty_items` | pass |

## 验证（实跑，退出码为真）

| 命令 | 退出码 | 关键输出 |
|---|---|---|
| `uv run pytest tests/modules/module-b tests/contracts/module-b` | 0 | `43 passed, 0 skipped` |
| `uv run pytest -q` | 0 | `157 passed, 1 skipped` |
| `uv run ruff check .` | 0 | `All checks passed!` |
| `uv run ruff format --check .` | 0 | `9 files already formatted` |
| `uv run mypy .` | 0 | `Success: no issues found in 9 source files` |
| `bash scripts/contract-check.sh --base origin/main` | 0 | `契约: 2 份，失败 0` |
| `bash scripts/ownership-check.sh origin/main HEAD --owner worker-module-b` | 0 | 7 个文件全部在所有权范围内 |
| 提案 ↔ 契约 YAML 逐键比对 | 0 | methods / implementation / error_surface / types / error_codes 相等，mocks 缺席 |
| `grep -rn "skip" tests/modules/module-b tests/contracts/module-b` | 1 | 无匹配（预期） |

## CROSS-MODULE

只依赖 `contracts/module-a/v1.yaml`：

- `list_entries.semantics.range`（`:82`）→ 自然月与分类区间都用闭区间
- `list_entries.semantics.date_input`（`:85`）→ 严格 `YYYY-MM-DD`
- `list_entries.semantics.from_parameter`（`:86`）→ 统一 `**{"from": ...}` 调用
- `record_entry.semantics.amount`（`:46`）→ `total` 为正
- `types.Entry.category`（`:47`、`:100`）→ `""` 是合法分组
- `error_codes.ACCOUNT_NOT_FOUND`（`:111`）、`INVALID_DATE_RANGE`（`:114`）→
  B 的错误码取值与 http/retryable 与 A 一致
- `error_surface.attributes`（`:118-122`）→ 只按 `code` / `http_status` / `retryable`
  读取，不依赖类名或继承关系

未读 `modules/module-a/**` 源码；单元测试用 A 的 mock，契约入口测试按 A 的
`implementation` 字段解析真实实现。

## 复审收口（PR #3，APPROVE_WITH_FOLLOWUPS）

| 项 | 处置 |
|---|---|
| M1 契约写了不可能成立的句子 | `year_month` 删「或缺省」，注明缺省由 Python 抛 `TypeError`；新增 `test_monthly_summary_missing_period_argument_is_type_error` |
| M3 无 `code` 异常行为未定义 | `error_passthrough` 补「无 `code` 原样透传，不保证满足 `error_surface`」；新增 `test_upstream_exception_without_code_propagates_unchanged` |
| M2 mock 路径顺序问题 | 本轮不改夹具，已单立 `TASK-MODULE-B-002`；实测证据见下 |
| L4 `from_` 别名 / 未知参数 | 契约增 `from_parameter`；新增 `test_category_breakdown_from_alias_and_unknown_kwarg` |
| L5 「绝对值」措辞 | `types` 注释统一为「amount 之和」 |
| L6 失效的 VERIFY 引用 | CHANGELOG 与提案改为指向本报告验证表 |
| L7 参数名写死 | 改为遍历契约 `input`；必填强度按实际：`account_id` 由签名保证，`from`/`to` 由运行时 `ValueError` 覆盖 |
| L8 `__cause__` 语义 | `error_passthrough` 区分「不对消费者暴露类型做判断」与「traceback 保留原因」，注明 `__cause__` 仅诊断；实现不改 |
| L9 行号与 SHA | 按 A 契约实号修正；交付提交改为 `1359d85`（初版）+ `41aa630`（透传）+ `008009b`（复审） |
| L10 #4 / #6 表面冲突 | #4 后补「仅禁依赖 mock 的猜法；A-003 落地后按契约 `attributes` 读 `code` 允许」 |

M2 实测证据：把工作树复制到临时目录、只删除
`contracts/module-a/mocks/ledger_service.py`，再跑 B 套件，结果为
`25 errors / 18 passed`（exit 1）；25 个 error 全部落在
`tests/modules/module-b/test_report_service.py` 的 mock 夹具。因此删除 A 的 mock
之前必须先完成 `TASK-MODULE-B-002`（夹具切到真实实现），否则这 25 个用例必红。

## 未验证项与偏差

| 项 | 说明 | 需要谁做什么 |
|---|---|---|
| integration / security | `.agent/quality-gates.yaml` 仍为 TBD；跨模块集成用例未排期 | orchestrator |
| CI | 仓库无 `.github/workflows/`；PR 已开但 CI 未接线 | orchestrator 接线后重跑 |
| mock 生命周期 | `contracts/module-a/mocks/ledger_service.py` 与真实实现并存；实测删 mock 后 B 套件 25 errors / 18 passed | **删除 mock 前必须先做 `TASK-MODULE-B-002`**（夹具切真实实现），再由 A-004 删 mock |
| B 的 `mocks` | 已删除，B 无消费者；未来出现消费者时补 mock + parity | orchestrator / 后续任务 |
| 错误信息稳定性 | `message` 原样携带上游文本，仅供诊断，不作契约承诺 | 消费方不得按 message 分支 |

READY_FOR_REVIEW: YES