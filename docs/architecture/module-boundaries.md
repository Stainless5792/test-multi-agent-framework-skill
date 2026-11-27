# 模块边界

按业务域切分。一个模块 = 一个可独立交付、可独立测试、拥有完整纵向切片的单元。

## 好边界与坏边界

| 好 | 坏 |
|---|---|
| `modules/user/**` 含 api/service/repo/model/tests | 把 `api/` 给一个人、`service/` 给另一个人 |
| 模块对外只暴露契约里的方法 | 模块之间直接 import 对方内部实现 |
| 一个模块能独立跑通测试 | 改一个模块必须同时改三个模块才能测 |

## 模块清单

| 模块 | 所有者 | 路径 | 发布契约 | 消费契约 |
|---|---|---|---|---|
| TBD | worker-a | `modules/TBD/**` | `contracts/TBD/v1.yaml` | — |

## 共享层

`shared/**` 由 orchestrator 维护，包含：数据库连接、统一异常、日志、安全、配置读取。

规则：

- Worker 只调用 shared 暴露的接口，不修改 shared。
- 需要新能力时提 proposal，由 orchestrator 实现或授权。
- shared 的接口一旦冻结，变更走契约流程（同样需要版本与兼容判定）。

## 依赖方向

```
modules/* → shared           允许
modules/a → modules/b        只允许通过 contracts/b 的方法
modules/a → modules/b/repo   禁止（读对方内部实现）
shared → modules/*           禁止（反向依赖）
```

## 边界变更

改边界（拆模块、并模块、移动路径）属于架构决策：写 ADR，更新
`project-dependencies.yaml` 与 `file-ownership.md`，再通知受影响的 Worker。