# module-a 账目域

实现 `contracts/module-a/v1.yaml`（`LedgerService` v1）。契约是唯一事实源，
本文件只记录契约没写死、但调用方必须知道的边界决定。

## 入口

```python
import sys

sys.path.insert(0, "modules/module-a")
import ledger

service = ledger.LedgerService()          # 内存态，每个实例一套账户
account = service.create_account(name="现金", currency="CNY")["account"]
entry = service.record_entry(
    account_id=account["id"],
    amount=10000,                                  # 最小货币单位正整数（分）
    kind="income",
    occurred_on="2026-01-05",
    category="salary",
)["entry"]
balance = service.get_balance(account_id=account["id"])["balance"]
entries = service.list_entries(account_id=account["id"], **{"from": "2026-01-01"})["entries"]
```

`list_entries` 的契约参数名是 `from`，Python 里是关键字，因此既支持
`**{"from": ...}`（与契约字面一致），也支持别名 `from_=`。

## 返回值

返回值是普通 `dict`，键名与契约 `types` 完全一致：

- `create_account` → `{"account": Account}`
- `record_entry` → `{"entry": Entry}`
- `get_balance` → `{"balance": Balance}`
- `list_entries` → `{"entries": [Entry, ...]}`

`Entry.category` / `Entry.memo` 是契约声明为 `string` 的非必填输入；缺省时输出
空字符串 `""`，保证字段类型始终是 `string`。

## 错误

失败抛 `ledger.LedgerError`：

| 属性 | 含义 |
|---|---|
| `code` | 契约 `error_codes` 的键，只可能是六个之一 |
| `http_status` | 契约里对应的 `http` |
| `retryable` | 契约里对应的 `retryable`，v1 全为 `false` |

## 契约未定义、由本实现补齐的规则

这些规则不改变契约语义，只是把契约留白填成可测的行为；契约补齐后以契约为准。

| 项 | 本实现的规则 |
|---|---|
| `currency` | 必须是现行 ISO 4217 三字母代码，表见 `ledger.ISO4217_CODES` |
| 账户名 | 去首尾空白后非空；命名空间为「本实例全局」，与币种无关；重名返回 409 |
| `category` | 提供时去空白后 1..64 字符、不含控制字符，否则 `INVALID_CATEGORY` |
| `memo` | 提供时必须为字符串，去首尾空白后原样保存 |
| `occurred_on` / `as_of` / `from` / `to` | ISO 8601 日期（`YYYY-MM-DD`）或 `date` 对象 |
| `limit` | 提供时为正整数，按 `occurred_on` 升序（同日按写入顺序）取前 N 条 |
| `get_balance.as_of` | 含当天：只累计 `occurred_on <= as_of` 的流水 |
| `list_entries` 范围 | 两端闭区间：`from <= occurred_on <= to`，单边可省略 |
| `amount` | `int` 且 `> 0`，`bool` 不算整数 |

契约没有给「`kind` 非枚举值」「日期格式非法」「`limit` 非正」错误码，这些是调用方
违反契约声明的类型，本实现抛 `ValueError`，不属于契约错误面。详见任务报告 RISKS。

## 下游

`worker-module-b` 并行开发时使用 `contracts/module-a/mocks/ledger_service.py`，
它与本文件的公开面、字段和错误码一致，可独立加载。真实实现接入后按协议删除 Mock。