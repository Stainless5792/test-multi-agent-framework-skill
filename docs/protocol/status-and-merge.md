# 状态查看与合并

本文回答两个问题：**现在各 Worker 在干什么**，以及**什么时候可以合**。

## 一、为什么需要专门的状态层

OpenCode 没有跨目录的会话总览：

- `opencode session list` 只列**当前目录**的会话，主仓库看不到 worktree 里的会话；
- 没有 agent 运行状态 API；
- `opencode run -w` 建的是 detached HEAD，落在 `~/.local/share/opencode/worktree/`，
  不适合"一个 Worker 一个分支一个 PR"。

所以状态必须从三个跨会话可靠的来源拼出来：**git、文件、心跳**。

## 二、四个信号源

| 来源 | 能回答 | 拿不到时 |
|---|---|---|
| `git worktree list` + 每个 worktree 的 `log`/`status` | 有没有进展、脏不脏、推没推 | 不可用（git 必需） |
| 每个 worktree 内的 `opencode session list -n 1` | 最近有没有动 | 回退到分支最后提交时间 |
| `.agent/workers/<id>.json` 心跳 | 在做什么、是否 blocked | 无法区分 stale 与 blocked |
| `docs/reviews/<task>-delivery.md` / `-review.md` | 是否交付、评审结论 | 视为未交付 |

PR 与 CI 状态需要 `gh`/`glab`，当前未接入，一律显示 `NOT_CHECKED`。

## 三、五种信号

| 信号 | 判定 | 你该做什么 |
|---|---|---|
| `blocked` | 心跳 `state=blocked` | 看 `note` 里的阻塞点，解契约或改任务，别等 |
| `delivered` | 状态 review/integration 且交付报告齐全 | 跑合并门 |
| `stale` | `in_progress` 且最后活动超过阈值（默认 10 分钟） | 去该 worktree 看一眼，可能卡在等确认 |
| `working` | 有新提交或在阈值内活跃 | 不动 |
| `idle` | 未开工或无分支 | 可以派发 |

阈值用 `--stale N`（分钟）调整。心跳优先级高于会话时间，因为它带语义。

## 四、怎么看

三种入口，数据同源：

```bash
# 1. 浏览器看板（推荐，2 秒自动刷新）
bash scripts/dashboard.sh              # 或 maf-dashboard --dir . --open

# 2. 终端一次性快照
maf-dashboard --once
bash scripts/status.sh                 # 没有二进制时的轻量视图

# 3. 机器可读
curl -s http://127.0.0.1:7717/api/status | jq
```

看板只读：`GET` 接口，不接受任何命令。门禁要执行时在终端跑脚本。

## 五、合并九条

`maf-dashboard --check-merge <TASK-ID>` 或 `bash scripts/merge-ready.sh <TASK-ID>`：

1. 任务状态是 `review` 或 `integration`
2. 分支领先 base ≥ 1 个提交
3. worktree 干净（无未提交与未跟踪）
4. 交付报告存在，含 `VERIFY` 与 `READY_FOR_REVIEW: yes`
5. `ownership-check` 通过
6. `contract-check --base` 通过
7. `integration-check --only contract,ownership,unit` 通过（加 `--run-gates`）
8. 评审结论为 `APPROVE` / `APPROVE_WITH_FOLLOWUPS`
9. 分支已在 origin

任何一条 FAIL 就是 NO-GO。第 7 条默认跳过，CI 里应该跑全量。

## 六、合并顺序

- 契约有 **breaking** 变更（`contracts/<m>/proposals/` 里有 accepted 的 breaking 提案）：
  **契约所有者先合**，消费者后合。
- **additive** 变更：任意顺序。
- 没有契约变更：谁先 `delivered` 谁先合。

`--queue` 会按模块依赖拓扑给出序号；发现"消费者已合、提供者未合"要在下次合并前纠正。

## 七、节奏

| 时点 | 动作 |
|---|---|
| 派发前 | 看板确认没有 `stale` / `blocked`，避免叠加任务 |
| 运行中 | 看板常开（2 秒刷新）；终端可用 `--watch` 不适用，直接挂看板 |
| 收到 `delivered` | 跑合并门 |
| 合并后 | 重跑合并队列，确认下一个 |
| 每天收工 | 交付/评审报告归档，更新 task-dag 状态 |

## 八、Worker 侧义务

Worker 必须在三个时点写 `.agent/workers/<worker-id>.json`：开工后、每次验证后、结束时。
`blocked` 时 `note` 必须写具体阻塞点（文件、契约、命令），否则看板只会显示"变旧"，编排者得人工去问。

心跳文件不入库（`.gitignore` 已包含 `.agent/workers/`），它是本机运行态，不是项目事实。