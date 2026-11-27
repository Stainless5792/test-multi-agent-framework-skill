# Delivery: TASK-MODULE-A-001

- 任务：module-a 账目域首个可交付切片（账户 / 流水 / 余额）
- Owner：worker-module-a
- 分支：`feature/module-a-TASK-MODULE-A-001`
- 交付代码：`9553ab0`（合并基线 `origin/main` @ `34629f6`）
- PR：#1
- 报告来源：**worker-module-a 自签**（第五轮）。首轮曾由 orchestrator 转录到
  `docs/reviews/TASK-MODULE-A-001-delivery.md`；第五轮按 AGENTS.md 新规则迁到
  `docs/reviews/deliveries/worker-module-a/`，本文件为准。本文件随其后一笔
  docs 提交入库（`git log -- docs/reviews/deliveries/worker-module-a/`）。

```
TASK: TASK-MODULE-A-001
BRANCH: feature/module-a-TASK-MODULE-A-001   HEAD: 9553ab0
CHANGED:
  modules/module-a/            ledger.py, README.md
  contracts/module-a/          v1.yaml, CHANGELOG.md, mocks/ledger_service.py,
                               proposals/20261127-{entrypoint,semantics,create-account-semantics}.md
  tests/modules/module-a/      conftest.py, test_ledger_service.py
  tests/contracts/module-a/    test_ledger_contract.py, test_ledger_parity.py
CONTRACTS: contracts/module-a/v1.yaml（v1）| deltas: 3 份提案，均 accepted（additive/minor）
CROSS-MODULE: 消费方 worker-module-b；只依赖 contracts/module-a/v1.yaml，未 import 对方代码
RISKS: integration / security 门禁仍 TBD；CI 未接线；mock 与实现并存至 B 合入
READY_FOR_REVIEW: YES
```

## 改动文件清单（`git diff --stat origin/main..9553ab0`）

| 文件 | 增行 | 说明 |
|---|---|---|
| `modules/module-a/ledger.py` | +250 | `LedgerService` 实现（内存态） |
| `modules/module-a/README.md` | +92 | 入口按契约 `implementation`、语义以契约为准、异常口径 |
| `contracts/module-a/mocks/ledger_service.py` | +250 | 供 module-b 并行开发的 mock（实现镜像，契约测试覆盖） |
| `contracts/module-a/v1.yaml` | +35/−2 | `implementation` + 四个方法的 `semantics` + Entry 缺省值注释 |
| `contracts/module-a/CHANGELOG.md` | +36 | 三次 additive 变更 + 唯一性 v1 冻结注记 |
| `contracts/module-a/proposals/20261127-entrypoint.md` | +152 | accepted，方案 A（`implementation` 字段） |
| `contracts/module-a/proposals/20261127-semantics.md` | +164 | accepted，排序 / 区间 / 缺省值 / 日期严格形态 |
| `contracts/module-a/proposals/20261127-create-account-semantics.md` | +137 | accepted，`create_account` 三条留白 + 四条建议处置 |
| `tests/contracts/module-a/test_ledger_contract.py` | +337 | 契约面：方法 / 参数 / 字段 / 6 错误码 / 入口 / semantics |
| `tests/contracts/module-a/test_ledger_parity.py` | +215 | real ↔ mock 11 个场景 parity |
| `tests/modules/module-a/conftest.py` | +30 | 夹具 |
| `tests/modules/module-a/test_ledger_service.py` | +308 | 行为用例（余额、区间、排序、错误码、边界） |

合计 12 个文件，+2004 / −2；加上本报告共 13 个文件。

## 契约增量

`contracts/module-a/v1.yaml` 版本号仍为 `v1`，文件名不变，三次变更均 additive / minor：

1. `implementation: {module_path, factory, bootstrap}`——下游接入由契约决定，
   `factory` 统一 `<import 名>:<类名>`（提案 `20261127-entrypoint.md`，方案 A）。
2. `record_entry` / `get_balance` / `list_entries` 的 `semantics`——排序、闭区间、
   `as_of` 含当天、`category` / `memo` 缺省与归一化、日期输入严格 `YYYY-MM-DD`、
   `ValueError` 前置条件（提案 `20261127-semantics.md`）。
3. `create_account.semantics`——`name` 去空白、唯一性（同一实例内 + 跨币种）、
   `currency` 不归一化、校验顺序 `name → currency → 重名`、生成字段、
   必填值缺失抛 `ValueError`（提案 `20261127-create-account-semantics.md`）。

`bash scripts/contract-check.sh` 以 `origin/main` 为 base 判定「无 breaking」：
新增键与新增类型字段不触发 breaking 规则，退出码 0。

## 验证（worker-module-a 实跑，退出码为真）

| 命令 | 退出码 | 关键输出 |
|---|---|---|
| `uv run pytest tests/contracts/module-a tests/modules/module-a` | 0 | `94 passed, 1 skipped` |
| `uv run ruff check .` | 0 | `All checks passed!` |
| `uv run ruff format --check .` | 0 | `6 files already formatted` |
| `uv run mypy .` | 0 | `Success: no issues found in 6 source files` |
| `bash scripts/contract-check.sh` | 0 | `契约: 2 份，失败 0` |
| `bash scripts/ownership-check.sh origin/main HEAD --owner worker-module-a` | 0 | 全部文件都在所有权范围内（含本报告的自签目录） |

未跑、也不声称通过：`scripts/integration-check.sh`（integration / security 两项在
`.agent/quality-gates.yaml` 里仍是 `TBD`）。

## CROSS-MODULE

- 依赖对方什么：无。未 import `modules/module-b/**` 任何代码。
- 向对方提供什么：`contracts/module-a/v1.yaml`（方法、字段、错误码、
  `implementation`、`semantics`）+ `contracts/module-a/mocks/ledger_service.py`。
- 对 module-b 的影响：方法输入只有 `account_id`，不调用 `create_account`；若 B 的
  夹具自建账户，需按 `create_account.semantics` 处理（`"usd"` 非法、`"Cash "` 与
  `"Cash"` 同名、不同币种不能重用同名）。

## 未验证项与偏差

| 项 | 说明 | 需要谁做什么 |
|---|---|---|
| integration 门禁 | `.agent/quality-gates.yaml` 仍为 `TBD`，无跨模块用例 | orchestrator，等 module-b 合入后补 `tests/integration` |
| security 门禁 | 无 CI step / 扫描配置可溯源 | orchestrator |
| CI 是否绿 | 仓库只有 `ci/github-actions.yml`，无 `.github/workflows/`；PR #1 `statusCheckRollup` 为空 | orchestrator 接线后重跑 |
| `types-PyYAML` 缺失 | 契约测试用 `yaml.safe_load`，dev 组只有 `pyyaml`；mypy 需 `# type: ignore[import-untyped]`，加 stub 后该 ignore 会触发 `warn_unused_ignores` | orchestrator 在 `pyproject.toml` / `uv.lock` 加 `types-PyYAML`，worker-module-a 删 ignore |
| mock 生命周期 | mock 与真实实现并存（`agent-protocol.md:34` 视为缺陷，但本任务验收要求产出 mock 给 B） | module-b 合入后按协议删除 mock 并跑一次契约测试 |
| 唯一性范围冻结 | v1 冻结为「实例内 + 跨币种」；改范围属 breaking | 持久化或 `TASK-MODULE-A-002` 前单独提案 |
| `TASK-MODULE-A-002` | `modules/module_a/` 可导入包为 backlog | orchestrator 排期 |

READY_FOR_REVIEW: YES