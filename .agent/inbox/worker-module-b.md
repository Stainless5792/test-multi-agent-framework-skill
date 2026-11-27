# Inbox: worker-module-b

- 任务：`TASK-MODULE-B-002`（单测夹具切到契约入口）
- 分支：`feature/module-b-TASK-MODULE-B-002`（从 `origin/main` 建）
- 下发：orchestrator，2026-11-27

## 指令

1. `tests/modules/module-b/**` 目前直接引用 `contracts/module-a/mocks/ledger_service.py`。
   按协议该 mock 在 A 的实现合入后应删除（`TASK-MODULE-A-004`），删了你的套件就红。
   本轮把它切成**按契约解析**：读 `contracts/module-a/v1.yaml` 的 `implementation`
   （`module_path` + `factory`），`sys.path` 加入后解析并实例化。
2. 只改 `tests/modules/module-b/**` 与 `modules/module-b/**`（如需注入点）。不要删 mock，
   那是 A 的活；不要改 `contracts/module-a/**`。
3. 验收：临时副本里删掉 `contracts/module-a/mocks/` 后，B 套件仍全绿，给出命令与输出。
4. 心跳照旧；交付报告落 `docs/reviews/deliveries/worker-module-b/TASK-MODULE-B-002-delivery.md`。

## 上下文

- 主线 `40e7c79`，框架升到 v1.8.0：`contract-check` 现在会校验 `implementation`
  （`module_path` 必须存在、`factory` 必须 `<import 名>:<类名>`、`bootstrap` 枚举）。
- `scripts/**`、`.agent/**` 不要在 worktree 里改。
