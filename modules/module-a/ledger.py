"""module-a 账目域实现，对应契约 contracts/module-a/v1.yaml。

入口：``LedgerService``。方法返回与契约同名的普通 dict（Account / Entry / Balance），
失败时抛 ``LedgerError``，其 ``code`` 只能是契约 error_codes 中的键。

导入方式：把 ``modules/module-a`` 放到 ``sys.path`` 后 ``import ledger``。
"""

from __future__ import annotations

import uuid
from datetime import UTC, date, datetime
from typing import Any, Literal, TypedDict

Kind = Literal["income", "expense"]

ERROR_HTTP_STATUS: dict[str, int] = {
    "INVALID_CURRENCY": 400,
    "DUPLICATE_ACCOUNT_NAME": 409,
    "ACCOUNT_NOT_FOUND": 404,
    "INVALID_AMOUNT": 400,
    "INVALID_CATEGORY": 400,
    "INVALID_DATE_RANGE": 400,
}

ERROR_RETRYABLE: dict[str, bool] = {code: False for code in ERROR_HTTP_STATUS}

CATEGORY_MAX_LENGTH = 64


class LedgerError(Exception):
    """契约错误码的载体：code 与 http_status 由契约 error_codes 决定。"""

    def __init__(self, code: str, message: str) -> None:
        if code not in ERROR_HTTP_STATUS:
            raise ValueError(f"未在契约中声明的错误码: {code}")
        super().__init__(message)
        self.code = code
        self.message = message
        self.http_status = ERROR_HTTP_STATUS[code]
        self.retryable = ERROR_RETRYABLE[code]


class Account(TypedDict):
    id: str
    name: str
    currency: str
    created_at: str


class Entry(TypedDict):
    id: str
    account_id: str
    amount: int
    kind: Kind
    occurred_on: str
    category: str
    memo: str
    created_at: str


class Balance(TypedDict):
    account_id: str
    currency: str
    amount: int


# ISO 4217 现行代码表。契约 input.currency 的 format=iso4217 由它判定。
# 标准更新时整表替换，不按需增删。
ISO4217_CODES: frozenset[str] = frozenset(
    """
    AED AFN ALL AMD ANG AOA ARS AUD AWG AZN BAM BBD BDT BGN BHD BIF BMD BND
    BOB BOV BRL BSD BTN BWP BYN BZD CAD CDF CHE CHF CHW CLF CLP CNY COP COU
    CRC CUC CUP CVE CZK DJF DKK DOP DZD EGP ERN ETB EUR FJD FKP GBP GEL GHS
    GIP GMD GNF GTQ GYD HKD HNL HTG HUF IDR ILS INR IQD IRR ISK JMD JOD JPY
    KES KGS KHR KMF KPW KRW KWD KYD KZT LAK LBP LKR LRD LSL LYD MAD MDL MGA
    MKD MMK MNT MOP MRU MUR MVR MWK MXN MXV MYR MZN NAD NGN NIO NOK NPR NZD
    OMR PAB PEN PGK PHP PKR PLN PYG QAR RON RSD RUB RWF SAR SBD SCR SDG SEK
    SGD SHP SLE SLL SOS SRD SSP STN SVC SYP SZL THB TJS TMT TND TOP TRY TTD
    TWD TZS UAH UGX USD USN UYI UYU UYW UZS VED VES VND VUV WST XAF XAG XAU
    XBA XBB XBC XBD XCD XCG XDR XOF XPD XPF XPT XSU XTS XUA XXX YER ZAR ZMW
    ZWG
    """.split()
)

_KINDS: tuple[Kind, Kind] = ("income", "expense")


def _now_iso() -> str:
    return datetime.now(UTC).isoformat()


def _parse_date(value: str | date, field: str) -> date:
    if isinstance(value, datetime):
        raise ValueError(f"{field} 必须是日期（YYYY-MM-DD），不是 datetime")
    if isinstance(value, date):
        return value
    if not isinstance(value, str):
        raise ValueError(f"{field} 必须是 ISO 8601 日期字符串")
    # 契约只接受 YYYY-MM-DD：仅卡长度不够，ISO 周日期（2026-W01-4）也是 10 字符
    if len(value) != 10 or value[4] != "-" or value[7] != "-":
        raise ValueError(f"{field} 必须是 YYYY-MM-DD: {value!r}")
    try:
        return date.fromisoformat(value)
    except ValueError as exc:
        raise ValueError(f"{field} 必须是 ISO 8601 日期（YYYY-MM-DD）: {value!r}") from exc


def _normalize_category(category: str | None) -> str:
    if category is None:
        return ""
    if not isinstance(category, str):
        raise ValueError("category 提供时必须是字符串")
    normalized = category.strip()
    if not normalized or len(normalized) > CATEGORY_MAX_LENGTH:
        raise LedgerError(
            "INVALID_CATEGORY",
            f"category 必须为 1..{CATEGORY_MAX_LENGTH} 个字符",
        )
    if any(ord(char) < 32 for char in normalized):
        raise LedgerError("INVALID_CATEGORY", "category 不能包含控制字符")
    return normalized


def _normalize_memo(memo: str | None) -> str:
    if memo is None:
        return ""
    if not isinstance(memo, str):
        raise ValueError("memo 提供时必须是字符串")
    return memo.strip()


def _take_from_alias(alias_value: str | date | None, kwargs: dict[str, Any]) -> str | date | None:
    """契约参数名是 ``from``（Python 关键字），用 **kwargs 接住该关键字。"""
    if "from" not in kwargs:
        if kwargs:
            raise TypeError(f"未知参数: {sorted(kwargs)}")
        return alias_value
    if alias_value is not None:
        raise TypeError('"from" 与 from_ 只能给一个')
    value = kwargs.pop("from")
    if kwargs:
        raise TypeError(f"未知参数: {sorted(kwargs)}")
    return value


class LedgerService:
    """内存版账目服务。四个方法的行为与错误码以契约 v1 为准。"""

    def __init__(self) -> None:
        self._accounts: dict[str, Account] = {}
        self._entries: dict[str, list[Entry]] = {}
        self._account_names: set[str] = set()

    def create_account(self, name: str, currency: str) -> dict[str, Account]:
        if not isinstance(name, str) or not name.strip():
            raise ValueError("name 必须是非空字符串")
        normalized_name = name.strip()
        if not isinstance(currency, str) or currency not in ISO4217_CODES:
            raise LedgerError("INVALID_CURRENCY", f"不是有效的 ISO 4217 币种: {currency!r}")
        if normalized_name in self._account_names:
            raise LedgerError("DUPLICATE_ACCOUNT_NAME", f"账户名已被占用: {normalized_name!r}")
        account: Account = {
            "id": str(uuid.uuid4()),
            "name": normalized_name,
            "currency": currency,
            "created_at": _now_iso(),
        }
        self._accounts[account["id"]] = account
        self._entries[account["id"]] = []
        self._account_names.add(normalized_name)
        return {"account": Account(**account)}

    def record_entry(
        self,
        account_id: str,
        amount: int,
        kind: Kind,
        occurred_on: str | date,
        category: str | None = None,
        memo: str | None = None,
    ) -> dict[str, Entry]:
        account = self._require_account(account_id)
        if not isinstance(amount, int) or isinstance(amount, bool) or amount <= 0:
            raise LedgerError("INVALID_AMOUNT", f"amount 必须是正整数: {amount!r}")
        if kind not in _KINDS:
            raise ValueError(f"kind 必须是 income 或 expense: {kind!r}")
        occurred = _parse_date(occurred_on, "occurred_on")
        entry: Entry = {
            "id": str(uuid.uuid4()),
            "account_id": account["id"],
            "amount": amount,
            "kind": kind,
            "occurred_on": occurred.isoformat(),
            "category": _normalize_category(category),
            "memo": _normalize_memo(memo),
            "created_at": _now_iso(),
        }
        self._entries[account["id"]].append(entry)
        return {"entry": Entry(**entry)}

    def get_balance(self, account_id: str, as_of: str | date | None = None) -> dict[str, Balance]:
        account = self._require_account(account_id)
        cutoff = _parse_date(as_of, "as_of") if as_of is not None else None
        total = 0
        for entry in self._entries[account["id"]]:
            if cutoff is not None and date.fromisoformat(entry["occurred_on"]) > cutoff:
                continue
            total += entry["amount"] if entry["kind"] == "income" else -entry["amount"]
        balance: Balance = {
            "account_id": account["id"],
            "currency": account["currency"],
            "amount": total,
        }
        return {"balance": balance}

    def list_entries(
        self,
        account_id: str,
        from_: str | date | None = None,
        to: str | date | None = None,
        limit: int | None = None,
        **kwargs: Any,
    ) -> dict[str, list[Entry]]:
        from_ = _take_from_alias(from_, kwargs)
        account = self._require_account(account_id)
        start = _parse_date(from_, "from") if from_ is not None else None
        end = _parse_date(to, "to") if to is not None else None
        if start is not None and end is not None and start > end:
            raise LedgerError("INVALID_DATE_RANGE", f"from {start} 晚于 to {end}")
        if limit is not None and (
            not isinstance(limit, int) or isinstance(limit, bool) or limit <= 0
        ):
            raise ValueError(f"limit 提供时必须是正整数: {limit!r}")
        selected = [
            entry
            for entry in self._entries[account["id"]]
            if (start is None or date.fromisoformat(entry["occurred_on"]) >= start)
            and (end is None or date.fromisoformat(entry["occurred_on"]) <= end)
        ]
        selected.sort(key=lambda entry: entry["occurred_on"])
        if limit is not None:
            selected = selected[:limit]
        return {"entries": [Entry(**entry) for entry in selected]}

    def _require_account(self, account_id: str) -> Account:
        account = self._accounts.get(account_id) if isinstance(account_id, str) else None
        if account is None:
            raise LedgerError("ACCOUNT_NOT_FOUND", f"账户不存在: {account_id!r}")
        return account
