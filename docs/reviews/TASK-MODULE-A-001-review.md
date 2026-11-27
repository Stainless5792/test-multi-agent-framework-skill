# Review: TASK-MODULE-A-001 / PR #1

- 目标：`feature/module-a-TASK-MODULE-A-001` @ `d7d7588`（worktree `worktrees/worker-module-a`）
- Base：`origin/main` = `34629f6`
- Reviewer：reviewer（只读子 agent，两轮）+ orchestrator（黑盒复核）
- 日期：2026-11-27

## 结论

**APPROVE_WITH_FOLLOWUPS**

首轮判「要求修改」的原因是契约留白（实现入口、可观察语义、`create_account` 语义都没写进契约），
不是代码缺陷。三轮返工后：入口与四个方法的 `semantics` 全部落契约、日期收紧、parity 与
跨币种重名有测试锁死、控制字符口径与实现对齐、心跳不再入库、自签交付报告数字与实跑一致。
契约中每一处新内容都能在三份 accepted 提案里找到出处，无「契约外新事实」。

## 轮次记录

| 轮 | SHA | 结论 | 要点 |
|---|---|---|---|
| 首轮 | `e87b436` | 要求修改 | 4 条 acceptance 全中、6 码可达、零越界；F1 入口未声明、F2 语义留白（High），F3 mock 无 parity，F4 心跳缺失，F5 报告数字错，F6 自写 YAML 解析器，F7 日期宽松，F8 Worker 无处落盘 |
| 返工 | `54ccdd5` | — | 两份提案 → 受理 → `implementation` + 3×`semantics` 落契约；F7 收紧；parity 10 场景 |
| 合并与 F6 | `bb02ee9` | — | merge main、删 129 行解析器改 `yaml.safe_load`、提案 3 |
| 提案 3 | `bc72b10` | 可批准（带 followup） | `create_account.semantics` 落契约；F1/F2/F9/F7/F3/F4/F6/F5 全部关闭；新增 F10（Medium）、F11–F17（Low） |
| 收口 | `d7d7588` | 可批准（带 followup） | F10 控制字符改 `unicodedata.category == "Cc"`（real+mock 同步 + parity）、F11 删 `CUC`/`SLL`、F12 键集合断言改相等、F13 跨币种重名用例、F15 报告补 `VERIFY` |

## 遗留 followup（不阻塞合并）

| ID | 级别 | 问题 | 处置 |
|---|---|---|---|
| F14 | Low | `contract-format.md` 未收录 `implementation`；`contracts/_schema.json` 不存在但文档要求据此校验 | **已处理**：字段说明与迁移路径补进文档，schema 一节改为如实描述（schema 补齐前不得声称已校验） |
| F16 | Low | `generated_fields: id 为 uuid4` 写进 `stability: stable` 契约，换 ID 形态即 breaking | **维持现状**：这是当前事实，换形态本来就该 major |
| F17 | Low | 历史提交 `9d4b86f` 曾把心跳文件入库（终态已删） | 合并用 merge commit 或 squash，不单独 cherry-pick 该提交 |
| — | Low | 契约写「现行 ISO 4217」，实现是 v1 快照，标准更新仍会漂移 | 需要时另开提案把「快照版本 / 生效日期」写进契约 |
| — | Low | `unicodedata` 只判 `Cc`，`Cf`（零宽字符）仍可入库，契约只说「控制字符」 | 纳入 `Cf` 属语义扩展，走提案 |
| — | Low | `types-PyYAML` 缺失，`yaml.safe_load` 处靠 `# type: ignore[import-untyped]` | 加 stub 后删 ignore（orchestrator，`pyproject.toml`） |
| — | — | integration / security 门禁为 `TBD`；CI 未接线 | orchestrator 待办，合并证据里记 NOT_CHECKED，不得默认为通过 |

## 契约与边界

- 契约兼容性：**additive**。`v1.yaml` 只新增 `implementation`、四个方法的 `semantics`、`Entry` 缺省值注释；`input`/`output`/`errors`/`types` 的类型、必填性、枚举均未变。`contract-check.sh` exit 0，`--base origin/main` 同。
- 版本自洽：`contract.version` 仍 `v1`、文件名未变、`CHANGELOG.md` 三条 additive + 唯一性冻结注记。
- 提案覆盖度：`implementation`、`record_entry`/`get_balance`/`list_entries`/`create_account` 的 `semantics` 与三份提案逐键逐值相等（reviewer 脚本比对 `keys_eq=True vals_eq=True`）。
- 越界改动：none。`ownership-check origin/main HEAD --owner worker-module-a` → 13/13（含 `deliveries/worker-module-a/**` 预留规则）。
- 共享层改动：none。`shared/**`、`scripts/**`、`ci/**`、`.agent/**`、`pyproject.toml`、`uv.lock` 不在 diff 内。

## 门禁验证（`d7d7588`，orchestrator 复跑）

| 门禁 | 命令 | 结果 |
|---|---|---|
| contract | `bash scripts/contract-check.sh` | PASS exit 0（契约 2 份，失败 0） |
| ownership | `bash scripts/ownership-check.sh origin/main HEAD --owner worker-module-a` | PASS exit 0（13 文件） |
| format | `uv run ruff format --check .` | PASS exit 0（6 files already formatted） |
| lint | `uv run ruff check .` | PASS exit 0 |
| typecheck | `uv run mypy .` | PASS exit 0（6 source files） |
| unit | `uv run pytest tests/contracts/module-a tests/modules/module-a` | PASS exit 0（109 passed, 1 skipped） |
| integration | `quality-gates.yaml:48` = TBD | NOT_CHECKED |
| security | `quality-gates.yaml:54` = TBD | NOT_CHECKED |
| CI | PR #1 `statusCheckRollup` 为空 | NOT_CHECKED |

黑盒复核（不读实现，直接调契约声明的方法）：

```
'a\x7fb' INVALID_CATEGORY   'a\x9fb' INVALID_CATEGORY   'a\tb' INVALID_CATEGORY   'ok' ACCEPTED
CUC INVALID_CURRENCY        SLL INVALID_CURRENCY        usd INVALID_CURRENCY      CNY ACCEPTED
```

## 未验证项

| 项 | 原因 | 需要谁执行什么 |
|---|---|---|
| integration / security | 门禁命令仍为 TBD，仓库无 `tests/integration` 与扫描配置 | orchestrator |
| PR #1 CI | `ci/github-actions.yml` 未落到 `.github/workflows/` | orchestrator 接线后重跑 |
| `contracts/_schema.json` | 文件不存在，`contract-check` 只做结构与 breaking 校验 | orchestrator 补 schema 或维持文档现状 |
| `Cf` 字符、ISO 表快照版本 | 契约未覆盖，属待决策 | orchestrator 决定是否提案 |

## Orchestrator 处置

首轮的 F1–F8 全部关闭；F10 在收口轮修复并有前后对照；F11/F12/F13/F15 修复；
F14 由 orchestrator 直接改文档；F16 维持现状并记录理由；F17 由合并方式规避。
剩下的是 integration / security / CI 接线与 schema，属仓库级待办，不阻塞本 PR。