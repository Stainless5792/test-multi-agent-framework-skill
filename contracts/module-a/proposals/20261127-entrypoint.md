# Proposal: 在契约里声明「实现入口」（implementation）

- 提案人: worker-module-a
- 目标契约: `contracts/module-a/v1.yaml`
- 兼容性判定: additive（minor；不删字段、不改类型/枚举/语义）
- 判定: accepted（orchestrator, 2026-11-27，方案 A + 两条约束）
- 影响面: `worker-module-a`（实现方）、`worker-module-b`（唯一消费者）。
  无其他模块引用 `LedgerService`（`.agent/project-dependencies.yaml` 与
  `contracts/module-b/v1.yaml` 均只声明消费本契约，未声明导入方式）。
- 触发来源: 评审 F1（`docs/reviews/TASK-MODULE-A-001-review.md:21`）

## 动机

契约声明了 4 个方法和 6 个错误码，但**没有声明调用方怎么拿到 `LedgerService`
对象**。当前唯一可行路径写在 `modules/module-a/README.md:9-12`：

```python
sys.path.insert(0, "modules/module-a")
import ledger
```

这有三个后果：

1. **违反铁律 2**（`docs/protocol/agent-protocol.md:9-10`）：module-b 只能读契约，
   却必须读 A 的 README 才知道目录布局，等于依赖对方内部结构。
2. **协议要求删 mock**（`agent-protocol.md:34`「上游实现完成后，删掉 Mock」）。
   删掉 `contracts/module-a/mocks/ledger_service.py` 后，契约里就再没有任何
   下游可达的入口；集成测试又禁止用 mock（`docs/standards/testing.md:29`）。
3. **裸模块名遮蔽**：实现模块名是 `ledger`，靠 `sys.path` 注入。任何同进程存在
   第二个 `ledger` 模块（或 module-b 自己的文件叫 `ledger.py`）都会互相遮蔽，
   且失败方式是静默的。

## 方案

### 方案 A（推荐）：契约登记实现入口，保留现有目录

在 `v1.yaml` 顶层（与 `mocks:` 同级）新增：

```yaml
implementation:
  module_path: modules/module-a     # 相对仓库根
  factory: ledger:LedgerService     # <import 名>:<类名>
  bootstrap: sys_path               # 调用方需把 module_path 加入 sys.path
```

module-b 的接入方式由契约唯一决定，不再看 A 的 README：

```python
sys.path.insert(0, contract["implementation"]["module_path"])
module_name, attr = contract["implementation"]["factory"].split(":")
service = getattr(importlib.import_module(module_name), attr)()
```

改动面：只加契约字段 + 一条契约测试（断言 `factory` 指向可调用对象）。
代码零改动，mock 生命周期不变。

### 方案 B：把实现变成可导入包

两种子形式，都不便宜：

- **B1 只加 `modules/module-a/__init__.py`**：无效。目录名含 `-`，`import
  modules.module-a` 是语法错误（实测 `SyntaxError`），`importlib` 也不应按这种
  名字解析。
- **B2 新增 `modules/module_a/` 包**（下划线），`__init__.py` 重导出
  `LedgerService`。要么把 `ledger.py` 搬进去（`modules/module-a/**` 现有内容
  迁走，mock 镜像也要跟着改），要么在两处各放一份实现（等于把 F3 的漂移风险
  翻倍）。

B2 是长期最干净的目标态（`import modules.module_a` 可用、无 `sys.path` 注入、
无裸模块名），但**需要 orchestrator 先动两处 A 无权改的东西**：

1. `.agent/file-ownership.md` 增加 `modules/module_a/**` → `worker-module-a`
   （现在没有这一行，`ownership-check` 会判「无主路径」）；
2. `.agent/task-dag.yaml` 的 `TASK-MODULE-A-001.allowed_paths` 增加
   `modules/module_a/**`（并与 `project-dependencies.yaml` 的路径约定对齐）。

本提案不请求这两项授权，也不自改 `.agent/**`。B2 建议作为独立任务
（如 `TASK-MODULE-A-002`）走 ADR，因为改模块路径同时影响 `modules/module-b`
的对称约定。

### 方案 C：mock 长期作为唯一下游入口（A 不暴露实现）

与两条既有规定直接冲突，不推荐：

- `agent-protocol.md:34`：Mock 与真实实现同时存在**视为缺陷**；
- `docs/standards/testing.md:29`：集成测试必须用真实模块，不用 Mock。

若坚持要 C，需要先改协议与测试规范（新增「mock 即交付物」的合法形态、
集成测试例外），属架构决策，不是 A 单方面能定的。相比之下 A 只加一个字段。

## 权衡

| 维度 | A（登记入口） | B2（可导入包） | C（mock 常驻） |
|---|---|---|---|
| 下游是否需要读 A 的布局 | 否（读契约 `module_path`） | 否（标准 import） | 否 |
| 裸模块名遮蔽风险 | 仍在（`ledger`） | 消除 | 消除 |
| 代码改动 | 0 | 迁文件/改镜像，较大 | 0 |
| 需要 orchestrator 授权 | 否 | **是**（ownership + allowed_paths） | 是（改协议/测试规范） |
| 与协议冲突 | 否 | 否 | **是**（两条） |
| 实施轮次 | 本轮受理后即可 | 需独立任务 + ADR | 需改协议 |

## 推荐

**A，本轮。** 它把下游依赖从「A 的目录布局 + README」搬进契约，改动最小，
不触发路径授权，也不动 mock 的生命周期。A 遗留的遮蔽风险用两条约束收窄：

1. `factory` 必须写 `<import 名>:<类名>`，不允许下游猜模块名；
2. 契约测试新增一条：按 `implementation` 解析出的对象存在且可实例化、暴露
   契约声明的 4 个方法——入口一旦失效，契约门禁直接失败。

**B2 作为目标态**：当 module-b 真正落地、或 module-a 出现第二个模块文件时，
再走独立任务把目录改成可导入包，届时 A 的字段值换成
`module_path: modules`、`factory: module_a:LedgerService`，对下游是纯字段值变更。

## 兼容性判定

additive / minor：新增可选的 `implementation` 块，不删字段、不改方法签名、
不改枚举、不改错误码语义。`scripts/contract-check.sh` 只校验已知结构
（已读脚本 `contracts/../scripts/contract-check.sh:60-153`），未知顶层键不报错；
本仓库暂无 `contracts/_schema.json`，因此不需要同步 schema（若以后加 schema，
需允许该键）。

对 module-b 是纯增量：受理前继续用 mock，受理后按 `implementation` 接入真实实现。

## 迁移步骤

1. orchestrator 在提案上标 `accepted`；
2. worker-module-a 在 `v1.yaml` 顶层加 `implementation` 块，并抄进
   `contracts/module-a/CHANGELOG.md`（若已存在）；
3. worker-module-a 在 `tests/contracts/module-a/` 加一条入口测试（解析
   `factory`、实例化、断言 4 个方法存在）；
4. worker-module-b 用契约字段替换硬编码的 `sys.path` 路径；
5. module-b 的 mock 依赖解除后，按 `agent-protocol.md:34` 删除 mock，跑一次
   契约测试。

## 回滚方式

删除 `implementation` 块即可回到「mock 为唯一下游入口」的现状；无代码依赖该
字段，回滚不影响已有测试。

## 受理记录

- 2026-11-27 accepted（orchestrator），采用**方案 A**。两条约束同时生效：
  1. `factory` 统一写 `<import 名>:<类名>`，不允许下游猜模块名；
  2. `tests/contracts/module-a/` 必须有入口测试——按契约 `implementation` 解析出
     对象、实例化、断言契约声明的 4 个方法存在。
- 方案 B2（`modules/module_a/` 可导入包）记为 **`TASK-MODULE-A-002`** backlog，
  触发条件：module-a 出现第二个实现文件，或 module-b 集成测试落地前。
  届时只需改 `implementation.module_path` / `factory` 的字段值，对下游是纯值变更。
- 落地结果：`contracts/module-a/v1.yaml` 的 `implementation` 块、入口测试
  `test_implementation_entrypoint_resolves`、`contracts/module-a/CHANGELOG.md`
  （2026-11-27 条目）。