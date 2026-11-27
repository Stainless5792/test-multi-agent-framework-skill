# 任务与状态机

任务规格统一，是为了让 Worker 不必理解整个项目，也能准确完成自己那一块。

## 状态机

```
backlog → analyzing → ready → in_progress → review → integration → done
                ↘           ↘             ↘            ↘
                  blocked ← ← ← ← ← ← ← ← ← ← ← ← ← ← ←
```

| 状态 | 含义 | 谁能推进 |
|---|---|---|
| `backlog` | 记下来了，还没分析 | 人 |
| `analyzing` | Orchestrator 在拆边界、定契约 | Orchestrator |
| `ready` | 契约 approved、依赖满足、路径已定、验证命令可执行 | Orchestrator |
| `in_progress` | Worker 在写 | Worker |
| `review` | 等审查（PR 已开） | Orchestrator / 人 |
| `integration` | 已合并，正在跑集成门禁 | 人 |
| `done` | 集成通过 | 人 |
| `blocked` | 有明确阻塞点，`blocked_by` 必须写清 | 任何人 |

硬规则：

- `ready` 的必要条件里包含「引用到的契约全部 `approved`」。缺一条就不是 ready。
- `blocked` 必须写 `blocked_by: <具体到文件/契约/命令>`，写「等上游」不算。
- 同一 Worker 同时只有一个 `in_progress`。

## 任务字段

```yaml
- id: TASK-USER-002
  title: 实现用户注册与查询
  module: user
  owner: worker-user
  state: ready
  deps: [TASK-USER-001]          # 任务级依赖
  contracts: [contracts/user/v1.yaml]
  allowed_paths: [modules/user/**, tests/modules/user/**]
  forbidden_paths: [shared/**, modules/auth/**, modules/project/**]
  acceptance:
    - 注册成功返回 201 且返回体符合 User
    - 用户名重复返回 USERNAME_TAKEN
    - 查询不存在的 id 返回 USER_NOT_FOUND
  verify_cmds:
    - pytest tests/modules/user -q
    - pytest tests/contracts/test_user_contract.py -q
    - ruff check modules/user
  deliverables: [branch, report, contract_deltas]
  mock:
    needed: false
    path: null
  blocked_by: null
```

## 就绪判定（validate 会检查）

一条任务可以进入 `ready`，必须同时满足：

1. `owner` 存在于 `.agent/file-ownership.md`。
2. `deps` 里的任务都已是 `done` 或 `integration`。
3. `contracts` 里每份契约 `status: approved`。
4. `allowed_paths` 与任何其他 `in_progress` 任务不重叠。
5. `verify_cmds` 非空，且每条都能在仓库里找到来源（manifest script / Makefile / CI step）。
6. 若 `mock.needed: true`，`mock.path` 指向的文件存在。

## 为什么必须有 Mock

并行开发的瓶颈不是写代码，是等上游。下游只依赖契约时，就可以先写 Mock 把整条链路跑通；
上游实现完成后再替换实现、重跑契约测试。这样两个 Worker 的时间轴才能真正重叠。

Mock 的三个要求：

- 放在 `contracts/<module>/mocks/`，与契约同目录，跟着契约版本走。
- 字段、枚举、错误码必须与契约一致，由契约测试兜底。
- 替换为真实实现时，删除 Mock 文件，别留两套。

## 交付物

- 分支：`feature/<module>-<task-id>`，从主干切出，直接对主干开 PR。
- 报告：`docs/reviews/<task-id>-delivery.md`，使用协议里的五段格式。
- 契约增量：无变更写 `deltas: none`；有变更必须指向提案 id。