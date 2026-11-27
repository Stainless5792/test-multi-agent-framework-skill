"""module-a 账目域 LedgerService 单元测试。

行为依据 contracts/module-a/v1.yaml 与 modules/module-a/README.md。
每个测试只验证一个可观察行为。
"""

from __future__ import annotations

import uuid
from datetime import datetime

import pytest


def _record(
    service,
    account: dict,
    amount: int,
    kind: str,
    occurred_on: str,
    **kwargs,
) -> dict:
    return service.record_entry(
        account_id=account["id"],
        amount=amount,
        kind=kind,
        occurred_on=occurred_on,
        **kwargs,
    )["entry"]


# 1. 余额 = income 合计 - expense 合计（多笔混合）
def test_balance_is_income_minus_expense(service, account):
    _record(service, account, 10000, "income", "2026-01-01")
    _record(service, account, 2500, "expense", "2026-01-02")
    _record(service, account, 300, "income", "2026-01-03")
    _record(service, account, 700, "expense", "2026-01-04")

    balance = service.get_balance(account_id=account["id"])["balance"]

    assert balance["amount"] == 10000 - 2500 + 300 - 700


# 2. from/to 是闭区间，单边可省略
def test_list_entries_range_is_closed_at_both_ends(service, account):
    _record(service, account, 1, "income", "2026-01-01")
    _record(service, account, 1, "income", "2026-01-02")
    _record(service, account, 1, "income", "2026-01-03")

    entries = service.list_entries(
        account_id=account["id"], **{"from": "2026-01-02"}, to="2026-01-03"
    )["entries"]

    assert [entry["occurred_on"] for entry in entries] == ["2026-01-02", "2026-01-03"]


def test_list_entries_from_only_has_no_lower_bound_issue(service, account):
    _record(service, account, 1, "income", "2026-01-01")
    _record(service, account, 1, "income", "2026-01-03")

    entries = service.list_entries(account_id=account["id"], from_="2026-01-02")["entries"]

    assert [entry["occurred_on"] for entry in entries] == ["2026-01-03"]


def test_list_entries_to_only_has_no_upper_bound_issue(service, account):
    _record(service, account, 1, "income", "2026-01-01")
    _record(service, account, 1, "income", "2026-01-03")

    entries = service.list_entries(account_id=account["id"], to="2026-01-02")["entries"]

    assert [entry["occurred_on"] for entry in entries] == ["2026-01-01"]


# 3. 按 occurred_on 升序，同日保持写入顺序；limit 取前 N 条
def test_list_entries_sorted_by_occurred_on(service, account):
    _record(service, account, 1, "income", "2026-01-03")
    _record(service, account, 1, "income", "2026-01-01")
    _record(service, account, 1, "income", "2026-01-02")

    entries = service.list_entries(account_id=account["id"])["entries"]

    assert [entry["occurred_on"] for entry in entries] == [
        "2026-01-01",
        "2026-01-02",
        "2026-01-03",
    ]


def test_list_entries_keeps_insertion_order_within_same_day(service, account):
    _record(service, account, 1, "income", "2026-01-01", memo="first")
    _record(service, account, 1, "income", "2026-01-01", memo="second")
    _record(service, account, 1, "income", "2026-01-01", memo="third")

    entries = service.list_entries(account_id=account["id"])["entries"]

    assert [entry["memo"] for entry in entries] == ["first", "second", "third"]


def test_list_entries_limit_returns_first_n_after_sorting(service, account):
    _record(service, account, 1, "income", "2026-01-03")
    _record(service, account, 1, "income", "2026-01-01")
    _record(service, account, 1, "income", "2026-01-02")

    entries = service.list_entries(account_id=account["id"], limit=2)["entries"]

    assert [entry["occurred_on"] for entry in entries] == ["2026-01-01", "2026-01-02"]


# 4. get_balance(as_of=...) 含当天边界，之后的流水不计入
def test_get_balance_as_of_includes_entries_on_cutoff_day(service, account):
    _record(service, account, 100, "income", "2026-01-05")
    _record(service, account, 40, "expense", "2026-01-05")

    balance = service.get_balance(account_id=account["id"], as_of="2026-01-05")["balance"]

    assert balance["amount"] == 60


def test_get_balance_as_of_excludes_entries_after_cutoff_day(service, account):
    _record(service, account, 100, "income", "2026-01-05")
    _record(service, account, 999, "income", "2026-01-06")

    balance = service.get_balance(account_id=account["id"], as_of="2026-01-05")["balance"]

    assert balance["amount"] == 100


# 5. 两个账户互不串账
def test_accounts_do_not_share_entries(service, account):
    other = service.create_account(name="Other", currency="CNY")["account"]
    _record(service, account, 100, "income", "2026-01-01")
    _record(service, other, 700, "income", "2026-01-01")

    first_balance = service.get_balance(account_id=account["id"])["balance"]
    second_balance = service.get_balance(account_id=other["id"])["balance"]
    first_entries = service.list_entries(account_id=account["id"])["entries"]

    assert first_balance["amount"] == 100
    assert second_balance["amount"] == 700
    assert [entry["account_id"] for entry in first_entries] == [account["id"]]


# 6. 重名账户返回 409
def test_duplicate_account_name_raises_conflict(service, account, ledger):
    with pytest.raises(ledger.LedgerError) as excinfo:
        service.create_account(name="Cash", currency="CNY")

    assert excinfo.value.code == "DUPLICATE_ACCOUNT_NAME"
    assert excinfo.value.http_status == 409


# 7. 非法币种返回 INVALID_CURRENCY
@pytest.mark.parametrize("currency", ["usd", "US", "ABC", None, 123])
def test_create_account_rejects_invalid_currency(service, ledger, currency):
    with pytest.raises(ledger.LedgerError) as excinfo:
        service.create_account(name="Cash", currency=currency)

    assert excinfo.value.code == "INVALID_CURRENCY"


# 8. 不存在的 account_id 在三个方法都返回 ACCOUNT_NOT_FOUND
def test_record_entry_rejects_unknown_account(service, ledger):
    with pytest.raises(ledger.LedgerError) as excinfo:
        service.record_entry(
            account_id="00000000-0000-0000-0000-000000000000",
            amount=100,
            kind="income",
            occurred_on="2026-01-01",
        )

    assert excinfo.value.code == "ACCOUNT_NOT_FOUND"


def test_get_balance_rejects_unknown_account(service, ledger):
    with pytest.raises(ledger.LedgerError) as excinfo:
        service.get_balance(account_id="00000000-0000-0000-0000-000000000000")

    assert excinfo.value.code == "ACCOUNT_NOT_FOUND"


def test_list_entries_rejects_unknown_account(service, ledger):
    with pytest.raises(ledger.LedgerError) as excinfo:
        service.list_entries(account_id="00000000-0000-0000-0000-000000000000")

    assert excinfo.value.code == "ACCOUNT_NOT_FOUND"


# 9. 非法金额返回 INVALID_AMOUNT
@pytest.mark.parametrize("amount", [0, -5, 1.5, True])
def test_record_entry_rejects_invalid_amount(service, account, ledger, amount):
    with pytest.raises(ledger.LedgerError) as excinfo:
        service.record_entry(
            account_id=account["id"],
            amount=amount,
            kind="income",
            occurred_on="2026-01-01",
        )

    assert excinfo.value.code == "INVALID_AMOUNT"


# 10. 非法 category 返回 INVALID_CATEGORY
@pytest.mark.parametrize("category", ["", "   ", "x" * 65, "a\nb"])
def test_record_entry_rejects_invalid_category(service, account, ledger, category):
    with pytest.raises(ledger.LedgerError) as excinfo:
        service.record_entry(
            account_id=account["id"],
            amount=100,
            kind="income",
            occurred_on="2026-01-01",
            category=category,
        )

    assert excinfo.value.code == "INVALID_CATEGORY"


# 11. from > to 返回 INVALID_DATE_RANGE
def test_list_entries_rejects_reversed_date_range(service, account, ledger):
    with pytest.raises(ledger.LedgerError) as excinfo:
        service.list_entries(account_id=account["id"], from_="2026-01-02", to="2026-01-01")

    assert excinfo.value.code == "INVALID_DATE_RANGE"


# 12. category/memo 缺省为 ""；提供时 category 去首尾空白
def test_record_entry_defaults_category_and_memo_to_empty_string(service, account):
    entry = _record(service, account, 100, "income", "2026-01-01")

    assert entry["category"] == ""
    assert entry["memo"] == ""


def test_record_entry_strips_category_whitespace(service, account):
    entry = _record(service, account, 100, "income", "2026-01-01", category="  salary  ")

    assert entry["category"] == "salary"


# 13. 支持契约字面 from 与别名 from_；同时给抛 TypeError
def test_list_entries_accepts_contract_literal_from(service, account):
    _record(service, account, 1, "income", "2026-01-01")
    _record(service, account, 1, "income", "2026-01-02")

    entries = service.list_entries(account_id=account["id"], **{"from": "2026-01-02"})["entries"]

    assert [entry["occurred_on"] for entry in entries] == ["2026-01-02"]


def test_list_entries_accepts_from_alias(service, account):
    _record(service, account, 1, "income", "2026-01-01")
    _record(service, account, 1, "income", "2026-01-02")

    entries = service.list_entries(account_id=account["id"], from_="2026-01-02")["entries"]

    assert [entry["occurred_on"] for entry in entries] == ["2026-01-02"]


def test_list_entries_rejects_both_from_and_alias(service, account):
    with pytest.raises(TypeError):
        service.list_entries(
            account_id=account["id"],
            from_="2026-01-01",
            **{"from": "2026-01-02"},
        )


# 14. kind 非枚举值抛 ValueError（契约无对应错误码，刻意行为）
def test_record_entry_rejects_unknown_kind(service, account):
    with pytest.raises(ValueError):
        service.record_entry(
            account_id=account["id"],
            amount=100,
            kind="transfer",
            occurred_on="2026-01-01",
        )


# 15. occurred_on 非法格式抛 ValueError
@pytest.mark.parametrize("occurred_on", ["2026-13-01", "01/02/2026"])
def test_record_entry_rejects_invalid_occurred_on(service, account, occurred_on):
    with pytest.raises(ValueError):
        service.record_entry(
            account_id=account["id"],
            amount=100,
            kind="income",
            occurred_on=occurred_on,
        )


# 16. limit 非正整数抛 ValueError
@pytest.mark.parametrize("limit", [0, True])
def test_list_entries_rejects_invalid_limit(service, account, limit):
    with pytest.raises(ValueError):
        service.list_entries(account_id=account["id"], limit=limit)


# 17. id 是合法 UUID，created_at 可被 fromisoformat 解析
def test_account_id_is_uuid_and_created_at_is_isoformat(account):
    uuid.UUID(account["id"])
    datetime.fromisoformat(account["created_at"])


def test_entry_id_is_uuid_and_created_at_is_isoformat(service, account):
    entry = _record(service, account, 100, "income", "2026-01-01")

    uuid.UUID(entry["id"])
    datetime.fromisoformat(entry["created_at"])
