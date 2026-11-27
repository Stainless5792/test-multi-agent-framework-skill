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

四个方法的可观察行为都写在契约 `v1.yaml` 的 `semantics` 块里，本文件不再复制：

- `create_account`：`name` 去首尾空白、唯一性范围（同一实例内 + 跨币种）、
  `currency` 不做大小写归一化、校验顺序 `name → currency → 重名`、
  `id` / `created_at` 的生成规则（提案 `proposals/20261127-create-account-semantics.md`）。
- `record_entry` / `get_balance` / `list_entries`：排序、`from` / `to` 区间开闭、
  `as_of` 边界、`category` / `memo` 缺省与归一化、日期输入格式
  （提案 `proposals/20261127-semantics.md`）。
- 变更记录与「唯一性范围在 v1 冻结」的注记见 `CHANGELOG.md`。

### `currency` 表版本

`ledger.ISO4217_CODES` 是 v1 快照，只收**现行**代码；新增或退市代码属语义变更，
需提案。已按此移除 `CUC`（2021 并入 `CUP`）与 `SLL`（2022 并入 `SLE`），
两者现在返回 `INVALID_CURRENCY`。

### 异常口径

- 业务失败 → `LedgerError`，`code` 只取契约 `error_codes` 的 6 个键。
- **必填值缺失 / 违反契约已声明的类型** → `ValueError`，不进 `error_codes`。
  例如 `create_account(name="")`（必填值缺失）、`kind` 非枚举、日期格式非法、
  `limit <= 0`。`create_account` 的 `name` 与 `record_entry` 的可选 `category`
  不同类：前者是必填值缺失，后者是可选字段的命名规则违反（后者有
  `INVALID_CATEGORY`）。

## 下游

`worker-module-b` 并行开发时使用 `contracts/module-a/mocks/ledger_service.py`，
它与契约的公开面、字段和错误码一致，可独立加载。真实实现接入后按协议删除 Mock。

## 提案与变更记录

- `proposals/20261127-entrypoint.md`：accepted（方案 A）。入口改由契约
  `implementation` 声明，入口测试见 `tests/contracts/module-a/`；
  `TASK-MODULE-A-002`（`modules/module_a/` 可导入包）为 backlog。
- `proposals/20261127-semantics.md`：accepted（additive / minor）。契约补齐
  `semantics` 块，日期输入收紧为 `YYYY-MM-DD`。
- `proposals/20261127-create-account-semantics.md`：accepted（additive / minor）。
  `create_account` 的三条留白写进契约；唯一性范围在 v1 冻结。
- 变更记录：`contracts/module-a/CHANGELOG.md`。