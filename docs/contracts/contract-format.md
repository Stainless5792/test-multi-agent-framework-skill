# 契约格式

契约是模块之间唯一的接口事实源。人读它，脚本校验它，测试验证实现是否遵守它。

## 位置与命名

```
contracts/<module>/v1.yaml          # 当前版本
contracts/<module>/v0.yaml          # 兼容窗口内的旧版本（仅 breaking 变更时保留）
contracts/<module>/mocks/           # 下游用的 mock，必须与契约同源
contracts/<module>/proposals/<id>.md
contracts/<module>/CHANGELOG.md
```

`<module>` 与 `.agent/project-dependencies.yaml` 的 `modules[].id` 一致。

## 字段

```yaml
contract:
  name: UserService            # 与 module 一致的服务名
  module: user
  version: v1                  # v<major>；major 变更才换文件名
  status: approved             # draft | approved | deprecated
  owner: worker-user           # 谁维护这份契约
  consumers:                   # 谁依赖它，改之前必须通知
    - worker-auth
  stability: stable            # stable | experimental

methods:                       # 每个可调用能力一条
  - name: get_user_by_id
    kind: request_response     # request_response | event | stream
    input:
      user_id: { type: string, required: true, format: uuid }
    output:
      user: { type: object, required: true, ref: User }
    errors: [USER_NOT_FOUND, INVALID_USER_ID]
    idempotent: true
    side_effects: none

types:                         # 跨模块共享的数据结构，唯一来源
  User:
    id: { type: string, format: uuid }
    username: { type: string }
    email: { type: string, format: email }
    status: { type: string, enum: [active, disabled] }

error_codes:                   # 错误必须可枚举，禁止裸字符串
  USER_NOT_FOUND: { http: 404, retryable: false }
  INVALID_USER_ID: { http: 400, retryable: false }

versioning:
  strategy: semver_method       # 新增可选字段=minor，删字段/改类型/改语义=major
  deprecation_window: 1_release

mocks:
  path: contracts/user/mocks/user_service.py

contract_tests:
  command: pytest tests/contracts/test_user_contract.py -q
```

## 版本与兼容

| 变更 | 版本 | 是否阻塞下游 |
|---|---|---|
| 新增可选字段 / 新增方法 | minor | 否，通知即可 |
| 新增必填字段 | major | 是 |
| 删除字段 / 改类型 / 改枚举值 / 改语义 | major | 是，保留旧版本一个窗口 |
| 改错误码含义 | major | 是 |
| 只改注释、文档 | patch | 否 |

## 类型单一来源

`shared/contracts/` 下的 Pydantic 模型（或 TS 类型）由 `scripts/contract-check.sh --gen`
从 YAML 生成。**禁止手写第二份。** 手写副本一旦与 YAML 不一致，`contract-check` 失败。

## 契约测试写什么

一份契约至少三个测试：

1. **结构**：`contracts/<module>/v1.yaml` 通过 `contracts/_schema.json` 校验，必填字段齐全。
2. **实现**：模块的真实入口暴露了契约声明的每个方法，参数名与必填性与契约一致。
3. **行为**：契约声明的每个 `error_codes` 键都能被触发一次（用最小可复现场景），且返回码与契约一致。

示例（Python，FastAPI 风格）：

```python
import yaml
from app.modules.user.service import UserService

CONTRACT = yaml.safe_load(open("contracts/user/v1.yaml"))

def test_methods_exist():
    for m in CONTRACT["contract"]["methods"]:
        assert hasattr(UserService, m["name"]), f"missing {m['name']}"

def test_error_codes_reachable(client):
    for code in CONTRACT["contract"]["error_codes"]:
        resp = client.get("/users/00000000-0000-0000-0000-000000000000")
        assert resp.json()["code"] in CONTRACT["contract"]["error_codes"]
```

## 变更提案

`contracts/<module>/proposals/<YYYYMMDD>-<slug>.md`：

```markdown
# Proposal: <一句话>

- 提案人: worker-auth
- 目标契约: contracts/user/v1.yaml
- 判定: additive | breaking
- 影响面: worker-auth, worker-project（列出具体调用点）

## 动机
## 变更内容（before / after）
## 迁移步骤
## 回滚方式
```

提案被 Orchestrator 标 `accepted` 后，才允许改契约文件。改完跑 `contract-check`，
通过后把提案里的判定抄进 `contracts/<module>/CHANGELOG.md`。