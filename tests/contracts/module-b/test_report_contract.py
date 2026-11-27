from __future__ import annotations

import importlib
import inspect
import sys
from pathlib import Path
from typing import Any

import pytest
import yaml  # type: ignore[import-untyped]

ROOT = Path(__file__).resolve().parents[3]
CONTRACT_PATH = ROOT / "contracts/module-b/v1.yaml"


@pytest.fixture(scope="module")
def contract() -> dict[str, Any]:
    loaded = yaml.safe_load(CONTRACT_PATH.read_text(encoding="utf-8"))
    assert isinstance(loaded, dict)
    return loaded


def _resolve_module(implementation: dict[str, Any]) -> Any:
    module_path = str(ROOT / implementation["module_path"])
    if module_path not in sys.path:
        sys.path.insert(0, module_path)
    return importlib.import_module(implementation["factory"].split(":", 1)[0])


@pytest.fixture(scope="module")
def report_module(contract: dict[str, Any]) -> Any:
    return _resolve_module(contract["implementation"])


_MONTHLY_SEMANTICS = {
    "period_window",
    "year_month",
    "income",
    "expense",
    "net",
    "period_field",
    "empty_result",
    "validation_order",
    "error_passthrough",
    "upstream_call",
}

_CATEGORY_SEMANTICS = {
    "range",
    "date_input",
    "validation_order",
    "scope",
    "grouping",
    "total",
    "order",
    "empty_result",
    "error_passthrough",
    "upstream_call",
}


class _StubLedger:
    def __init__(self, entries: list[dict[str, Any]] | None = None) -> None:
        self.entries = entries or []
        self.calls: list[dict[str, Any]] = []

    def list_entries(self, account_id: str, **kwargs: Any) -> dict[str, list[dict[str, Any]]]:
        self.calls.append({"account_id": account_id, **kwargs})
        return {"entries": [dict(entry) for entry in self.entries]}


class _ExplodingLedger:
    def list_entries(self, account_id: str, **kwargs: Any) -> dict[str, list[dict[str, Any]]]:
        raise AssertionError("校验顺序错误：非法输入不应触达上游")


class _UpstreamBusinessError(Exception):
    def __init__(self, code: str, http_status: int = 400, retryable: bool = False) -> None:
        super().__init__(f"upstream {code}")
        self.code = code
        self.http_status = http_status
        self.retryable = retryable


def _entry(amount: int, kind: str, category: str = "a") -> dict[str, Any]:
    return {
        "amount": amount,
        "kind": kind,
        "occurred_on": "2026-01-10",
        "category": category,
    }


def test_contract_declares_accepted_semantics(contract: dict[str, Any]) -> None:
    methods = {method["name"]: method for method in contract["methods"]}

    assert _MONTHLY_SEMANTICS <= set(methods["monthly_summary"]["semantics"])
    assert _CATEGORY_SEMANTICS <= set(methods["category_breakdown"]["semantics"])

    implementation = contract["implementation"]
    assert implementation["module_path"] == "modules/module-b"
    assert implementation["factory"] == "report:ReportService"
    assert implementation["bootstrap"] == "sys_path"
    assert [item["name"] for item in implementation["requires"]] == ["ledger"]
    assert implementation["requires"][0]["from"] == "contracts/module-a/v1.yaml"


def test_contract_declares_error_surface(contract: dict[str, Any]) -> None:
    surface = contract["error_surface"]

    assert surface["mechanism"] == "exception"
    assert set(surface["attributes"]) == {"code", "http_status", "retryable"}
    assert surface["code_domain"] == "error_codes"
    assert contract["error_codes"]
    assert surface["code_domain"] in contract


def test_entrypoint_resolves_with_requires(contract: dict[str, Any], report_module: Any) -> None:
    requires = contract["implementation"]["requires"]
    upstream_path = ROOT / requires[0]["from"]
    upstream_contract = yaml.safe_load(upstream_path.read_text(encoding="utf-8"))
    upstream_implementation = upstream_contract["implementation"]
    upstream_module = _resolve_module(upstream_implementation)
    upstream_class = getattr(upstream_module, upstream_implementation["factory"].split(":", 1)[1])

    service = report_module.ReportService(ledger=upstream_class())

    assert report_module.ReportService.__name__ == "ReportService"
    assert callable(service.monthly_summary)
    assert callable(service.category_breakdown)


def test_method_parameters_match_contract(report_module: Any) -> None:
    monthly = inspect.signature(report_module.ReportService.monthly_summary).parameters
    assert list(monthly) == ["self", "account_id", "year", "month"]
    for name in ("account_id", "year", "month"):
        assert monthly[name].default is inspect.Parameter.empty

    category = inspect.signature(report_module.ReportService.category_breakdown).parameters
    assert "account_id" in category
    assert "to" in category
    assert category["account_id"].default is inspect.Parameter.empty
    assert any(parameter.kind is inspect.Parameter.VAR_KEYWORD for parameter in category.values())


def test_category_breakdown_requires_from_and_to(report_module: Any) -> None:
    service = report_module.ReportService(_StubLedger())

    with pytest.raises(ValueError):
        service.category_breakdown("acct", to="2026-01-31")
    with pytest.raises(ValueError):
        service.category_breakdown("acct", **{"from": "2026-01-01"})


def test_monthly_summary_shape(report_module: Any) -> None:
    ledger = _StubLedger([_entry(100, "income"), _entry(30, "expense")])
    result = report_module.ReportService(ledger).monthly_summary("acct", 2026, 1)

    assert set(result) == {"summary"}
    assert result["summary"] == {
        "account_id": "acct",
        "period": "2026-01",
        "income": 100,
        "expense": 30,
        "net": 70,
    }
    assert set(result["summary"]) == {
        "account_id",
        "period",
        "income",
        "expense",
        "net",
    }


def test_category_breakdown_shape(report_module: Any) -> None:
    ledger = _StubLedger([_entry(30, "expense", "a"), _entry(999, "income", "a")])
    result = report_module.ReportService(ledger).category_breakdown(
        "acct", **{"from": "2026-01-01", "to": "2026-01-31"}
    )

    assert set(result) == {"items"}
    assert result["items"] == [{"category": "a", "total": 30}]
    assert set(result["items"][0]) == {"category", "total"}


def test_invalid_period_code(report_module: Any) -> None:
    service = report_module.ReportService(_StubLedger())

    with pytest.raises(report_module.ReportError) as exc:
        service.monthly_summary("acct", 2026, 13)

    assert exc.value.code == "INVALID_PERIOD"
    assert exc.value.http_status == 400
    assert exc.value.retryable is False


def test_invalid_date_range_code(report_module: Any) -> None:
    service = report_module.ReportService(_StubLedger())

    with pytest.raises(report_module.ReportError) as exc:
        service.category_breakdown("acct", **{"from": "2026-02-01", "to": "2026-01-01"})

    assert exc.value.code == "INVALID_DATE_RANGE"
    assert exc.value.http_status == 400
    assert exc.value.retryable is False


def test_validation_order_does_not_touch_upstream(report_module: Any) -> None:
    service = report_module.ReportService(_ExplodingLedger())

    with pytest.raises(report_module.ReportError):
        service.monthly_summary("acct", 2026, 0)
    with pytest.raises(report_module.ReportError):
        service.category_breakdown("acct", **{"from": "2026-02-01", "to": "2026-01-01"})


def test_upstream_call_uses_contract_field_names(report_module: Any) -> None:
    ledger = _StubLedger()
    service = report_module.ReportService(ledger)

    service.monthly_summary("acct", 2026, 1)
    service.category_breakdown("acct", **{"from": "2026-01-01", "to": "2026-01-31"})

    assert ledger.calls == [
        {"account_id": "acct", "from": "2026-01-01", "to": "2026-01-31"},
        {"account_id": "acct", "from": "2026-01-01", "to": "2026-01-31"},
    ]


def test_account_not_found_passthrough(report_module: Any) -> None:
    class _MissingAccountLedger:
        def list_entries(self, account_id: str, **kwargs: Any) -> dict[str, list[dict[str, Any]]]:
            raise _UpstreamBusinessError("ACCOUNT_NOT_FOUND", http_status=404)

    service = report_module.ReportService(_MissingAccountLedger())

    with pytest.raises(report_module.ReportError) as exc:
        service.monthly_summary("missing", 2026, 1)

    assert exc.value.code == "ACCOUNT_NOT_FOUND"
    assert exc.value.http_status == 404
    assert exc.value.retryable is False


def test_other_upstream_business_code_is_runtime_error(report_module: Any) -> None:
    class _UnexpectedCodeLedger:
        def list_entries(self, account_id: str, **kwargs: Any) -> dict[str, list[dict[str, Any]]]:
            raise _UpstreamBusinessError("INVALID_AMOUNT")

    service = report_module.ReportService(_UnexpectedCodeLedger())

    with pytest.raises(RuntimeError) as exc:
        service.monthly_summary("acct", 2026, 1)

    assert "INVALID_AMOUNT" in str(exc.value)
