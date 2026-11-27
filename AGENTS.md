# 项目指令

<!-- maf:begin — 由 /multi-agent-framework 追加，勿手工删除标记 -->
## Multi-Agent 协作规则

本仓库使用「1 个 Orchestrator + N 个模块 Worker」。以下规则对所有 Agent 生效，
优先级高于通用工程流程。

### 优先级

- 单个任务内部的实现纪律（复现、根因、验证）走 `poteto-mode`。
- 跨模块拆分、契约、任务派发、合并走本框架（`.agent/` + `contracts/`）。

### 必读

1. `.agent/project-dependencies.yaml` — 模块与依赖
2. `.agent/file-ownership.md` — 谁能改哪些路径
3. `.agent/task-dag.yaml` — 什么可做、什么被阻塞
4. `contracts/<module>/v1.yaml` — 你要遵守与实现的接口
5. `docs/architecture/` — 全局视图与边界
6. `.agent/quality-gates.yaml` — 合并前必须过的门禁
7. `docs/protocol/agent-protocol.md` — 协作协议与交付格式
8. `docs/contracts/contract-format.md` — 契约字段与版本规则

缺文件或仍是 `TBD` 时，说出来并停下，不要用猜测补。

### 铁律

1. 契约优先于实现。实现证明契约错了，先改契约再改代码。
2. Agent 之间不读对方源码，只读契约与架构文档。
3. 一个路径只有一个所有者；`shared/**` 归 Orchestrator，Worker 只读。
4. 契约要改：停手写 `contracts/<module>/proposals/`，不自行修改。
5. Agent 不合并 PR。合并由人决定。
6. 不提交密钥、不跑有副作用的命令、不动 git 历史。

### 交付格式

每个 Worker 的交付必须包含：分支与 SHA、改动文件清单、契约增量、
`命令 + 退出码 + 关键输出`、未验证项。少一项视为未交付。

### 状态查看与合并

- 看板：`bash scripts/dashboard.sh`（只读，127.0.0.1:7717）；没有二进制时用 `bash scripts/status.sh`。
- 心跳文件 `.agent/workers/<worker-id>.json` 由 Worker 在开工、每次验证、结束时写入。
  看板按它区分 working / blocked / stale / delivered。
- 合并前必须跑 `bash scripts/merge-ready.sh <TASK-ID>` 或 `maf-dashboard --check-merge <TASK-ID>`，
  九条全过才允许合并；PR/CI 状态未接入的部分记 NOT_CHECKED，不得默认为通过。
- 合并顺序：契约有 breaking 变更时，契约所有者先合，消费者后合。

### 命令

- 全量门禁：`bash scripts/integration-check.sh`
- 契约：`bash scripts/contract-check.sh`
- 越界：`bash scripts/ownership-check.sh <base> <head>`
<!-- maf:end -->