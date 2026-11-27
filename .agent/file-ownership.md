# 路径所有权。一个路径只能有一个所有者，`ownership-check.sh` 按这张表判定越界。
# glob 从项目根开始匹配；先匹配更具体的行，未命中任何行即视为无主（默认拒绝）。

| 路径 glob | 所有者 | 说明 |
|---|---|---|
| `shared/**` | orchestrator | 横切能力，Worker 只读 |
| `shared/contracts/**` | orchestrator | 由 contract-check --gen 生成，禁止手改 |
| `contracts/**` | orchestrator | 契约根级 README / 模板 / 提案模板；模块目录由各自 Worker 拥有 |
| `modules/module-a/**` | worker-module-a | 模块 A 全部实现与测试 |
| `modules/module-b/**` | worker-module-b | 模块 B 全部实现与测试 |
| `tests/modules/module-a/**` | worker-module-a | 模块 A 测试 |
| `tests/modules/module-b/**` | worker-module-b | 模块 B 测试 |
| `tests/contracts/**` | orchestrator | 契约测试由契约所有者维护 |
| `tests/contracts/module-a/**` | worker-module-a | module-a 契约测试 |
| `tests/contracts/module-b/**` | worker-module-b | module-b 契约测试 |
| `contracts/module-a/**` | worker-module-a | 模块 A 契约 |
| `contracts/module-b/**` | worker-module-b | 模块 B 契约 |
| `docs/**` | orchestrator | 架构、协议、ADR、评审记录 |
| `.agent/**` | orchestrator | 项目事实源与门禁 |
| `scripts/**` | orchestrator | 门禁脚本，Worker 只执行不改 |
| `ci/**` | orchestrator | CI 模板 |
| `.opencode/**` | orchestrator | agent 与配置 |
| `AGENTS.md` | orchestrator | 项目指令 |
| `.gitignore` | orchestrator | 忽略规则 |
| `requirements*.txt` | orchestrator | 依赖唯一入口 |
| `pyproject.toml` | orchestrator | 依赖与工具链 |
| `*.lock` | orchestrator | 锁文件 |
| `.github/workflows/**` | orchestrator | CI |
| `.gitlab-ci.yml` | orchestrator | CI |
| `migrations/**` | orchestrator | 迁移顺序敏感 |

## 规则

1. Worker 只能写自己那几行覆盖到的路径。
2. 需要临时扩大范围：先在任务里写理由，由 orchestrator 改这张表，再开工。
3. 同一路径不允许出现两个所有者，包括通过通配符间接触及的情况。