"""module-b 报表域：按 contracts/module-b/v1.yaml 提供月度汇总与分类统计。

上游账目只通过构造注入的 ``ledger`` 访问（contracts/module-a/v1.yaml 的
``list_entries``）；本模块不 import module-a 的代码，也不读取其内部实现。
"""

from __future__ import annotations

import calendar
from datetime import date
from typing import Any, Protocol, TypedDict

ERROR_HTTP_STATUS: dict[str, int] = {
    "ACCOUNT_NOT_FOUND": 404,
    "INVALID_PERIOD": 400,
    "INVALID_DATE_RANGE": 400,
}

ERROR_RETRYABLE: dict[str, bool] = {code: False for code in ERROR_HTTP_STATUS}


class ReportError(Exception):
    def __init__(self, code: str, message: str) -> None:
        if code not in ERROR_HTTP_STATUS:
            raise ValueError(f"未在契约中声明的错误码: {code}")
        super().__init__(message)
        self.code = code
        self.message = message
        self.http_status = ERROR_HTTP_STATUS[code]
        self.retryable = ERROR_RETRYABLE[code]


class EntryView(TypedDict):
    amount: int
    kind: str
    occurred_on: str
    category: str


class MonthlySummary(TypedDict):
    account_id: str
    period: str
    income: int
    expense: int
    net: int


class CategoryTotal(TypedDict):
    category: str
    total: int


class LedgerPort(Protocol):
    def list_entries(self, account_id: str, **kwargs: Any) -> dict[str, list[EntryView]]: ...


class ReportService:
    def __init__(self, ledger: LedgerPort) -> None:
        self._ledger = ledger

    def monthly_summary(self, account_id: str, year: int, month: int) -> dict[str, MonthlySummary]:
        start, end = _month_bounds(year, month)
        entries = self._list_entries(account_id, start.isoformat(), end.isoformat())
        income = sum(entry["amount"] for entry in entries if entry["kind"] == "income")
        expense = sum(entry["amount"] for entry in entries if entry["kind"] == "expense")
        summary = MonthlySummary(
            account_id=account_id,
            period=f"{year:04d}-{month:02d}",
            income=income,
            expense=expense,
            net=income - expense,
        )
        return {"summary": summary}

    def category_breakdown(
        self,
        account_id: str,
        from_: str | None = None,
        to: str | None = None,
        **kwargs: Any,
    ) -> dict[str, list[CategoryTotal]]:
        from_value = _take_from_alias(from_, kwargs)
        start = _parse_date(from_value, "from")
        end = _parse_date(to, "to")
        if start > end:
            raise ReportError("INVALID_DATE_RANGE", f"from {start} 晚于 to {end}")
        entries = self._list_entries(account_id, start.isoformat(), end.isoformat())
        totals: dict[str, int] = {}
        for entry in entries:
            if entry["kind"] != "expense":
                continue
            category = entry["category"]
            totals[category] = totals.get(category, 0) + entry["amount"]
        items = [
            CategoryTotal(category=category, total=total) for category, total in totals.items()
        ]
        items.sort(key=lambda item: (-item["total"], item["category"]))
        return {"items": items}

    def _list_entries(self, account_id: str, from_value: str, to_value: str) -> list[EntryView]:
        response = self._ledger.list_entries(
            account_id=account_id, **{"from": from_value, "to": to_value}
        )
        return response["entries"]


def _require_int(value: Any, field: str) -> int:
    if not isinstance(value, int) or isinstance(value, bool):
        raise ValueError(f"{field} 必须是整数: {value!r}")
    return value


def _month_bounds(year: Any, month: Any) -> tuple[date, date]:
    year_value = _require_int(year, "year")
    month_value = _require_int(month, "month")
    if not 1 <= year_value <= 9999:
        raise ReportError("INVALID_PERIOD", f"year 必须在 1..9999: {year_value}")
    if not 1 <= month_value <= 12:
        raise ReportError("INVALID_PERIOD", f"month 必须在 1..12: {month_value}")
    last_day = calendar.monthrange(year_value, month_value)[1]
    return date(year_value, month_value, 1), date(year_value, month_value, last_day)


def _parse_date(value: Any, field: str) -> date:
    if not isinstance(value, str):
        raise ValueError(f"{field} 必须是 YYYY-MM-DD 字符串: {value!r}")
    if len(value) != 10 or value[4] != "-" or value[7] != "-":
        raise ValueError(f"{field} 必须是 YYYY-MM-DD: {value!r}")
    try:
        return date.fromisoformat(value)
    except ValueError as exc:
        raise ValueError(f"{field} 必须是合法日期: {value!r}") from exc


def _take_from_alias(from_value: str | None, kwargs: dict[str, Any]) -> str | None:
    if "from" not in kwargs:
        if kwargs:
            raise TypeError(f"未知参数: {sorted(kwargs)}")
        return from_value
    if from_value is not None:
        raise TypeError('"from" 与 from_ 只能给一个')
    value: Any = kwargs.pop("from")
    if kwargs:
        raise TypeError(f"未知参数: {sorted(kwargs)}")
    return value
