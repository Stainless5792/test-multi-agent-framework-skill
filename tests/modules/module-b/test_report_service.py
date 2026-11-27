from __future__ import annotations

import importlib
import importlib.util
import sys
from pathlib import Path
from typing import Any

import pytest

ROOT = Path(__file__).resolve().parents[3]
REPORT_DIR = ROOT / "modules/module-b"
LEDGER_MOCK = ROOT / "contracts/module-a/mocks/ledger_service.py"


def _load_report_module() -> Any:
    if str(REPORT_DIR) not in sys.path:
        sys.path.insert(0, str(REPORT_DIR))
    return importlib.import_module("report")


def _load_ledger_mock() -> Any:
    spec = importlib.util.spec_from_file_location("module_a_mock_ledger", LEDGER_MOCK)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


@pytest.fixture(scope="module")
def report_module() -> Any:
    return _load_report_module()


@pytest.fixture
def ledger() -> Any:
    return _load_ledger_mock().LedgerService()


@pytest.fixture
def service(report_module: Any, ledger: Any) -> Any:
    return report_module.ReportService(ledger)


class _ExplodingLedger:
    def list_entries(self, account_id: str, **kwargs: Any) -> dict[str, list[dict[str, Any]]]:
        raise AssertionError("校验顺序错误：非法输入不应触达上游")


def _account(ledger: Any, name: str = "Cash") -> str:
    return ledger.create_account(name=name, currency="CNY")["account"]["id"]


# --- monthly_summary：M1-M10 -------------------------------------------------


def test_m1_monthly_summary_counts_only_natural_month(service: Any, ledger: Any) -> None:
    account = _account(ledger)
    ledger.record_entry(account_id=account, amount=999, kind="income", occurred_on="2025-12-31")
    ledger.record_entry(account_id=account, amount=1000, kind="income", occurred_on="2026-01-01")
    ledger.record_entry(account_id=account, amount=300, kind="expense", occurred_on="2026-01-31")
    ledger.record_entry(account_id=account, amount=50, kind="expense", occurred_on="2026-02-01")

    assert service.monthly_summary(account, 2026, 1) == {
        "summary": {
            "account_id": account,
            "period": "2026-01",
            "income": 1000,
            "expense": 300,
            "net": 700,
        }
    }


def test_m2_leap_day_is_included(service: Any, ledger: Any) -> None:
    account = _account(ledger)
    ledger.record_entry(account_id=account, amount=100, kind="expense", occurred_on="2024-02-29")

    summary = service.monthly_summary(account, 2024, 2)["summary"]

    assert (summary["income"], summary["expense"], summary["net"]) == (0, 100, -100)


def test_m3_empty_account_returns_zeros(service: Any, ledger: Any) -> None:
    account = _account(ledger)

    assert service.monthly_summary(account, 2026, 1) == {
        "summary": {
            "account_id": account,
            "period": "2026-01",
            "income": 0,
            "expense": 0,
            "net": 0,
        }
    }


def test_m4_income_only(service: Any, ledger: Any) -> None:
    account = _account(ledger)
    ledger.record_entry(account_id=account, amount=500, kind="income", occurred_on="2026-03-05")

    summary = service.monthly_summary(account, 2026, 3)["summary"]

    assert (summary["income"], summary["expense"], summary["net"]) == (500, 0, 500)


@pytest.mark.parametrize(("year", "month"), [(2026, 0), (2026, 13), (0, 1), (10000, 1)])
def test_m5_period_out_of_range(
    service: Any, report_module: Any, ledger: Any, year: int, month: int
) -> None:
    account = _account(ledger)

    with pytest.raises(report_module.ReportError) as exc:
        service.monthly_summary(account, year, month)

    assert exc.value.code == "INVALID_PERIOD"
    assert exc.value.http_status == 400
    assert exc.value.retryable is False


@pytest.mark.parametrize(
    ("year", "month"),
    [("2026", 1), (2026, True), (2026, 1.0), (2026, None)],
)
def test_m6_non_integer_period_is_value_error(
    service: Any, ledger: Any, year: Any, month: Any
) -> None:
    account = _account(ledger)

    with pytest.raises(ValueError):
        service.monthly_summary(account, year, month)


def test_m7_invalid_period_precedes_account_lookup(report_module: Any) -> None:
    service = report_module.ReportService(_ExplodingLedger())

    with pytest.raises(report_module.ReportError) as exc:
        service.monthly_summary("00000000-0000-0000-0000-000000000000", 2026, 13)

    assert exc.value.code == "INVALID_PERIOD"


def test_m8_unknown_account(service: Any, report_module: Any) -> None:
    with pytest.raises(report_module.ReportError) as exc:
        service.monthly_summary("00000000-0000-0000-0000-000000000000", 2026, 1)

    assert exc.value.code == "ACCOUNT_NOT_FOUND"
    assert exc.value.http_status == 404
    assert exc.value.retryable is False


def test_m9_period_year_is_zero_padded(service: Any, ledger: Any) -> None:
    account = _account(ledger)

    assert service.monthly_summary(account, 1, 1)["summary"]["period"] == "0001-01"


def test_m10_cross_year_entries_do_not_leak(service: Any, ledger: Any) -> None:
    account = _account(ledger)
    ledger.record_entry(account_id=account, amount=5, kind="income", occurred_on="2026-12-31")
    ledger.record_entry(account_id=account, amount=7, kind="income", occurred_on="2027-01-01")

    assert service.monthly_summary(account, 2026, 12)["summary"]["income"] == 5


# --- category_breakdown：C1-C10 ----------------------------------------------


def test_c1_groups_expense_by_category(service: Any, ledger: Any) -> None:
    account = _account(ledger)
    ledger.record_entry(
        account_id=account,
        amount=100,
        kind="expense",
        occurred_on="2026-01-01",
        category="食",
    )
    ledger.record_entry(
        account_id=account,
        amount=50,
        kind="expense",
        occurred_on="2026-01-15",
        category="行",
    )
    ledger.record_entry(
        account_id=account,
        amount=50,
        kind="expense",
        occurred_on="2026-01-31",
        category="食",
    )

    assert service.category_breakdown(account, **{"from": "2026-01-01", "to": "2026-01-31"}) == {
        "items": [
            {"category": "食", "total": 150},
            {"category": "行", "total": 50},
        ]
    }


def test_c2_single_day_range(service: Any, ledger: Any) -> None:
    account = _account(ledger)
    ledger.record_entry(
        account_id=account,
        amount=20,
        kind="expense",
        occurred_on="2026-01-05",
        category="日",
    )

    assert service.category_breakdown(account, **{"from": "2026-01-05", "to": "2026-01-05"}) == {
        "items": [{"category": "日", "total": 20}]
    }


def test_c3_invalid_range_precedes_account_lookup(report_module: Any) -> None:
    service = report_module.ReportService(_ExplodingLedger())

    with pytest.raises(report_module.ReportError) as exc:
        service.category_breakdown(
            "00000000-0000-0000-0000-000000000000",
            **{"from": "2026-02-01", "to": "2026-01-01"},
        )

    assert exc.value.code == "INVALID_DATE_RANGE"
    assert exc.value.http_status == 400
    assert exc.value.retryable is False


@pytest.mark.parametrize("bad_date", ["20260101", "2026-W01-4"])
def test_c4_non_yyyy_mm_dd_is_value_error(service: Any, bad_date: str) -> None:
    with pytest.raises(ValueError):
        service.category_breakdown(
            "00000000-0000-0000-0000-000000000000",
            **{"from": bad_date, "to": "2026-01-31"},
        )


def test_c5_income_only_yields_empty_items(service: Any, ledger: Any) -> None:
    account = _account(ledger)
    ledger.record_entry(
        account_id=account,
        amount=999,
        kind="income",
        occurred_on="2026-01-10",
        category="食",
    )

    assert service.category_breakdown(account, **{"from": "2026-01-01", "to": "2026-01-31"}) == {
        "items": []
    }


def test_c6_missing_category_is_its_own_bucket(service: Any, ledger: Any) -> None:
    account = _account(ledger)
    ledger.record_entry(account_id=account, amount=50, kind="expense", occurred_on="2026-01-10")

    assert service.category_breakdown(account, **{"from": "2026-01-01", "to": "2026-01-31"}) == {
        "items": [{"category": "", "total": 50}]
    }


def test_c7_ties_sort_by_category_code_point(service: Any, ledger: Any) -> None:
    account = _account(ledger)
    for category in ("b", "a", None):
        kwargs = {} if category is None else {"category": category}
        ledger.record_entry(
            account_id=account,
            amount=50,
            kind="expense",
            occurred_on="2026-01-10",
            **kwargs,
        )

    items = service.category_breakdown(account, **{"from": "2026-01-01", "to": "2026-01-31"})[
        "items"
    ]

    assert [item["category"] for item in items] == ["", "a", "b"]


def test_c8_unknown_account(service: Any, report_module: Any) -> None:
    with pytest.raises(report_module.ReportError) as exc:
        service.category_breakdown(
            "00000000-0000-0000-0000-000000000000",
            **{"from": "2026-01-01", "to": "2026-01-31"},
        )

    assert exc.value.code == "ACCOUNT_NOT_FOUND"
    assert exc.value.http_status == 404
    assert exc.value.retryable is False


def test_c9_range_includes_both_endpoints(service: Any, ledger: Any) -> None:
    account = _account(ledger)
    for day, category in (
        ("2026-01-09", "before"),
        ("2026-01-10", "start"),
        ("2026-01-20", "end"),
        ("2026-01-21", "after"),
    ):
        ledger.record_entry(
            account_id=account,
            amount=10,
            kind="expense",
            occurred_on=day,
            category=category,
        )

    items = service.category_breakdown(account, **{"from": "2026-01-10", "to": "2026-01-20"})[
        "items"
    ]

    assert [item["category"] for item in items] == ["end", "start"]


def test_c10_empty_account_yields_empty_items(service: Any, ledger: Any) -> None:
    account = _account(ledger)

    assert service.category_breakdown(account, **{"from": "2026-01-01", "to": "2026-01-31"}) == {
        "items": []
    }
