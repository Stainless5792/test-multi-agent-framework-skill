# Review: TASK-MODULE-A-003 / PR #2

- 目标：`feature/module-a-TASK-MODULE-A-003` @ `e3cba77`（`f9c27dd` 契约提交 + `e3cba77` 自签报告）
- Base：`origin/main` = `872881d`（merge-base `4653af7`）
- Reviewer：reviewer（只读子 agent）+ orchestrator 复核
- 日期：2026-11-27

## 结论

**APPROVE_WITH_FOLLOWUPS**

契约与预批提案逐字一致，测试会真变红（reviewer 用临时副本做过变异验证），实现零改动。
唯一 Medium 是 `ownership-check.sh` 的两点比较在 base 前移后会把主线提交算成「本分支删除」——
已由 orchestrator 改成 merge-base 语义，复跑转绿。

## 发现

| ID | 级别 | 问题 | 处置 |
|---|---|---|---|
| 1 | Medium | `ownership-check.sh` 用 `git diff base..head`：base 前移后把主线新提交判成本分支的删除 | **已修**：脚本内部改用 `git merge-base base head`；`merge-ready.sh` 同时改为使用编排者这份门禁脚本（worker 分支里的 `scripts/` 可能是旧版） |
| 2 | Low | `error_surface.attributes` 用 `http_status`，`error_codes` 列名是 `http`，契约没写这条映射，测试却断言相等 | 后续提案补一句显式映射；本轮预批形态不含，不属越界 |
| 3 | Low | `mechanism: exception` + `code_domain: error_codes` 易被读成「所有异常都带 code」，而各方法的 `ValueError` 不在其中 | 与 #2 同一个后续提案补「`ValueError` 不在 mechanism / code_domain 内」 |
| 4 | Low | `contract-format.md` 未登记 `error_surface` | **已修**：格式文档补字段示例 + 一节定义（含「类名不是契约事实」与 `http_status`↔`http` 措辞提醒） |
| 5 | Low | `test_business_error_exposes_contract_attributes` 只断言 `code ∈ code_domain`，未断言该场景应为 `ACCOUNT_NOT_FOUND` | 可选加强；同类断言在 `tests/modules/module-a/` 已覆盖，不构成漏测 |

## 契约与边界

- 兼容性：**additive**。`v1.yaml` 只新增顶层 `error_surface` 与 `list_entries.semantics.from_parameter`；`contract-check --base origin/main` 与 `--base 4653af7` 均 exit 0。
- 提案一致：`error_surface` 四键与 `from_parameter` 文本与 `proposals/20261127-error-surface.md` 逐字相等（程序化比对）。
- 测试强度：无 `isinstance` / `except LedgerError`；`[real]` / `[mock]` 各自独立跑；删 `from_parameter`、改 mock 属性名、改 `mechanism` 三种变异均能让对应测试变红。
- 实现零改动：`git diff origin/main HEAD -- modules/module-a/ledger.py contracts/module-a/mocks/` 为空。
- 越界：none。6 文件 = `contracts/module-a/**`(3) + `tests/contracts/module-a/**`(1) + `README.md`(1) + 自签报告(1，预留规则)。
- 共享层：none。

## 门禁验证（`e3cba77`，orchestrator 复跑）

| 门禁 | 命令 | 结果 |
|---|---|---|
| contract | `bash scripts/contract-check.sh --base origin/main` | PASS exit 0（契约 2 份，失败 0） |
| ownership | `bash scripts/ownership-check.sh origin/main HEAD --owner worker-module-a` | PASS exit 0（6 文件；修脚本后） |
| lint | `uv run ruff check .` | PASS exit 0 |
| format | `uv run ruff format --check .` | PASS exit 0（6 files） |
| typecheck | `uv run mypy .` | PASS exit 0（6 source files） |
| unit | `uv run pytest tests/contracts/module-a tests/modules/module-a` | PASS exit 0（114 passed, 1 skipped） |
| integration / security / CI | `quality-gates.yaml` 仍 TBD、无 workflow | NOT_CHECKED |

## 未验证项

| 项 | 原因 | 需要谁执行什么 |
|---|---|---|
| integration / security | 门禁命令仍 TBD，仓库无对应用例与扫描配置 | orchestrator |
| PR #2 CI | `statusCheckRollup` 为空，仓库无 `.github/workflows/` | orchestrator 接线 |
| 提案 X1 溯源 | 提案写「来源 B-001 评审」，但 B-001 尚未进入评审，`docs/reviews/` 下没有该文件 | B-001 评审后补引用，或改引用本记录 |

## Orchestrator 处置

- 发现 1（Medium）已修脚本并复跑；同时把 `merge-ready.sh` 改成用编排者自己的门禁脚本，避免 worker 分支里的旧副本影响判定。
- 发现 4 已改 `docs/contracts/contract-format.md`。
- 发现 2 / 3 记为 A 的后续提案（可与删除 mock、A-002 合并成一轮），不阻塞本 PR。
- 发现 5 不阻塞。