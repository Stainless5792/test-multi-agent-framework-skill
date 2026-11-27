# Agent 协作协议

本协议定义「一个 Orchestrator + N 个模块 Worker」如何在**不读对方代码**的前提下协作。
违反其中任一铁律的产出，一律不算交付。

## 铁律

1. **契约优先于实现。** 契约是模块之间唯一的通信媒介。实现证明契约错了，先改契约、再改代码。
2. **不读对方源码。** Worker 只读：自己模块的代码、`contracts/`、`docs/architecture/`、
   `AGENTS.md`。要判断对方行为，看契约与契约测试，不看对方实现。
3. **一个路径一个所有者。** `shared/**` 归 Orchestrator；Worker 只读。需要改 shared，
   写提案，由 Orchestrator 改或授权改。
4. **Agent 不合并。** Worker 只推自己的 feature 分支并开 PR；合并由人（或人明确授权的
   Orchestrator 会话）执行。
5. **不猜依赖。** 下游只依赖契约里写明的东西。契约没写的字段、错误码、副作用，一律视为不存在。

## 六步生命周期

| 步 | 执行者 | 动作 | 出口条件 |
|---|---|---|---|
| 1 | Orchestrator | 定模块边界，写契约，标 `approved` | 该模块零业务代码 |
| 2 | Worker ×N | 只读契约与自己的路径，开工；下游用 Mock | 各自 worktree 干净、分支已建 |
| 3 | Worker | 交付：分支 + 改动清单 + 实跑命令与退出码 + 契约增量 | 报告五段齐全 |
| 4 | Worker（阻塞时） | 写 `contracts/<m>/proposals/<id>.md` 并停手 | 提案有人受理 |
| 5 | Orchestrator | 审 PR：契约兼容、越界、证据 | 结论为 approve 或 request changes |
| 6 | 人 | 合并 PR，跑集成门禁，结果写回任务 | 集成通过或回退该 PR |

第 4 步是最容易被跳过的一步。Worker 觉得「顺手改一下对方接口更快」时，就是这一步必须生效的时候。

## Mock 规则

- 上游未实现时，下游按契约写 Mock，Mock 与契约放在一起（`contracts/<m>/mocks/`）。
- Mock 必须由契约测试验证：字段名、类型、枚举、错误码与契约一致。
- 上游实现完成后，删掉 Mock，跑一次契约测试。Mock 与真实实现同时存在视为缺陷。

## 冲突升级路径

1. Worker 发现契约缺字段/错误码不符/语义含糊 → 停手，写提案。
2. 提案必含：动机、影响面（哪些模块在用）、兼容性判定（additive / breaking）、迁移步骤。
3. Orchestrator 判定：
   - additive（新增可选字段/新增方法）→ 契约 minor 升版，通知用到的 Worker，不阻塞。
   - breaking（删字段/改类型/改语义）→ 契约 major 升版 + 旧版本保留一个窗口期，
     双方任务同步更新后再继续。
4. 未获批准的契约改动，`contract-check` 直接失败，PR 进不来。

## 交付格式（Worker 必须原样使用）

```
TASK: <id>
BRANCH: <branch>  HEAD: <sha>
CHANGED: <按目录分组的文件清单>
CONTRACTS: <本模块契约版本> | deltas: <none 或提案 id>
VERIFY:
  <command>  exit=<code>  <关键输出一行>
  ...
CROSS-MODULE: <依赖了对方什么，来自哪份契约>
RISKS: <未验证项与原因>
READY_FOR_REVIEW: yes|no
```

`VERIFY` 为空、或写了 `should pass` 的报告，视为未交付。

## 反模式

- 两个 Worker 同时改 `shared/`：所有权冲突，先拆。
- Worker 之间互相 `read` 对方模块源码「对齐实现」：串味，退回重做。
- 为了赶进度先在代码里改接口、事后再补契约：契约失真，后续全部返工。
- 让一个 Worker 顺手做「半个模块」：边界模糊，`ownership-check` 会拦。