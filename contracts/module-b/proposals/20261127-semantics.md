# Proposal: 把 module-b 报表语义与实现入口写成契约事实

- 提案人: worker-module-b
- 目标契约: `contracts/module-b/v1.yaml`
- 兼容性判定: **additive（minor）**——只新增 `semantics` / `implementation` 与注释，
  不删字段、不改类型、不改枚举、不改任何 `error_codes` 键
- 判定: **accepted**（orchestrator, 2026-11-27）
- 影响面: `worker-module-b`（唯一实现方）；`contracts/module-b/v1.yaml` 的
  `contract.consumers` 为空数组，当前无下游代码受影响。跨模块只涉及
  `worker-module-a` 的两处契约缺口 X1 / X2（见「跨模块依赖与缺口」），不需要 A 改实现
- 触发来源: `TASK-MODULE-B-001` 派发指令（`docs/tasks/TASK-MODULE-B-001.md:26`
  「按分类汇总」、`:27` 三个错误码各命中一次）；`contracts/module-b/v1.yaml`
  的 `monthly_summary` / `category_breakdown` 目前没有任何 `semantics`

## 动机

报表数字由下面这些事实唯一决定，但它们现在全部不在契约里：

| 未定义事实 | 决定什么 | 不定义的后果 |
|---|---|---|
| 期间边界 | 自然月？含首尾？ | 12-31 / 01-01 的流水可能被漏算或双算 |
| `income` / `expense` 符号 | 绝对值还是带符号 | `net` 算成 `income + expense` |
| `net` 定义 | `income - expense`？ | 正负号与上游 `get_balance` 口径不一致 |
| `period` 形态 | `YYYY-MM`？零填充？ | 下游按字符串分组时 `1` 与 `01` 分裂 |
| `year` / `month` 合法范围 | 1..9999 / 1..12？错误码？ | `month=13` 静默返回空汇总 |
| 空账户 / 空区间 | 零还是报错 | 把「无流水」误报成「账户不存在」 |
| `from` / `to` 开闭 | 闭区间？`from == to`？ | 与上游 `list_entries` 差一天 |
| `items` 排序 | `total` 降序？分类字典序？ | 同一份数据两次请求顺序不同 |
| 空 `category`（`""`） | 计入还是丢弃 | 丢弃即静默少算金额 |
| 零额分类 | 输出还是省略 | 输出 `total: 0` 的幽灵项 |
| `total` 符号 | 正数还是带符号 | 与「区间支出」的语义相反 |
| `ACCOUNT_NOT_FOUND` | 原样抛还是重包 | 下游被迫 import A 的异常类型 |
| `implementation` | 下游怎么拿到 `ReportService` | mock 删除后无契约级入口 |

module-a 因为同样的留白返工了三轮（`docs/reviews/TASK-MODULE-A-001-review.md:12-15`）。
本提案一次把上述事实全部写成可测试断言，避免 module-b 重复这条路。

## 变更内容（可直接粘进 `v1.yaml`）

### 1. `methods`（整段替换；字段、错误码、顺序均不变，只补 `semantics`）

```yaml
methods:
  - name: monthly_summary
    kind: request_response
    input:
      account_id: { type: string, required: true, format: uuid }
      year: { type: integer, required: true }
      month: { type: integer, required: true }
    output:
      summary: { type: object, required: true, ref: MonthlySummary }
    errors: [ACCOUNT_NOT_FOUND, INVALID_PERIOD]
    idempotent: true
    side_effects: none
    semantics:
      period_window: "公历自然月，闭区间 [该月 1 日, 该月最后一天]；from = f'{year:04d}-{month:02d}-01'，to = 该年该月实际最后一天（闰年 2 月为 29 日）；日期粒度，无时区参与"
      year_month: "year 必须是整数且 1 <= year <= 9999；month 必须是整数且 1 <= month <= 12；越界 → INVALID_PERIOD；非整数、bool、None → ValueError（前置条件违反，与 module-a 的 precondition_violation 同口径）；缺省属调用方违约，Python 在进入方法前抛 TypeError，不在本契约承诺内"
      income: "区间内 kind=income 的 amount 之和，非负整数；无 income 流水时为 0；不做币种换算、不取整"
      expense: "区间内 kind=expense 的 amount 之和，非负整数；无 expense 流水时为 0"
      net: "有符号整数：income - expense；可为负，不取绝对值"
      period_field: "输出 period 为输入年月的 YYYY-MM：年份 4 位零填充、月份 2 位零填充（year=1, month=1 → '0001-01'）"
      empty_result: "账户存在但区间内无任何流水 → summary 正常返回，income=expense=net=0，period 按输入回填；不返回空对象、不报错"
      validation_order: "先校验 year/month（类型 → ValueError；范围 → INVALID_PERIOD），再调用上游取数（ACCOUNT_NOT_FOUND）；year/month 非法时即使 account_id 不存在也返回 INVALID_PERIOD 或 ValueError；先校验参数再查数据：输入形态错误不依赖数据存在性，也避免无谓调用上游"
      error_passthrough: "ACCOUNT_NOT_FOUND 不由 B 预判：仅当上游以 ACCOUNT_NOT_FOUND 失败时，B 以自身错误载体重抛同码（http=404、retryable=false，见 error_codes），message 原样携带但只用于诊断、不作稳定承诺；不向上游消费者暴露上游异常类型给消费者做判断（类名与继承关系不是契约事实）；实现保留 __cause__ 属诊断用途，消费者不得依赖 traceback 或 __cause__ 做判断；上游其余业务错误码视为上游违约，B 抛 RuntimeError，不新增契约错误码；上游抛出的异常若无 code 属性（上游违约或非业务错误），B 原样透传，不保证满足 error_surface"
      upstream_call: "只调用 list_entries(account_id, **{'from': from, 'to': to})，from/to 为本节 period_window 的日期；禁止传 limit（会截断汇总）；不用 get_balance（其 as_of 只能表达上界，无法表达月初下界）"

  - name: category_breakdown
    kind: request_response
    input:
      account_id: { type: string, required: true, format: uuid }
      from: { type: string, required: true, format: date }
      to: { type: string, required: true, format: date }
    output:
      items: { type: array, required: true, ref: CategoryTotal }
    errors: [ACCOUNT_NOT_FOUND, INVALID_DATE_RANGE]
    idempotent: true
    side_effects: none
    semantics:
      range: "闭区间：from <= occurred_on <= to，含首尾两天；from == to 合法（单日区间）；与上游 list_entries.semantics.range 一致"
      date_input: "from / to 只接受 YYYY-MM-DD 严格形态（长度 10、第 5/8 位为 '-'）；紧凑格式 20260101、ISO 周日期 2026-W01-4、datetime、None 或缺省 → ValueError，与上游 list_entries.semantics.date_input 同口径"
      from_parameter: "契约参数名 from 是 Python 关键字；from_ 关键字与 **{'from': ...} 等价，两者必须行为一致；传入未知关键字参数 → TypeError"
      validation_order: "先校验日期形态（ValueError）与区间方向（from > to → INVALID_DATE_RANGE），再调用上游取数（ACCOUNT_NOT_FOUND）；区间非法时即使 account_id 不存在也返回 INVALID_DATE_RANGE 或 ValueError；先校验参数再查数据：输入形态错误不依赖数据存在性，也避免无谓调用上游"
      scope: "只统计 kind=expense 的流水；income 不计入，也不产生分类项；金额单位为账户的最小货币单位，不做币种换算；v1 不提供 income 维度，需要时另开方法或提案"
      grouping: "按上游 Entry.category 原值分组（上游已去首尾空白，B 不再归一化）；空字符串 '' 是合法分组并输出 category: ''；不同分类不合并、不改写、不按大小写折叠"
      total: "该分类 expense 的 amount 之和，正整数（上游 amount 恒 >= 1）；输出中不存在 total <= 0 的项，因此没有零额分类"
      order: "按 total 降序；total 相同时按 category 的 Unicode 码点升序（Python 默认字符串比较，不受 locale 影响）；排序稳定"
      empty_result: "区间内没有 expense 流水（含账户存在但无流水）→ items: []，不报错"
      error_passthrough: "同 monthly_summary.error_passthrough：ACCOUNT_NOT_FOUND 只由上游触发后透传；上游其余业务错误码视为上游违约，B 抛 RuntimeError"
      upstream_call: "只调用 list_entries(account_id, **{'from': from, 'to': to})；禁止传 limit（会截断分类合计）"
```

### 2. `types`（仅补注释，类型与字段名不变）

```yaml
types:
  MonthlySummary:
    account_id: { type: string, format: uuid }
    period: { type: string }        # YYYY-MM，见 monthly_summary.semantics.period_field
    income: { type: integer }       # 非负：income amount 之和
    expense: { type: integer }      # 非负：expense amount 之和
    net: { type: integer }          # 有符号：income - expense
  CategoryTotal:
    category: { type: string }      # 上游 Entry.category 原值；缺省分组为 ""
    total: { type: integer }        # 正整数：该分类 expense 之和
```

### 3. `error_codes`（仅改注释，键值与 http 不变）

```yaml
error_codes:
  ACCOUNT_NOT_FOUND: { http: 404, retryable: false }  # 由上游 list_entries 触发；B 不预判、重包同码（见 error_passthrough）
  INVALID_PERIOD: { http: 400, retryable: false }     # year 不在 1..9999 或 month 不在 1..12；非整数/bool/None → ValueError
  INVALID_DATE_RANGE: { http: 400, retryable: false } # from > to；日期形态非法 → ValueError
```

### 4. `implementation`（新增顶层块，与 module-a 形态一致）

```yaml
implementation:
  module_path: modules/module-b   # 相对仓库根
  factory: "report:ReportService" # <import 名>:<类名>
  bootstrap: sys_path             # 调用方需把 module_path 加入 sys.path
  requires:
    - name: ledger
      from: contracts/module-a/v1.yaml
      description: "构造时注入的上游实例，按该契约的 implementation 字段解析"
```

与 module-a 的差异只有值；`factory` 同样遵守 `<import 名>:<类名>`。
B 当前无消费者，但一受理就写入，避免 mock 删除后出现「契约无入口」的真空
（`docs/contracts/contract-format.md:68-78`）。实现轮必须补一条入口契约测试：
按 `implementation` 解析、实例化、断言两个方法存在。`requires` 是收口轮新增
（orchestrator 预批）：入口测试必须先按 `from` 指向的契约解析并构造上游实例，
再注入 `ReportService(ledger=...)`，不能假设无参构造。

### 4a. `error_surface`（收口轮新增，与 module-a 同形态）

```yaml
error_surface:
  mechanism: exception
  attributes: [code, http_status, retryable]
  code_domain: error_codes
  notes: "异常类名不是契约事实，消费者不得依赖类型名或继承关系"
```

消费者只按 `attributes` 与 `code_domain` 读 B 的错误面。B 自己抛
`ReportError`，但类型名不是契约事实；测试只断言 `code` / `http_status` /
`retryable`。

### 4b. 删除 `mocks` 声明（收口轮）

原 `mocks.path: contracts/module-b/mocks/report_service.py` 指向不存在的文件。
B 当前 `contract.consumers` 为空，没有下游需要 mock；按
`docs/protocol/agent-protocol.md:32-34`，mock 与真实实现并存本就视为缺陷。
删除该节，理由记入 `CHANGELOG.md`；出现消费者时再按契约提供 mock 并写 parity
测试，不做两份会漂移的代码。

### 5. 关键取舍

| 决定 | 选择 | 为什么不选另一种 |
|---|---|---|
| 分类统计范围 | 只统计 `expense` | 任务写明「区间支出」；混入 income 会让 `total` 符号失去意义 |
| `total` 符号 | 正整数 | 若带符号，`income` 项会抵消支出，报表不可读；上游 `amount` 恒正 |
| 期间包含 | 闭区间，交给上游 `list_entries` | A 的 `range` 已冻结为闭区间（`contracts/module-a/v1.yaml:82`），B 自己再算一遍等于造第二份事实 |
| 校验顺序 | 先期间/日期，后账户 | 请求形态错误不应触达上游；也避免「账户不存在」掩盖非法 `month=13` |
| `ACCOUNT_NOT_FOUND` | 重包同码，不原样抛 | B 的契约只声明错误码，不声明 A 的异常类型；原样抛会把 A 的类型泄漏成 B 的接口 |
| `""` 分类 | 计入并输出 | 丢弃静默少算金额；`""` 是上游 `category_default` 的合法值（`contracts/module-a/v1.yaml:47,99`） |
| 排序 tie-break | `total` 降序 → `category` 码点升序 | 只按 `total` 会让同额分类顺序依赖插入顺序，两次请求可能不同 |
| `year` 范围 | 1..9999 | 与 `datetime.date` 可表示范围一致；更宽需要另立日期体系，属 breaking |

## 可测试判定（受理后直接转成契约测试）

`monthly_summary`（夹具均为同一 `LedgerService` 实例）：

| # | 场景 | 期望 |
|---|---|---|
| M1 | 2025-12-31 income 999；2026-01-01 income 1000；2026-01-31 expense 300；2026-02-01 expense 50；查 2026-01 | `income=1000, expense=300, net=700, period="2026-01"` |
| M2 | 2024-02-29 expense 100；查 2024-02 | `expense=100, net=-100`（闰日计入） |
| M3 | 账户存在、无流水；查 2026-01 | `income=expense=net=0, period="2026-01"` |
| M4 | 2026-03-05 income 500；查 2026-03 | `income=500, expense=0, net=500` |
| M5 | `month=0` / `month=13` / `year=0` / `year=10000` | `INVALID_PERIOD`（http 400） |
| M6 | `year="2026"` / `month=True` / `month=1.0` / `month=None` | `ValueError` |
| M7 | 不存在的 `account_id` + `month=13` | `INVALID_PERIOD`（先于账户校验） |
| M8 | 不存在的 `account_id` + 合法年月 | `ACCOUNT_NOT_FOUND`（http 404、retryable=false） |
| M9 | `year=1, month=1`、无流水 | `period="0001-01"` |
| M10 | 2026-12-31 income 5、2027-01-01 income 7；查 2026-12 | `income=5`（跨年不串月） |

`category_breakdown`：

| # | 场景 | 期望 |
|---|---|---|
| C1 | 2026-01-01 expense 100「食」；01-15 expense 50「行」；01-31 expense 50「食」；from=01-01,to=01-31 | `[{食,150},{行,50}]` |
| C2 | 单日区间 `from=to=2026-01-05`，当天 expense 20 | `[{分类,20}]`（`from == to` 合法） |
| C3 | `from=2026-02-01, to=2026-01-01` | `INVALID_DATE_RANGE`，即使账户不存在 |
| C4 | `from="20260101"` / `from="2026-W01-4"` | `ValueError` |
| C5 | income 999 分类「食」，区间内无 expense | `items=[]` |
| C6 | expense 50 且 `category` 未提供（上游输出 `""`） | `[{"category": "", "total": 50}]` |
| C7 | 三个 expense 各 50，分类分别 `"b"` / `"a"` / `""` | 顺序 `""`, `"a"`, `"b"`（total 相同，按码点） |
| C8 | 不存在的 `account_id` + 合法区间 | `ACCOUNT_NOT_FOUND` |
| C9 | 区间端点各一条（from 当天、to 当天）及端点前一天/后一天各一条 | 只含端点两条（闭区间） |
| C10 | 账户存在、无流水 | `items=[]` |

## 兼容性判定

**additive / minor**，理由逐条：

1. 只新增 `methods[].semantics`、顶层 `implementation` 与注释；`input` / `output` /
   `errors` / `types` 的字段名、类型、必填性、枚举、错误码键均未改。
2. `contract.consumers` 为空，当前没有任何下游代码依赖这些未定义行为；
   不存在「旧行为被改写」的调用方。`contract.stability: stable` 约束的是已声明的
   事实，不是留白。
3. `scripts/contract-check.sh` 的 breaking 判定（删方法 / 删类型字段 / 改字段类型 /
   删错误码）不会触发；`semantics` 与 `implementation` 不在其校验键内
   （实测见交付报告 `docs/reviews/deliveries/worker-module-b/TASK-MODULE-B-001-delivery.md`
   的验证表）。
4. 若 orchestrator 认为「把未定义行为收窄」也应算 breaking，本提案没有可回退的
   旧语义，实际影响仍是零；仍建议按 minor 记入 `CHANGELOG.md`。

## 跨模块依赖与缺口（只读契约与 mock，未读 A 源码）

B 依赖的上游事实逐条引用：

| 依赖点 | 出处 |
|---|---|
| 闭区间 `from <= occurred_on <= to` | `contracts/module-a/v1.yaml:82`（`list_entries.semantics.range`） |
| 日期只接受 `YYYY-MM-DD` 严格形态 | `contracts/module-a/v1.yaml:85`（`list_entries.semantics.date_input`） |
| `amount` 为正整数、最小货币单位 | `contracts/module-a/v1.yaml:46`（`record_entry.semantics.amount`） |
| `category` 缺省 `""` | `contracts/module-a/v1.yaml:47`、`:99`（`types.Entry.category`） |
| `ACCOUNT_NOT_FOUND` 为 404、不可重试 | `contracts/module-a/v1.yaml:110` |
| `INVALID_DATE_RANGE` 为 400、不可重试 | `contracts/module-a/v1.yaml:113` |
| B 的 `implementation` 形态 | `contracts/module-a/v1.yaml:121-124`（同为 `sys_path` + `<import>:<class>`） |

### X1（阻塞实现轮，不阻塞本提案受理）：A 未声明错误载体

A 的契约声明了 `error_codes`，但没有声明业务错误**以什么形式**回到调用方
（异常类名、属性、`code` 的取值范围）。B 要透传 `ACCOUNT_NOT_FOUND`，必须能读到
上游错误码。现在唯一可参照的是 mock 的 `LedgerError.code`
（`contracts/module-a/mocks/ledger_service.py:39-47`），但按铁律 5
（`docs/protocol/agent-protocol.md:15`「契约没写的字段、错误码、副作用，一律视为不存在」），
mock 不能当契约事实。

建议（二选一，请 orchestration 裁决）：

- **X1-a（推荐）**：让 `worker-module-a` 补一条 `list_entries.semantics.error_surface`，
  写明「业务失败抛 `LedgerError`，实例暴露 `code` / `message` / `http_status` /
  `retryable`，`code` 取 `error_codes` 的键；前置条件违反抛 `ValueError`」。纯新增，
  additive。B 之后按此实现，不需要 A 改代码。
- **X1-b**：orchestrator 明确授权 B 依赖 mock 的 `LedgerError.code` 形态，并在
  B 的集成测试里锁死；风险是 A 改异常载体时契约不报警。

在 X1 裁决前，B 的 `semantics` 只承诺「上游以 ACCOUNT_NOT_FOUND 失败时重包同码」，
不把「怎么识别」写死；识别机制留到实现轮按裁决落地。

### X2（低）：`from` 关键字的调用形态未声明

A 的字段名 `from` 在 Python 里是关键字。mock 同时接受
`list_entries(..., **{"from": ...})` 与 `from_` 别名
（`contracts/module-a/mocks/ledger_service.py:10-11,139-149`），但 A 契约没写调用形态。
B 计划统一用 `**{"from": ...}`（与契约字段名逐字一致）。建议 A 的契约测试补一条
「按 `**{"from": ...}` 调用可用」，否则真实实现可能只支持 `from_`。

## 影响面

- `contracts/module-b/v1.yaml`：+ `semantics` ×2、`implementation`、注释（本提案受理后才改）。
- `contracts/module-b/CHANGELOG.md`：新建（当前不存在）。
- `tests/contracts/module-b/**`：实现轮新增，M1-M10 / C1-C10 转成契约测试，另加
  `implementation` 入口测试与三个错误码各命中一次。
- `contracts/module-a/**`：不改；X1/X2 若采纳，由 A 走自己的提案。
- `shared/**`、`scripts/**`、`.agent/**`、`pyproject.toml`：零改动。

## 迁移步骤

1. orchestrator 在本提案标 `accepted`，并对 X1（a/b）与 X2 给出裁决。
2. `worker-module-b` 把第 1-4 节 YAML 落进 `v1.yaml`（`semantics` 与 `side_effects`
   同级；`implementation` 与 `mocks` 同级），新建 `contracts/module-b/CHANGELOG.md`，
   抄录判定。
3. 跑 `bash scripts/contract-check.sh` 与
   `bash scripts/ownership-check.sh origin/main HEAD --owner worker-module-b`。
4. 实现轮按契约写 `modules/module-b/report.py`（`ReportService`）、mock 接入、
   M/C 用例、入口测试；X1 采用 a 时等 A 的补充语义先落。
5. 通知 orchestrator：B 可进入实现；mock 删除仍按 `agent-protocol.md:34` 由
   orchestrator 在 B 合入后安排。

## 回滚方式

删除 `monthly_summary.semantics`、`category_breakdown.semantics`、顶层
`implementation` 与新增注释即可回到当前字节。当前没有任何代码/测试依赖这些键，
回滚不影响其他模块。

## 受理记录

- 2026-11-27 accepted（orchestrator），additive / minor。裁定：

1. `semantics` 全文采纳。`validation_order` 维持「先期间/日期、后账户」，契约已补理由：
   输入形态错误不依赖数据存在性，也避免无谓调用上游。
2. `category_breakdown.scope` 只统计 `expense`；契约已补「v1 不提供 income 维度，
   需要时另开方法或提案」。
3. `implementation` 采纳为 `module_path: modules/module-b`、
   `factory: "report:ReportService"`、`bootstrap: sys_path`。实现必须真实落在
   `modules/module-b/report.py`，并写入按契约字段解析、实例化、断言方法 callable
   的入口契约测试。
4. X1 走 **X1-a**：已开 `TASK-MODULE-A-003`，给 A 的契约补顶层 `error_surface`
   （mechanism=exception、attributes=[code, http_status, retryable]、
   code_domain=error_codes；异常类名不是契约事实）与
   `list_entries.semantics.from_parameter`（`**{"from": ...}` 与 `from_` 等价）。
   **X1-b 被否决**：B 不得依赖 mock 的 `.code`，不得写
   `getattr(exc, "code", None)` 这类按 mock 猜的代码；A-003 合入前，
   `ACCOUNT_NOT_FOUND` 透传只留 skip 测试骨架，状态记 blocked。
   这里只禁依赖 mock 的猜法；A-003 落地、`error_surface` 进契约后，
   按契约 `attributes` 读 `code` 是允许的（见 #6）。
5. X2：B 调用上游一律写
   `list_entries(account_id=..., **{"from": from_, "to": to})`，不依赖 `from_` 别名；
   等 A-003 把 `from_parameter` 写进契约后再评估别名。
6. 收口轮（A-003 已合入 `75dd608`）：新增 `implementation.requires`（`ledger`，
   `from: contracts/module-a/v1.yaml`）与顶层 `error_surface`（与 A 同形态）；
   按 A 的 `error_surface.attributes` 只读 `code` 实现 `ACCOUNT_NOT_FOUND`
   透传，其余业务错误码抛 `RuntimeError`，测试断言不含 A 的异常类名。
7. 收口轮删除 `mocks` 节：路径指向的文件不存在、B 无消费者；不在没有 parity
   测试的前提下提供第二份实现。
8. 复审收口：`year_month` 删「或缺省」并注明缺省由 Python 抛 `TypeError`；
   `error_passthrough` 补「无 `code` 异常原样透传」与 `__cause__` 仅诊断；
   `category_breakdown.semantics` 增 `from_parameter`；`types` 注释去掉「绝对值」。
   测试补三条：缺参 `TypeError`、无 `code` 异常原样冒泡、`from_` 别名与未知参数。

## 判定与批准

- Orchestrator 判定: **accepted**（2026-11-27）
- 批准人 / 日期: orchestrator, 2026-11-27
- 批准后需同步的任务: `TASK-MODULE-B-001`（第二轮实现）；
  `TASK-MODULE-A-003`（A 补 `error_surface` + `from_parameter`，additive，已合入
  `75dd608`）；B 收口轮按 A 的 `error_surface` 补透传并去掉 3 个 skip