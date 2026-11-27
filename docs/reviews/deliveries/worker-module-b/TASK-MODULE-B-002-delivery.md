# Delivery: TASK-MODULE-B-002

- 任务：module-b 单测夹具切到契约入口（为 `TASK-MODULE-A-004` 删除 A 的 mock 解除阻塞）
- Owner：`worker-module-b`
- 分支：`feature/module-b-TASK-MODULE-B-002`（从 `origin/main` `e82a5cf` 建立）
- 交付提交：`16e4120`（仅测试夹具）；本报告随后一笔提交入库
- PR：[#4](https://github.com/Stainless5792/test-multi-agent-framework-skill/pull/4)

```
TASK: TASK-MODULE-B-002
BRANCH: feature/module-b-TASK-MODULE-B-002  HEAD: 16e4120
CHANGED:
  tests/modules/module-b/   test_report_service.py（夹具按 A 契约 implementation 解析）
  docs/reviews/deliveries/worker-module-b/  TASK-MODULE-B-002-delivery.md
CONTRACTS: 无变更（contracts/module-b/v1.yaml 与 contracts/module-a/v1.yaml 均未动）
VERIFY:
  grep -rn "module-a/mocks" tests/modules/module-b                exit=1  无匹配（期望 0 命中）
  临时副本删除 contracts/module-a/mocks/ 后跑 B 套件               exit=0  43 passed
  uv run pytest tests/modules/module-b tests/contracts/module-b   exit=0  43 passed
  uv run pytest                                                   exit=0  157 passed, 1 skipped（A 的既有 skip）
  uv run ruff check .                                             exit=0  All checks passed!
  uv run ruff format --check .                                    exit=0  9 files already formatted
  uv run mypy .                                                   exit=0  Success: no issues found in 9 source files
  bash scripts/contract-check.sh --base origin/main               exit=0  契约: 2 份，失败 0
  bash scripts/ownership-check.sh origin/main HEAD --owner worker-module-b  exit=0  2 个文件全部在所有权范围内
CROSS-MODULE: 只读 contracts/module-a/v1.yaml 的 implementation（module_path: modules/module-a、factory: ledger:LedgerService、bootstrap: sys_path）；未读 modules/module-a/** 源码
RISKS: 单测现在直接跑 A 的真实实现，A 行为变化会直接反映；sys.path 注入遵循 A 的 bootstrap 字段
READY_FOR_REVIEW: YES
```

## 改动

只改 `tests/modules/module-b/test_report_service.py`：

- 删除 `LEDGER_MOCK` 常量与 `importlib.util` 的 mock 加载函数。
- 新增 `_resolve_module(implementation)`：按 `implementation["module_path"]` 拼出相对仓库根的路径，加入 `sys.path`，再按 `factory` 的 `<import 名>:<类名>` `importlib.import_module`。
- 新增 `_load_ledger_class()`：读 `contracts/module-a/v1.yaml`，取 `implementation`，解析模块并 `getattr` 类。
- `ledger` 夹具改为 `_load_ledger_class()()`。

夹具中没有写死 module-a 的模块名或类名；换实现只改 A 的契约字段。生产代码、两份契约、`tests/contracts/module-b/**` 均未改动。

## 删 mock 后仍全绿（A-004 前置证据）

在临时副本里复制 `modules` / `tests` / `contracts` / `pyproject.toml`，清掉 `__pycache__`，删除整个 `contracts/module-a/mocks/`：

```
$ TMPD=$(mktemp -d)
$ cp -R modules tests contracts pyproject.toml "$TMPD"/
$ find "$TMPD" -name '__pycache__' -type d -prune -exec rm -r {} +
$ rm -r "$TMPD/contracts/module-a/mocks"
$ (cd "$TMPD" && /path/to/.venv/bin/python -m pytest tests/modules/module-b tests/contracts/module-b -v)
============================== 43 passed in 0.52s ==============================
pytest exit=0
```

同一份工作树的 `grep` 证明源文件不再引用 mock：

```
$ grep -rn "module-a/mocks" tests/modules/module-b
（无匹配，exit 1）
```

（首次 grep 曾命中一个上一分支遗留的 `__pycache__/conftest...pyc`；删除该目录下的
`.pyc` 缓存后无命中。源文件里的 mock 路径已在本提交中移除。）

## 验证（实跑，退出码为真）

| 命令 | 退出码 | 关键输出 |
|---|---|---|
| `uv run pytest tests/modules/module-b tests/contracts/module-b` | 0 | `43 passed` |
| `uv run pytest` | 0 | `157 passed, 1 skipped` |
| `uv run ruff check .` | 0 | `All checks passed!` |
| `uv run ruff format --check .` | 0 | `9 files already formatted` |
| `uv run mypy .` | 0 | `Success: no issues found in 9 source files` |
| `bash scripts/contract-check.sh --base origin/main` | 0 | `契约: 2 份，失败 0` |
| `bash scripts/ownership-check.sh origin/main HEAD --owner worker-module-b` | 0 | 2 个文件全部在所有权范围内 |
| `grep -rn "module-a/mocks" tests/modules/module-b` | 1 | 无匹配 |
| 临时副本删除 `contracts/module-a/mocks/` 后跑 B 套件 | 0 | `43 passed` |

## CROSS-MODULE

只读 `contracts/module-a/v1.yaml` 的 `implementation`：

- `module_path: modules/module-a` → 相对仓库根的导入路径
- `factory: "ledger:LedgerService"` → `<import 名>:<类名>`，夹具拆开后 `import_module` + `getattr`
- `bootstrap: sys_path` → 夹具把 `module_path` 加入 `sys.path`

不读 `modules/module-a/**` 源码，不 import A 的内部函数；行为差异由测试直接暴露。

## 未验证项与偏差

| 项 | 说明 | 需要谁做什么 |
|---|---|---|
| A 的真实实现与 mock 行为差异 | 单测现在跑真实实现；若 A 改语义，B 套件会先红 | A 的变更走契约与自己的测试 |
| `TASK-MODULE-A-004` | 本次只解除 B 的依赖，未删除 mock | orchestrator 安排 A-004 删除 `contracts/module-a/mocks/` |
| integration / security | 门禁仍为 TBD | orchestrator |
| CI | 仓库无 `.github/workflows/`；PR #4 无 checks | orchestrator 接线后重跑 |

READY_FOR_REVIEW: YES