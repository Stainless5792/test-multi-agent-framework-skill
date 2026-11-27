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

error_surface:                 # 错误怎么交到调用方；没有这条，消费者只能猜异常类名
  mechanism: exception         # exception（抛异常） | return_value（返回值编码）
  attributes: [code, http_status, retryable]   # 异常/返回值必须暴露的属性名
  code_domain: error_codes     # code 的取值域就是上面那张表，不得新增码
  notes: "异常类名不是契约事实，消费者不得依赖类型名或继承关系"

versioning:
  strategy: semver_method       # 新增可选字段=minor，删字段/改类型/改语义=major
  deprecation_window: 1_release

implementation:                 # 下游怎么拿到实现；没有它，mock 删掉后下游无契约级入口
  module_path: modules/user      # 相对仓库根
  factory: "ledger:UserService"  # <import 名>:<类名>，禁止下游猜模块名
  bootstrap: sys_path            # package | sys_path；package 表示 module_path 可常规 import

mocks:
  path: contracts/user/mocks/user_service.py

contract_tests:
  command: pytest tests/contracts/test_user_contract.py -q
```

## 实现入口（`implementation`）

`implementation` 是可选块，但**一旦有下游消费者就应补齐**：它把「怎么实例化服务」从模块内部
布局（目录名、`sys.path` 技巧、README 说明）挪进契约，下游不再需要读上游源码。

- `factory` 必须写成 `<import 名>:<类名>`；契约测试要按该字段解析、实例化，并断言契约声明的方法都存在。
  入口失效时门禁直接失败，不靠人肉检查。
- `bootstrap: sys_path` 表示调用方需把 `module_path` 加入 `sys.path`，属**临时形态**；
  `bootstrap: package` 是目标态（`module_path` 是常规包路径，直接 `import`）。
  从 `sys_path` 迁到 `package` 只改字段值，对下游是一次 import 变更。
- 改 `implementation` 的字段值会让下游代码失效，按「改语义」处理（major，或至少提前通知消费者）。
- `requires` 声明「构造这个服务需要哪些上游实例、从哪份契约取」：

  ```yaml
  implementation:
    module_path: modules/report
    factory: "report:ReportService"
    bootstrap: sys_path
    requires:
      - name: ledger                        # 构造参数名
        from: contracts/ledger/v1.yaml      # 上游契约，按它的 implementation 字段解析
        description: "构造时注入的上游实例"
  ```

  `requires` 只是**声明**，不是加载器：消费者仍要自己按上游契约的 `implementation` 解析出实例，
  再按 `name` 注入。没有 `requires` 时视为无参构造；`from` 指向的契约不存在，契约测试应失败。

## 错误面（`error_surface`）

`error_codes` 只说「有哪些错误」，`error_surface` 说「错误怎么交到调用方」。没有后者，下游只能靠
猜异常类名或用 `except SomeError` 反向依赖上游实现，违反「只依赖契约」。

- `mechanism: exception` 时，抛出的对象必须暴露 `attributes` 里列的属性；
  `code` 的取值必须落在 `code_domain` 指向的表里（通常是 `error_codes`）。
- 属性名与 `error_codes` 的列名是两套命名：`attributes` 用 `http_status`，
  `error_codes` 用 `http`。契约应把映射写清楚（哪个属性对应哪一列），否则消费者只能从测试里反推。
- **异常类名不是契约事实**：消费者不得 `isinstance` 或按类名 `except`，只按属性与取值判断。
- 前置条件违反（类型/格式/必填值缺失）通常抛 `ValueError`，**不进** `error_codes`，也不受
  `error_surface` 约束；契约应在对应方法的 `semantics` 里写明，避免被读成「所有异常都带 code」。

## 版本与兼容

| 变更 | 版本 | 是否阻塞下游 |
|---|---|---|
| 新增可选字段 / 新增方法 | minor | 否，通知即可 |
| 新增必填字段 | major | 是 |
| 删除字段 / 改类型 / 改枚举值 / 改语义 | major | 是，保留旧版本一个窗口 |
| 改错误码含义 | major | 是 |
| 只改注释、文档 | patch | 否 |
| 新增/改 `implementation` 字段值 | minor / major | 新增加 minor；改值算改语义 |

## 类型单一来源

`shared/contracts/` 下的 Pydantic 模型（或 TS 类型）由 `scripts/contract-check.sh --gen`
从 YAML 生成。**禁止手写第二份。** 手写副本一旦与 YAML 不一致，`contract-check` 失败。

## 契约测试写什么

一份契约至少三个测试：

1. **结构**：必填字段齐全、方法与错误码互相引用一致。**现状**：由 `scripts/contract-check.sh`
   做，`contracts/_schema.json` 尚未提供，等补 schema 后才有多余的结构校验；在那之前
   `contract-check` 的覆盖范围就是它的实现，不要声称「schema 已校验」。
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