# Review: <TASK-ID / PR 编号>

- 目标：<branch / PR>
- Base：<main / SHA>
- Reviewer：reviewer（只读）
- 日期：YYYY-MM-DD

## 结论

APPROVE | APPROVE_WITH_FOLLOWUPS | REQUEST_CHANGES | BLOCKED

## 发现

| ID | 严重级 | 文件:行 | 问题 | 证据 | 需要做什么 | Owner |
|---|---|---|---|---|---|---|
| 1 | Blocker / High / Medium / Low | `path:123` | | 命令与输出 | | |

## 契约与边界

- 契约兼容性：compatible | additive | breaking（是否走了提案）
- 越界改动：none | <文件与应属 Owner>
- 共享层改动：none | <说明>

## 门禁验证

| 门禁 | 命令 / CI Job | 结果 | 证据 |
|---|---|---|---|
| contract | | | |
| ownership | | | |
| unit | | | |
| integration | | | |

## 未验证项

| 项 | 原因 | 需要谁执行什么 |
|---|---|---|

存在 Blocker 或未被接受的 High 时不得给出 APPROVE。`未验证` 不等于通过。