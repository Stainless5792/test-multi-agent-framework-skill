# module-a 账目域

实现 `contracts/module-a/v1.yaml`（`LedgerService` v1）。契约是唯一事实源：
入口、方法、字段、错误码与可观察语义都以契约为准，本文件不重复声明。

## 入口

入口由契约的 `implementation` 块唯一决定，调用方不要硬编码本模块的目录：

```python
import importlib
import sys

# 值取自 contracts/module-a/v1.yaml 的 implementation 块
impl = {"module_path": "modules/module-a", "factory": "ledger:LedgerService"}
sys.path.insert(0, impl["module_path"])
module_name, attr = impl["factory"].split(":")
service = getattr(importlib.import_module(module_name), attr)()   # 内存态，每实例一套账户

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

`Entry.category` / `Entry.memo` 缺省输出空字符串 `""`（契约
`types.Entry` 已注明，归一化规则见 `record_entry.semantics`）。

## 错误

失败抛 `LedgerError`：

| 属性 | 含义 |
|---|---|
| `code` | 契约 `error_codes` 的键，只可能是六个之一 |
| `http_status` | 契约里对应的 `http` |
| `retryable` | 契约里对应的 `retryable`，v1 全为 `false` |

## 契约已声明的语义（2026-11-27 起）

排序、`from` / `to` 区间开闭、`as_of` 边界、`category` / `memo` 缺省与归一化、
日期输入格式，以及 `kind` 非枚举 / 非法日期 / `limit <= 0` 抛 `ValueError`，
全部写在契约 `v1.yaml` 的 `semantics` 块里（提案
`proposals/20261127-semantics.md`，变更记录 `CHANGELOG.md`）。本文件不再复制。

仍不在契约、由实现补齐的只有：

| 项 | 本实现的规则 |
|---|---|
| `currency` | 现行 ISO 4217 三字母代码，区分大小写，表见 `ledger.ISO4217_CODES` |
| 账户名 | 去首尾空白后非空；命名空间为「本实例全局」，与币种无关；重名返回 409 |

## 下游

`worker-module-b` 并行开发时使用 `contracts/module-a/mocks/ledger_service.py`，
它与契约的公开面、字段和错误码一致，可独立加载。真实实现接入后按协议删除 Mock。

## 提案与变更记录

- `proposals/20261127-entrypoint.md`：accepted（方案 A）。入口改由契约
  `implementation` 声明，入口测试见 `tests/contracts/module-a/`；
  `TASK-MODULE-A-002`（`modules/module_a/` 可导入包）为 backlog。
- `proposals/20261127-semantics.md`：accepted（additive / minor）。契约补齐
  `semantics` 块，日期输入收紧为 `YYYY-MM-DD`。
- 变更记录：`contracts/module-a/CHANGELOG.md`。