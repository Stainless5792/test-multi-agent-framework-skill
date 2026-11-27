# Proposal: 声明错误交付面（error_surface）与 `from` 的调用形态

- 提案人: worker-module-a
- 目标契约: `contracts/module-a/v1.yaml`
- 兼容性判定: additive（minor；只补声明，不删字段、不改类型、不改枚举、不改错误码语义）
- 判定: accepted（orchestrator 预批，2026-11-27，形态按提案正文）
- 影响面: `worker-module-b`（唯一消费者；要透传 `ACCOUNT_NOT_FOUND`）、
  `worker-module-a`（实现方）。无其他模块引用本契约。
- 触发来源: X1 / X2（B-001 第一轮评审）。B 需要把 A 的业务错误码透传出去，
  但契约只声明了 `error_codes` 表，**没声明错误怎么交到调用方手上**；B 只能读 A 的
  mock 或源码来确认异常形状，违反铁律 2（不读对方源码）与铁律 5（不猜依赖）。
  另一处是 `from` 是 Python 关键字，契约写了参数名却没写调用形态。

## 动机

### X1：错误交付面缺失

`error_codes` 只说明「有哪些失败、各自 http / retryable」，没有说明：

1. 失败是抛异常、返回错误对象，还是返回 `(ok, err)` 二元组；
2. 调用方从异常对象的**哪个属性**取 `code` / `http_status` / `retryable`；
3. `code` 的取值域是否就是本契约的 `error_codes`（会不会多出实现私有码）；
4. 调用方可不可以按异常**类名**或继承关系分支。

现状是：A 的实现抛 `ledger.LedgerError`，mock 也抛自家 `LedgerError`。B 若写
`except LedgerError` 或 `isinstance(exc, <A 的类>)`，就把 A 的实现细节写进了自己的
代码——A 换类名、mock 与真实实现类不同，B 都会静默失配。契约必须把「按什么识别」
写死：**按属性与 code 取值域，不按类型名**。

### X2：`from` 的调用形态缺失

契约参数名是 `from`（Python 关键字）。实现用 `from_` 承接，并通过 `**kwargs`
接收字面 `from`：

```python
service.list_entries(account_id=..., **{"from": "2026-01-01"})   # 契约字面
service.list_entries(account_id=..., from_="2026-01-01")         # 别名
```

两种调用形态都已存在，但契约未声明，B 只能从 A 的 README / mock 里看到写法。

## 变更内容（before → after）

### 1. 顶层 `error_surface`

加在 `error_codes` 与 `versioning` 之间（与 `implementation` 同级的顶层块）：

```yaml
error_surface:
  mechanism: exception            # 业务失败以异常形式抛出，不用返回值编码
  attributes: [code, http_status, retryable]   # 异常必须暴露的三个属性
  code_domain: error_codes        # code 取值域就是本契约 error_codes 的键，不得新增码
  notes: "异常类名不是契约事实，消费者不得依赖类型名或继承关系；只依赖 attributes 与 code_domain"
```

### 2. `list_entries.semantics.from_parameter`

在现有 `list_entries.semantics` 里追加一个键（其余语义不变）：

```yaml
    semantics:
      range: "…（不变）"
      order: "…（不变）"
      limit: "…（不变）"
      date_input: "…（不变）"
      from_parameter: "契约参数名 from 是 Python 关键字；调用形态 list_entries(**{'from': ...}) 与 from_ 关键字参数等价，两者必须行为一致"
```

## 兼容性判定

additive / minor：

- 只新增顶层键与一个 `semantics` 键，不删字段、不改 `input` / `output` / `errors` /
  `types`、不改任何错误码的 http / retryable、不改既有语义文字。
- 对 A：实现无需改动（当前行为已符合：异常对象有 `code` / `http_status` /
  `retryable`，`code` 取自 `ERROR_HTTP_STATUS` 即 `error_codes` 键；
  `list_entries` 两种调用形态已等价）。本提案只把既有行为写成契约事实。
- 对 B：拿到三条可用事实——按 `attributes` 取字段、按 `code_domain` 校验取值、
  不按类名分支；`from` 用哪种写法都行。
- `scripts/contract-check.sh --base origin/main` 只对「删方法 / 删类型字段 / 改类型 /
  删错误码」判 breaking，新增键不触发。

## 迁移步骤

1. orchestrator 已预批；
2. worker-module-a 落 `v1.yaml` 两处、抄进 `contracts/module-a/CHANGELOG.md`
   （2026-11-27 第四条）；
3. 同一次提交加契约测试：断言 `error_surface` 的形态；触发一个业务错误后按
   `hasattr` / `getattr` 校验三个属性与取值域（**不使用** `isinstance` 依赖类名）；
   断言 `**{"from": d}` 与 `from_=d` 返回一致（真实实现与 mock 各跑一遍）；
4. 通知 worker-module-b：异常按属性 + code 识别，别写 `except LedgerError`。

## 回滚方式

删除 `error_surface` 顶层块与 `list_entries.semantics.from_parameter` 即可；
实现与测试行为不变，回滚零影响。

## 提议人自检（落地时确认）

- 实现的 `code` 属性名与契约一致（`LedgerError.code`），无需改名。
- `http_status` / `retryable` 属性名一致。
- `code` 只可能取 `ERROR_HTTP_STATUS` 的 6 个键，构造时对未知码抛 `ValueError`。
- `list_entries(**{"from": ...})` 与 `from_=...` 走同一条路径（`_take_from_alias`）。