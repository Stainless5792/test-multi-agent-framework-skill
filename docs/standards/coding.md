# 编码规范

只写「多 Agent 协作会真的踩到」的条目。风格细节交给 formatter，不在这里重复。

## 边界

- 模块内部随便写，跨模块必须走契约方法。
- 禁止 `from modules.<other>.internal import ...`；只允许 import 契约声明的入口。
- 禁止在 `shared/**` 里 import 任何 `modules/**`。

## 类型

- 跨模块的数据结构只能来自契约生成的类型（`shared/contracts/`），禁止在模块内重新定义。
- 外部输入在边界处解析成契约类型，内部只信已解析的类型。
- 可枚举的状态用枚举，不用裸字符串。

## 错误

- 抛契约声明的错误码，不抛裸 Exception。
- 错误信息不包含密钥、SQL、堆栈。
- 新增错误码必须先改契约。

## 依赖

- `requirements*.txt`、`pyproject.toml`、`*.lock` 由 orchestrator 维护，Worker 不提 PR 改它们。
- 需要新依赖时在任务里写申请（包名、用途、替代方案），由 orchestrator 落地。

## 配置

- 配置从环境读取，代码里不留默认密码。
- 每个 Worker 的本地配置只写在自己的 worktree，不进仓库。

## 提交

- 一个 commit 一个可解释的动作；提交信息说明「为什么」。
- 不提交 `.env`、构建产物、本地路径。
- 分支命名 `feature/<module>-<task-id>`。