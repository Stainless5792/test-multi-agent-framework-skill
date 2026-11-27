# Review: TASK-MODULE-B-001 / PR #3

- 目标：`feature/module-b-TASK-MODULE-B-001` @ `d634418`（契约 `0341029`、实现 `1359d85`、透传 `41aa630`、复审收口 `d634418`）
- Base：`origin/main` = `586dbbd`（分支已 merge 主线）
- Reviewer：reviewer（只读子 agent）+ orchestrator 复核
- 日期：2026-11-27

## 结论

**APPROVE_WITH_FOLLOWUPS**

契约与提案逐键全等、取数只走 A 的契约、M1–M10 / C1–C10 都是真实用例（reviewer 做过三处变异验证，均变红）、
B 套件 skip 归零。复审提出的 3 个 Medium 已在 `d634418` 收口：契约里「不可能成立的句子」改掉、
上游无 `code` 异常的透传补了定义与用例；夹具耦合按顺序拆成 `TASK-MODULE-B-002` → `TASK-MODULE-A-004`。

## 发现（复审轮，均已处置）

| ID | 级别 | 问题 | 处置 |
|---|---|---|---|
| 1 | Medium | 契约写 `year`/`month`「或缺省 → ValueError」，实际是必填参数，缺参 Python 抛 `TypeError` | **已修**：契约改为「缺省属调用方违约，不在承诺内」，补 `test_monthly_summary_missing_period_argument_is_type_error` |
| 2 | Medium | B 单测夹具硬编码 A 的 mock 路径，删 mock 后 25 errors | **不阻塞本 PR**，拆成 `B-002`（切夹具）→ `A-004`（删 mock），`blocked_by` 已写进 DAG；报告 RISKS 记录实测 `25 errors / 18 passed` |
| 3 | Medium | 上游抛无 `code` 异常时行为未定义、无用例 | **已修**：契约 `error_passthrough` 补「无 `code` 原样透传，不保证 `error_surface`」，补 `test_upstream_exception_without_code_propagates_unchanged` |
| 4–10 | Low | `绝对值之和` 措辞、`from_` 别名与未知 kwargs 未声明、`from exc` 与「不暴露类型」冲突、报告行号漂移、提案 #4/#6 表面矛盾、参数断言写死 | **已修**：契约与提案措辞补齐，参数断言改为遍历契约 `input`，A 契约行号修正为 `:100`/`:111`/`:114` |

## 核对通过项

- 契约 **additive**：新增 `semantics`、`implementation`（含 `requires`）、`error_surface`，删除 `mocks`（路径从未存在、`consumers: []`，提案已受理）。
- 契约 ↔ 提案逐键相等（程序化比对 5 个 YAML 块）。
- 跨模块合规：只调 `list_entries`，未 `import` 或读 `modules/module-a/**`；错误只按 A 的 `error_surface.attributes` 读 `code`，无 `isinstance`、无 `except LedgerError`；测试文本零命中 `LedgerError`。
- 越界 / 共享层：none。7 文件全在 `contracts|modules|tests` 的 module-b 路径与自签报告目录。
- 变异验证：删 `requires` → 2 failed；404→402 → 3 failed；去掉排序 tie-break → 2 failed。

## 门禁验证（`d634418`，orchestrator 复跑）

| 门禁 | 命令 | 结果 |
|---|---|---|
| contract | `bash scripts/contract-check.sh --base origin/main` | PASS exit 0（契约 2 份，失败 0） |
| ownership | `bash scripts/ownership-check.sh origin/main HEAD --owner worker-module-b` | PASS exit 0（7 文件） |
| unit（B） | `uv run pytest tests/modules/module-b tests/contracts/module-b` | PASS exit 0（43 passed, 0 skipped） |
| unit（全仓） | `uv run pytest` | PASS exit 0（157 passed, 1 skipped，skip 属 A-001） |
| lint | `uv run ruff check .` | PASS exit 0 |
| format | `uv run ruff format --check .` | PASS exit 0（9 files） |
| typecheck | `uv run mypy .` | PASS exit 0（9 source files） |
| integration / security | `quality-gates.yaml` 仍 TBD | NOT_CHECKED |
| CI | 仓库无 `.github/workflows/` | NOT_CHECKED |

## 未验证项

| 项 | 原因 | 需要谁执行什么 |
|---|---|---|
| integration / security 门禁 | 命令仍 `TBD`，无跨模块用例与扫描配置 | orchestrator |
| PR #3 CI | 未接线，`statusCheckRollup` 为空 | orchestrator |
| mock 删除后的回归 | 依赖 B-002 先切夹具 | 按 DAG 顺序派发 |

## Orchestrator 处置

复审 3 个 Medium 全部收口或按顺序拆分；10 个 Low 全部处理。合并后按 `B-002` → `A-004` 清理 mock 生命周期。