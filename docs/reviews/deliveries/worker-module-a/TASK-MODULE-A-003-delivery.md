# Delivery: TASK-MODULE-A-003

- 任务：module-a 契约补 `error_surface` 与 `from` 调用形态
- Owner：worker-module-a
- 分支：`feature/module-a-TASK-MODULE-A-003`
- 交付代码：`f9c27dd`（base `origin/main` @ `4653af7`）
- PR：#2
- 报告来源：**worker-module-a 自签**；本文件随其后一笔 docs 提交入库
  （`git log -- docs/reviews/deliveries/worker-module-a/`）。

```
TASK: TASK-MODULE-A-003
BRANCH: feature/module-a-TASK-MODULE-A-003   HEAD: f9c27dd
CHANGED:
  contracts/module-a/v1.yaml                     error_surface + list_entries.semantics.from_parameter
  contracts/module-a/proposals/20261127-error-surface.md   预批提案正文（accepted）
  contracts/module-a/CHANGELOG.md                第四条 additive 记录
  modules/module-a/README.md                     「异常口径」补「类名不是契约事实」
  tests/contracts/module-a/test_ledger_contract.py   3 条新断言（real + mock）
  docs/reviews/deliveries/worker-module-a/TASK-MODULE-A-003-delivery.md   本报告
CONTRACTS: contracts/module-a/v1.yaml（v1，文件名与版本不变）| deltas: 20261127-error-surface.md
           （accepted 预批，additive / minor，无 breaking）
VERIFY:
  uv run pytest tests/contracts/module-a tests/modules/module-a   exit=0  114 passed, 1 skipped
  uv run ruff check .                                             exit=0  All checks passed!
  uv run ruff format --check .                                    exit=0  6 files already formatted
  uv run mypy .                                                   exit=0  Success: no issues found in 6 source files
  bash scripts/contract-check.sh --base origin/main               exit=0  契约: 2 份，失败 0
  bash scripts/ownership-check.sh origin/main HEAD --owner worker-module-a  exit=0  6 个文件全部在所有权范围内
CROSS-MODULE: 消费方 worker-module-b；只依赖 contracts/module-a/v1.yaml，未 import 对方代码
RISKS: integration / security 门禁仍 TBD；CI 未接线；B 侧不得按异常类名分支
READY_FOR_REVIEW: YES
```

> ownership 的 6 个文件 = 5 个交付文件（`v1.yaml`、`CHANGELOG.md`、提案、README、
> 契约测试）+ 本报告。报告写入前同一命令为 5 个文件。

## 契约新增键说明

| 键 | 值 / 语义 | 对消费者的含义 |
|---|---|---|
| `error_surface.mechanism` | `exception` | 业务失败以异常交付，不用返回值编码 |
| `error_surface.attributes` | `[code, http_status, retryable]` | 异常对象必须暴露这三个属性 |
| `error_surface.code_domain` | `error_codes` | `code` 取值域就是本契约 `error_codes` 的键，不得新增码 |
| `error_surface.notes` | 「异常类名不是契约事实……」 | 消费者不得依赖类型名或继承关系 |
| `list_entries.semantics.from_parameter` | 「`**{'from': ...}` 与 `from_` 等价」 | 两种调用形态必须行为一致 |

`error_surface` 与 `implementation` 同级（顶层）；`from_parameter` 加在既有
`list_entries.semantics` 内，其余语义未动。`v1.yaml` diff 为 +9 行、0 删除。

## 新增测试（5 条执行）

| 测试 | 断言要点 |
|---|---|
| `test_contract_declares_error_surface` | `mechanism == "exception"`；`attributes` 集合等于三个属性；`code_domain == "error_codes"` 且该表存在于契约 |
| `test_business_error_exposes_contract_attributes[real]` | 触发 `ACCOUNT_NOT_FOUND`，`hasattr` 校验三属性；`code` 在 `error_codes` 键内；`http_status` / `retryable` 与 `error_codes[code]` 一致；**不用 `isinstance`** |
| `test_business_error_exposes_contract_attributes[mock]` | 同上，跑 mock 实现（类名与真实实现不同，验证只依赖属性） |
| `test_list_entries_from_keyword_and_alias_are_equivalent[real]` | `**{"from": "2026-01-02"}` 与 `from_="2026-01-02"` 返回完全相同，范围为 `2026-01-02..03` |
| `test_list_entries_from_keyword_and_alias_are_equivalent[mock]` | 同上，跑 mock |

配套：`test_contract_declares_semantics_for_stateful_methods` 的 `list_entries`
键集合（`==` 相等断言）加入 `from_parameter`，契约被塞入未提案键时会红。

## 实现零改动（验证命令与输出）

```
$ git diff --name-only origin/main HEAD -- modules/module-a/ledger.py contracts/module-a/mocks/ledger_service.py
（无输出）
```

`git diff --stat origin/main HEAD` 不含这两个文件；本轮只补契约声明与测试。

## `git diff --stat origin/main HEAD`

```
 contracts/module-a/CHANGELOG.md                    |   5 +-
 contracts/module-a/proposals/20261127-error-surface.md | 103 +++++++++++++
 contracts/module-a/v1.yaml                         |   9 ++
 modules/module-a/README.md                         |   8 +-
 tests/contracts/module-a/test_ledger_contract.py   |  53 +++++++++++
 5 files changed, 175 insertions(+), 3 deletions(-)
```

## CROSS-MODULE

- 给 `worker-module-b`：按 `code` / `http_status` / `retryable` 读异常、按
  `code_domain` 校验取值；不要写 `except LedgerError` / `isinstance`；`from` 两种写法等价。
- 依赖对方：无；未触碰 `modules/module-b/**`、`contracts/module-b/**`。

## 未验证项与风险

| 项 | 说明 | 需要谁做什么 |
|---|---|---|
| integration / security 门禁 | `.agent/quality-gates.yaml` 仍为 `TBD` | orchestrator |
| CI 是否绿 | 仓库无 `.github/workflows/`，PR #2 `statusCheckRollup` 为空 | orchestrator 接线后重跑 |
| B 侧按类名分支的惯性 | mock 与真实实现异常类同名不同身份，`except LedgerError` 会失配 | B-001 实现时按 `code` 分支 |
| base 前移 | 开工后 `origin/main` 由 62e61cd 前移到 4653af7，已 fast-forward 对齐 | 合并前跑 `merge-ready.sh TASK-MODULE-A-003` |

READY_FOR_REVIEW: YES