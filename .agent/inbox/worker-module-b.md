# Inbox: worker-module-b

- 任务：`TASK-MODULE-B-001`（报表域首个可交付切片）
- 分支：`feature/module-b-TASK-MODULE-B-001`
- worktree：`/Users/kyma/Downloads/git_repos/worktrees/worker-module-b`
- 下发：orchestrator，2026-11-27

## 指令

1. 只读 `contracts/module-b/v1.yaml`（你的契约，status=approved）与 `contracts/module-a/v1.yaml`（取数唯一入口）。
   `contracts/module-a/mocks/ledger_service.py` 是开发期替身，**不要**读 `modules/module-a/**` 源码。
2. **先写提案再写实现**：`contracts/module-b/v1.yaml` 的 `monthly_summary` / `category_breakdown` 没有任何
   `semantics`——期间边界（自然月？含首尾？）、`net` 定义与符号、`category` 空值如何处理、
   `items` 排序、空结果返回什么、`INVALID_PERIOD` 的边界（`month` 0/13、`year` 0 或负）都未声明。
   这些直接决定报表数字，先写 `contracts/module-b/proposals/<日期>-semantics.md`（同样建议给
   `implementation` 一条，下游虽然暂无消费者，但保持与 module-a 一致的形态）。
   写完停下等受理，不要用实现先把语义锁死——module-a 在这一步返工了三轮。
3. 受理后再实现：`ReportService.monthly_summary` / `category_breakdown`，取数只调
   `contracts/module-a/v1.yaml` 的 `list_entries` / `get_balance`，按 `implementation` 字段或 mock 接入。
4. 测试：单元 + 契约测试（方法存在、参数名与必填性、返回字段形状、`ACCOUNT_NOT_FOUND` /
   `INVALID_PERIOD` / `INVALID_DATE_RANGE` 各命中一次）+ 与 mock 的对照。
5. 心跳 `.agent/workers/worker-module-b.json`：开工、每次验证、结束各写一次；
   `blocked` 时 `note` 写具体阻塞点。字段见 `.opencode/agents/worker-module-b.md`。
6. 交付报告落 `docs/reviews/deliveries/worker-module-b/TASK-MODULE-B-001-delivery.md`（该子目录归你）。
7. 不自读 `modules/module-a/**`；不改契约以外模块、`scripts/**`、`.agent/**`、`pyproject.toml`、锁文件、CI。

## 已完成的上游事实

- module-a 已合并（`2b5e8e9`）。它的契约现在有 `implementation` 与四个方法的 `semantics`：
  `list_entries` 按 `occurred_on` 升序（同日按写入顺序，稳定排序）、`from`/`to` **闭区间**、
  `get_balance(as_of)` **含当天**、日期只接受 `YYYY-MM-DD`、`category`/`memo` 缺省 `""`。
- 两处实现收紧，做夹具时注意：`CUC` / `SLL` 已退市 → `INVALID_CURRENCY`；
  `category` 含任何 Unicode `Cc` 控制字符（含 `\x7f`、`\x9f`）→ `INVALID_CATEGORY`。
- mock 在 B 合入后按协议删除，删除动作由 orchestrator 安排，不要自己删。