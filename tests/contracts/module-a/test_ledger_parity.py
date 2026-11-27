"""real ↔ mock parity：契约面之外的留白语义一旦两边漂移，这里失败。

覆盖：正常记账、`list_entries` 排序（含同日顺序）、`as_of` 边界、
`category` / `memo` 缺省与归一化，以及 4 条错误码路径。

`id` / `created_at` / `account_id` 是每个实例独有的值，不参与比较；比较的是
契约与提案 `20261127-semantics.md` 描述的可观察结果。
"""

from __future__ import annotations

import importlib
import importlib.util
import sys
import uuid
from collections.abc import Callable
from pathlib import Path
from types import ModuleType
from typing import Any

import pytest

REPO_ROOT = Path(__file__).resolve().parents[3]
MODULE_A_DIR = REPO_ROOT / "modules" / "module-a"
MOCK_PATH = REPO_ROOT / "contracts" / "module-a" / "mocks" / "ledger_service.py"

if str(MODULE_A_DIR) not in sys.path:
    sys.path.insert(0, str(MODULE_A_DIR))

EntryView = list[tuple[str, int, str, str, str]]


def _load_mock() -> ModuleType:
    spec = importlib.util.spec_from_file_location("module_a_parity_mock", MOCK_PATH)
    assert spec is not None and spec.loader is not None, f"无法加载 Mock: {MOCK_PATH}"
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


@pytest.fixture(scope="module")
def pair() -> tuple[ModuleType, ModuleType]:
    return importlib.import_module("ledger"), _load_mock()


def _open(module: ModuleType, name: str = "Cash", currency: str = "CNY") -> tuple[Any, dict]:
    service = module.LedgerService()
    return service, service.create_account(name=name, currency=currency)["account"]


def _record(
    service: Any, account: dict, amount: int, kind: str, occurred_on: str, **extra: Any
) -> None:
    service.record_entry(
        account_id=account["id"],
        amount=amount,
        kind=kind,
        occurred_on=occurred_on,
        **extra,
    )


def _view(entries: list[dict]) -> EntryView:
    return [
        (entry["occurred_on"], entry["amount"], entry["kind"], entry["category"], entry["memo"])
        for entry in entries
    ]


def _error(module: ModuleType, action: Callable[[], None]) -> dict[str, Any]:
    try:
        action()
    except module.LedgerError as exc:
        return {"code": exc.code, "http_status": exc.http_status, "retryable": exc.retryable}
    except Exception as exc:  # 非契约异常也是差异，必须如实暴露而不是吞掉
        return {"unexpected_exception": type(exc).__name__}
    return {"unexpected_exception": "none"}


def _normal_bookkeeping(module: ModuleType) -> dict[str, Any]:
    service, account = _open(module)
    _record(service, account, 10000, "income", "2026-01-01")
    _record(service, account, 2500, "expense", "2026-01-01")
    _record(service, account, 999, "income", "2026-01-02")

    balance = service.get_balance(account_id=account["id"])["balance"]
    entries = service.list_entries(account_id=account["id"])["entries"]
    return {
        "balance": (balance["currency"], balance["amount"]),
        "entries": _view(entries),
    }


def _ordering(module: ModuleType) -> dict[str, Any]:
    service, account = _open(module)
    _record(service, account, 1, "income", "2026-01-03", memo="third")
    _record(service, account, 2, "income", "2026-01-01", memo="first-a")
    _record(service, account, 3, "income", "2026-01-01", memo="first-b")
    _record(service, account, 4, "income", "2026-01-02", memo="second")

    return {"entries": _view(service.list_entries(account_id=account["id"])["entries"])}


def _ordering_with_limit(module: ModuleType) -> dict[str, Any]:
    service, account = _open(module)
    _record(service, account, 1, "income", "2026-01-03")
    _record(service, account, 2, "income", "2026-01-01")
    _record(service, account, 3, "income", "2026-01-02")

    return {"entries": _view(service.list_entries(account_id=account["id"], limit=2)["entries"])}


def _as_of_boundary(module: ModuleType) -> dict[str, Any]:
    service, account = _open(module)
    _record(service, account, 100, "income", "2026-01-05")
    _record(service, account, 40, "expense", "2026-01-05")
    _record(service, account, 999, "income", "2026-01-06")

    return {
        "balance": service.get_balance(account_id=account["id"], as_of="2026-01-05")["balance"][
            "amount"
        ]
    }


def _defaults_and_normalization(module: ModuleType) -> dict[str, Any]:
    service, account = _open(module)
    _record(service, account, 100, "income", "2026-01-01")
    _record(
        service,
        account,
        200,
        "income",
        "2026-01-02",
        category="  salary  ",
        memo="  jan  ",
    )

    return {"entries": _view(service.list_entries(account_id=account["id"])["entries"])}


def _invalid_amount(module: ModuleType) -> dict[str, Any]:
    service, account = _open(module)
    return _error(module, lambda: _record(service, account, 0, "income", "2026-01-01"))


def _invalid_category(module: ModuleType) -> dict[str, Any]:
    service, account = _open(module)
    return _error(
        module,
        lambda: _record(service, account, 100, "income", "2026-01-01", category="   "),
    )


def _invalid_date_range(module: ModuleType) -> dict[str, Any]:
    service, account = _open(module)
    return _error(
        module,
        lambda: service.list_entries(
            account_id=account["id"], **{"from": "2026-02-01", "to": "2026-01-01"}
        ),
    )


def _unknown_account(module: ModuleType) -> dict[str, Any]:
    service, _ = _open(module)
    return _error(module, lambda: service.get_balance(account_id=str(uuid.uuid4())))


def _duplicate_account_name(module: ModuleType) -> dict[str, Any]:
    service, _ = _open(module)

    def second_same_name() -> None:
        service.create_account(name="Cash", currency="USD")

    return _error(module, second_same_name)


def _date_input_rejects_non_yyyy_mm_dd(module: ModuleType) -> dict[str, Any]:
    service, account = _open(module)
    results: dict[str, Any] = {}

    def rejects(value: str) -> Callable[[], None]:
        def action() -> None:
            _record(service, account, 1, "income", value)

        return action

    for label, value in (("compact", "20260101"), ("iso_week", "2026-W01-4")):
        results[label] = _error(module, rejects(value))
    return results


SCENARIOS: dict[str, Callable[[ModuleType], dict[str, Any]]] = {
    "as_of_boundary": _as_of_boundary,
    "date_input_rejects_non_yyyy_mm_dd": _date_input_rejects_non_yyyy_mm_dd,
    "defaults_and_normalization": _defaults_and_normalization,
    "duplicate_account_name": _duplicate_account_name,
    "invalid_amount": _invalid_amount,
    "invalid_category": _invalid_category,
    "invalid_date_range": _invalid_date_range,
    "normal_bookkeeping": _normal_bookkeeping,
    "ordering": _ordering,
    "ordering_with_limit": _ordering_with_limit,
    "unknown_account": _unknown_account,
}


@pytest.mark.parametrize("scenario", sorted(SCENARIOS))
def test_real_and_mock_agree(pair: tuple[ModuleType, ModuleType], scenario: str) -> None:
    real, mock = pair
    real_view = SCENARIOS[scenario](real)
    mock_view = SCENARIOS[scenario](mock)

    assert real_view == mock_view, f"{scenario}: 真实实现与 mock 可观察结果不一致"
