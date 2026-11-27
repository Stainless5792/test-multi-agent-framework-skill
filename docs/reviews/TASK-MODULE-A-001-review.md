# Review: TASK-MODULE-A-001 / PR #1

- 目标：`feature/module-a-TASK-MODULE-A-001` @ `e87b436`（worktree `worktrees/worker-module-a`）
- Base：`280d162`（= `origin/main`，已核对）
- Reviewer：reviewer（只读子 agent）
- 日期：2026-11-27

## 结论

REQUEST_CHANGES

代码本身与 4 条 acceptance 全部吻合、6 个错误码真实可达、路径零越界、契约文件字节未变。
阻塞点是**契约留白被单方面写进代码与测试**（`agent-protocol.md` 反模式：「先在代码里改接口、事后再补契约」）：
实现入口未在契约声明，可观察语义（排序 / 区间开闭 / 缺省值）无任何契约声明却被测试锁死。
补 additive 提案并经 orchestrator 受理后，可无代码改动转为 APPROVE_WITH_FOLLOWUPS。

## 发现

| ID | 严重级 | 文件:行 | 问题 | 需要做什么 | Owner |
|---|---|---|---|---|---|
| F1 | High | `contracts/module-a/v1.yaml:95-99`、`modules/module-a/README.md:9-12` | 契约没有「实现入口」声明。实现无包、目录名含 `-`，只能 `sys.path.insert(0, "modules/module-a"); import ledger`。按协议 mock 在上游实现后必须删除，删后 module-b 无契约级路径拿到实现，只能抄 A 的目录布局（铁律 2 禁止）；`ledger` 裸模块名在同进程双 `sys.path` 下有遮蔽风险 | 提案：additive 增 `implementation: {module_path, factory}`，或 A 提供可导入包并在契约登记入口 | worker-module-a 提案 / orchestrator 受理 |
| F2 | High | `modules/module-a/ledger.py:106-108, 183-184, 200-206, 228-241` + 对应测试 | 契约未写的可观察语义被定死并被测试锁死：`list_entries` 按 `occurred_on` 升序、同日按写入顺序；`from`/`to` 闭区间、`as_of` 含当天；`category`/`memo` 缺省 `""`、`memo` 被 `strip()`；`kind` 非枚举 / 非法日期 / `limit<=0` 抛 `ValueError`。这些直接决定 module-b 汇总正确性 | 同一份提案把这 4 条写成契约事实（additive），或显式收紧 | worker-module-a 提案 / orchestrator |
| F3 | Medium | `contracts/module-a/mocks/ledger_service.py` | mock 与实现逐行镜像（diff 仅注释差异），无 parity 门禁；契约测试只覆盖契约面，F2 那批留白行为两边漂移看不出来 | 二选一：加 parity 测试（同场景 real vs mock 断言相等），或在 F1 提案里给 mock 定删除条件 | worker-module-a |
| F4 | Medium | `.agent/workers/worker-module-a.json`（不存在） | 心跳缺失，看板无法区分 working/blocked/stale | Worker 下次开工前补写；本次状态由 orchestrator 手工登记 | worker-module-a |
| F5 | Low | `docs/reviews/TASK-MODULE-A-001-delivery.md:34-35` | 报告写 `63 passed`，实测 `64 passed, 1 skipped`（40 + 25） | 已由 orchestrator 修正 | orchestrator |
| F6 | Low | `tests/contracts/module-a/test_ledger_contract.py:5-9, 39-167` | 为绕开 PyYAML 缺失，自写 371 行 YAML 子集解析器；契约改用块标量/锚点后会失效 | 在 `pyproject.toml` dev 依赖加 `pyyaml`，改用 `yaml.safe_load`（`pyproject.toml` 不归 Worker） | orchestrator |
| F7 | Low | `modules/module-a/ledger.py:101` | `date.fromisoformat` 额外接受紧凑格式 `20260101`，契约写 `YYYY-MM-DD`，README 未留痕 | 并入 F2 提案说明，或显式收紧 `len==10` | worker-module-a |
| F8 | Low | `docs/reviews/TASK-MODULE-A-001-delivery.md` | 协议要求 Worker 自签五段报告（含 `CROSS-MODULE`），但 `docs/**` 归 orchestrator，Worker 无处落盘；本报告为转录且缺 `CROSS-MODULE` 段 | 定一个 Worker 报告落盘位置（如 `docs/reviews/inbox/<worker>/`）或改协议 | orchestrator |

## 契约与边界

- 契约兼容性：compatible（无 breaking、无 additive）。`git diff --name-only 280d162 HEAD` 不含 `contracts/module-a/v1.yaml`；`git show` 比对字节一致。
- 6 个错误码全部可达，`code` / `http` / `retryable` 与契约逐项相等；`test_error_codes_declared_by_contract_are_all_triggered` 保证与契约键集合双向相等。
- 契约留白判定：非法 `kind` 抛 `ValueError` 可接受（enum 违反属前置条件违反，硬塞错误码会破坏 `error_codes` 可枚举性）；但排序 / 闭区间 / `as_of` 含当天 / `""` 缺省这批语义不能长期停留在契约外 —— 即 F2。
- 越界改动：none。`ownership-check 280d162 HEAD --owner worker-module-a` → 6/6 通过。
- 共享层改动：none（未触碰 `shared/**`、`scripts/**`、`ci/**`、`.agent/**`、`pyproject.toml`、`uv.lock`）。

## 门禁验证

reviewer 在 worktree 内自行执行，`git status --porcelain` 前后均为空。

| 门禁 | 命令 | 结果 |
|---|---|---|
| contract | `bash scripts/contract-check.sh` / `--base 280d162` | PASS exit 0（契约 2 份，失败 0） |
| ownership | `bash scripts/ownership-check.sh 280d162 HEAD --owner worker-module-a` | PASS exit 0（6 文件） |
| format | `uv run ruff format --check .` | PASS exit 0（5 files already formatted） |
| lint | `uv run ruff check .` | PASS exit 0 |
| typecheck | `uv run mypy .` | PASS exit 0（5 source files） |
| unit | `uv run pytest` | PASS exit 0（64 passed, 1 skipped） |
| integration | `quality-gates.yaml:48` = TBD | NOT_VERIFIED |
| security | `quality-gates.yaml:54` = TBD | NOT_VERIFIED |
| CI | PR #1 `statusCheckRollup` 为空；仓库只有 `ci/github-actions.yml`，无 `.github/workflows/` | NOT_VERIFIED（CI 未接线，不能声称绿） |

## 未验证项

| 项 | 原因 | 需要谁执行什么 |
|---|---|---|
| `bash scripts/integration-check.sh` 完整跑分 | 脚本会写 `.agent/logs/`，属只读评审禁止的落盘副作用；已用其背后的 6 条门禁命令逐条替代 | orchestrator 合并前存档一次完整跑分 |
| integration / security 门禁 | 两项仍为 TBD，`blocked_if_tbd: true` 下 strict 模式等于 BLOCKED；不在本任务 `verify_cmds` 内 | orchestrator 补跨模块用例与扫描配置 |
| PR #1 CI 是否绿 | `statusCheckRollup` 空 | orchestrator 把 `ci/github-actions.yml` 落到 `.github/workflows/` |
| mock 与真实实现行为等价 | 只验证源码逐行等价与契约面等价，F2 留白行为无 parity 断言 | worker-module-a 按 F3 补 |
| 契约 `_schema.json` 结构校验 | 仓库无该文件，`contract-format.md:82` 与 `contract-check.sh` 实现不符 | orchestrator 补 schema 或修文档 |

## Orchestrator 处置

- F5 已修（报告数字改为 64 passed / 1 skipped）。
- F1 **受理**：采纳提案 `20261127-entrypoint.md` 的方案 A（契约顶层 `implementation: {module_path, factory, bootstrap}`），附两条硬约束——`factory` 必须写 `<import 名>:<类名>`；契约测试必须按该字段解析并实例化，入口失效即门禁失败。方案 B2（`modules/module_a/` 可导入包）定为目标态，记入 `TASK-MODULE-A-002`，触发条件：module-a 出现第二个实现文件，或 module-b 集成测试落地前。理由：B2 需要改 `file-ownership.md` 与 `allowed_paths` 并同步 module-b 的对称约定，属独立任务，不应阻塞本次交付。
- F2 **受理**（含 F7）：采纳 `20261127-semantics.md`，判定 additive / minor。排序、闭区间、`as_of` 含当天、`""` 缺省与 `strip()` 写入契约；`ValueError` 明确为前置条件违反，不进 `error_codes`；日期收紧为 `len == 10`，与 mock 原子同步修改。
- F3 **接受现状，要求随 F7 补一条日期 parity 场景**：本轮 parity 已覆盖 10 个场景，日期宽松度随 F7 落地后补一条即可，不单独阻塞。
- F4 已由 Worker 补心跳文件（`state=blocked`），但该文件被提交进了分支 —— 属运行态，不应入库，要求从分支移除并依赖 `.gitignore`。
- F6 归 orchestrator：`pyyaml` 已在 `pyproject.toml` dev 组与 `uv.lock` 中，只是本地 venv 未同步；`uv sync` 后契约测试改用 `yaml.safe_load`，删除自写解析器。
- F8 待定：Worker 报告落盘位置需要改 `file-ownership.md`，等本条合并后单独处理。
- integration / security / CI 接线属 orchestrator 待办，不阻塞本 PR。