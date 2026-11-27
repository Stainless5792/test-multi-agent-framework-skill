"""module-a 契约测试：方法存在、参数名与必填性、字段与错误码可达。

同一套断言同时覆盖真实实现和供 module-b 使用的 Mock。

项目 dev 依赖里没有 PyYAML（`uv run pytest` 的 venv 里 import yaml 会失败），
所以这里用一个只覆盖 contracts/module-a/v1.yaml 所用 YAML 子集的解析器：
块映射、块序列、行内 `{}`/`[]`、注释、字符串/整数/布尔/null。
`test_contract_loader_reads_the_real_file` 用真实契约固定它的输出。
"""

from __future__ import annotations

import importlib
import importlib.util
import inspect
import re
import sys
import uuid
from collections.abc import Callable
from pathlib import Path
from types import ModuleType
from typing import Any

import pytest

REPO_ROOT = Path(__file__).resolve().parents[3]
CONTRACT_PATH = REPO_ROOT / "contracts" / "module-a" / "v1.yaml"
MODULE_A_DIR = REPO_ROOT / "modules" / "module-a"
MOCK_PATH = REPO_ROOT / "contracts" / "module-a" / "mocks" / "ledger_service.py"

if str(MODULE_A_DIR) not in sys.path:
    sys.path.insert(0, str(MODULE_A_DIR))

# Python 里 from 是关键字，实现用 from_ 承接契约参数 from。
ALIASES = {"from_": "from"}
PARAMETER_KINDS = (inspect.Parameter.POSITIONAL_OR_KEYWORD, inspect.Parameter.KEYWORD_ONLY)


def _strip_comment(line: str) -> str:
    quote = ""
    for index, char in enumerate(line):
        if quote:
            if char == quote:
                quote = ""
        elif char in ("'", '"'):
            quote = char
        elif char == "#":
            return line[:index]
    return line


def _split_flow(text: str) -> list[str]:
    parts: list[str] = []
    current = ""
    depth = 0
    quote = ""
    for char in text:
        if quote:
            current += char
            if char == quote:
                quote = ""
        elif char in ("'", '"'):
            quote = char
            current += char
        elif char in "{[":
            depth += 1
            current += char
        elif char in "}]":
            depth -= 1
            current += char
        elif char == "," and depth == 0:
            parts.append(current.strip())
            current = ""
        else:
            current += char
    if current.strip():
        parts.append(current.strip())
    return parts


def _parse_flow(text: str) -> object:
    text = text.strip()
    if text.startswith("[") and text.endswith("]"):
        return [_parse_flow(part) for part in _split_flow(text[1:-1])]
    if text.startswith("{") and text.endswith("}"):
        result: dict[str, object] = {}
        for part in _split_flow(text[1:-1]):
            key, _, value = part.partition(":")
            result[key.strip()] = _parse_flow(value)
        return result
    if len(text) >= 2 and text[0] == text[-1] and text[0] in ("'", '"'):
        return text[1:-1]
    if text in ("true", "false"):
        return text == "true"
    if text in ("", "null", "~"):
        return None
    try:
        return int(text)
    except ValueError:
        return text


def _parse_mapping(lines: list[tuple[int, str]], index: int, indent: int) -> tuple[object, int]:
    result: dict[str, object] = {}
    while index < len(lines) and lines[index][0] == indent:
        text = lines[index][1]
        key, separator, remainder = text.partition(":")
        if not separator:
            raise ValueError(f"无法解析映射行: {text}")
        remainder = remainder.strip()
        index += 1
        if remainder:
            result[key.strip()] = _parse_flow(remainder)
        elif index < len(lines) and lines[index][0] > indent:
            result[key.strip()], index = _parse_block(lines, index, lines[index][0])
        else:
            result[key.strip()] = None
    return result, index


def _parse_sequence(lines: list[tuple[int, str]], index: int, indent: int) -> tuple[object, int]:
    items: list[object] = []
    while index < len(lines) and lines[index][0] == indent and lines[index][1].startswith("-"):
        remainder = lines[index][1][1:].strip()
        index += 1
        item: object
        if not remainder:
            if index < len(lines) and lines[index][0] > indent:
                item, index = _parse_block(lines, index, lines[index][0])
            else:
                item = None
        elif ":" in remainder and not remainder.startswith(("{", "[")):
            key, _, value = remainder.partition(":")
            mapping: dict[str, object] = {
                key.strip(): _parse_flow(value) if value.strip() else None
            }
            if index < len(lines) and lines[index][0] > indent:
                more, index = _parse_block(lines, index, lines[index][0])
                assert isinstance(more, dict)
                mapping.update(more)
            item = mapping
        else:
            item = _parse_flow(remainder)
        items.append(item)
    return items, index


def _parse_block(lines: list[tuple[int, str]], index: int, indent: int) -> tuple[object, int]:
    if lines[index][1].startswith("-"):
        return _parse_sequence(lines, index, indent)
    return _parse_mapping(lines, index, indent)


def _load_contract(path: Path) -> dict:
    lines: list[tuple[int, str]] = []
    for raw in path.read_text(encoding="utf-8").splitlines():
        text = _strip_comment(raw).rstrip()
        if text.strip():
            lines.append((len(text) - len(text.lstrip(" ")), text.strip()))
    if not lines:
        raise ValueError(f"契约文件为空: {path}")
    value, index = _parse_block(lines, 0, lines[0][0])
    if index != len(lines):
        raise ValueError(f"契约有未解析内容，下一个有效行: {lines[index][1]}")
    if not isinstance(value, dict):
        raise ValueError("契约顶层必须是映射")
    return value


def _load_mock() -> ModuleType:
    spec = importlib.util.spec_from_file_location("module_a_mock_ledger_service", MOCK_PATH)
    assert spec is not None and spec.loader is not None, f"无法加载 Mock: {MOCK_PATH}"
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


@pytest.fixture(scope="session")
def contract() -> dict:
    return _load_contract(CONTRACT_PATH)


@pytest.fixture(scope="session", params=["real", "mock"])
def ledger(request: pytest.FixtureRequest) -> ModuleType:
    if request.param == "mock":
        return _load_mock()
    return importlib.import_module("ledger")


def _methods(contract: dict) -> list[dict]:
    return contract["methods"]


def test_contract_loader_reads_the_real_file(contract: dict) -> None:
    body = contract["contract"]
    assert (body["name"], body["module"], body["version"], body["status"]) == (
        "LedgerService",
        "module-a",
        "v1",
        "approved",
    )
    methods = {method["name"]: method for method in contract["methods"]}
    assert set(methods["record_entry"]["input"]) == {
        "account_id",
        "amount",
        "kind",
        "occurred_on",
        "category",
        "memo",
    }
    assert contract["types"]["Entry"]["kind"]["enum"] == ["income", "expense"]
    assert contract["error_codes"]["DUPLICATE_ACCOUNT_NAME"] == {
        "http": 409,
        "retryable": False,
    }


def test_contract_declares_expected_surface(contract: dict) -> None:
    body = contract["contract"]
    assert body["name"] == "LedgerService"
    assert body["module"] == "module-a"
    assert body["version"] == "v1"
    assert {method["name"] for method in _methods(contract)} == {
        "create_account",
        "record_entry",
        "get_balance",
        "list_entries",
    }
    for method in _methods(contract):
        for error in method["errors"]:
            assert error in contract["error_codes"], f"{method['name']} 引用了未声明错误码 {error}"


def test_methods_exist_with_contract_parameters(contract: dict, ledger: ModuleType) -> None:
    service = ledger.LedgerService()
    for method in _methods(contract):
        name = method["name"]
        assert hasattr(service, name), f"缺少契约方法 {name}"
        signature = inspect.signature(getattr(service, name))
        declared = method["input"]
        actual: dict[str, inspect.Parameter] = {}
        accepts_extra_keywords = False
        for parameter in signature.parameters.values():
            if parameter.kind is inspect.Parameter.VAR_KEYWORD:
                accepts_extra_keywords = True
                continue
            assert parameter.kind in PARAMETER_KINDS, f"{name} 有非法参数 {parameter.name}"
            actual[ALIASES.get(parameter.name, parameter.name)] = parameter
        assert set(actual) == set(declared), f"{name} 参数名与契约不一致: {sorted(actual)}"
        for parameter_name, spec in declared.items():
            required = bool(spec.get("required"))
            has_default = actual[parameter_name].default is not inspect.Parameter.empty
            assert has_default is not required, f"{name}.{parameter_name} 必填性与契约不一致"
        if "from" in declared:
            assert accepts_extra_keywords or "from" in actual, f"{name} 无法接收契约参数 from"


def test_returns_contract_shaped_fields(contract: dict, ledger: ModuleType) -> None:
    types = contract["types"]
    service = ledger.LedgerService()
    account = service.create_account(name="Cash", currency="USD")["account"]
    assert set(account) == set(types["Account"])

    entry = service.record_entry(
        account_id=account["id"],
        amount=500,
        kind="income",
        occurred_on="2026-01-10",
        category="salary",
        memo="jan",
    )["entry"]
    assert set(entry) == set(types["Entry"])
    assert entry["kind"] in types["Entry"]["kind"]["enum"]

    balance = service.get_balance(account_id=account["id"])["balance"]
    assert set(balance) == set(types["Balance"])
    assert balance["amount"] == 500

    entries = service.list_entries(account_id=account["id"])["entries"]
    assert [set(item) for item in entries] == [set(types["Entry"])]


def test_list_entries_accepts_contract_keyword_from(ledger: ModuleType) -> None:
    service = ledger.LedgerService()
    account = service.create_account(name="Cash", currency="USD")["account"]
    service.record_entry(
        account_id=account["id"], amount=1, kind="income", occurred_on="2026-01-01"
    )
    entries = service.list_entries(account_id=account["id"], **{"from": "2026-01-01"})["entries"]
    assert len(entries) == 1


def _open_account(service: Any) -> dict:
    return service.create_account(name="Cash", currency="USD")["account"]


def _invalid_currency(service: Any) -> None:
    service.create_account(name="Euro", currency="eur")


def _duplicate_account_name(service: Any) -> None:
    service.create_account(name="Cash", currency="USD")
    service.create_account(name="Cash", currency="USD")


def _account_not_found(service: Any) -> None:
    service.get_balance(account_id=str(uuid.uuid4()))


def _invalid_amount(service: Any) -> None:
    account = _open_account(service)
    service.record_entry(
        account_id=account["id"], amount=0, kind="income", occurred_on="2026-01-01"
    )


def _invalid_category(service: Any) -> None:
    account = _open_account(service)
    service.record_entry(
        account_id=account["id"],
        amount=100,
        kind="expense",
        occurred_on="2026-01-01",
        category="   ",
    )


def _invalid_date_range(service: Any) -> None:
    account = _open_account(service)
    service.list_entries(account_id=account["id"], **{"from": "2026-02-01", "to": "2026-01-01"})


TRIGGERS: dict[str, Callable[[Any], None]] = {
    "INVALID_CURRENCY": _invalid_currency,
    "DUPLICATE_ACCOUNT_NAME": _duplicate_account_name,
    "ACCOUNT_NOT_FOUND": _account_not_found,
    "INVALID_AMOUNT": _invalid_amount,
    "INVALID_CATEGORY": _invalid_category,
    "INVALID_DATE_RANGE": _invalid_date_range,
}


def test_error_codes_declared_by_contract_are_all_triggered(contract: dict) -> None:
    assert set(TRIGGERS) == set(contract["error_codes"])


@pytest.mark.parametrize("code", sorted(TRIGGERS))
def test_error_codes_are_reachable(contract: dict, ledger: ModuleType, code: str) -> None:
    spec = contract["error_codes"][code]
    with pytest.raises(ledger.LedgerError) as excinfo:
        TRIGGERS[code](ledger.LedgerService())
    assert excinfo.value.code == code
    assert excinfo.value.http_status == spec["http"]
    assert excinfo.value.retryable is spec["retryable"]


def test_error_tables_match_contract(contract: dict, ledger: ModuleType) -> None:
    codes = contract["error_codes"]
    assert set(ledger.ERROR_HTTP_STATUS) == set(codes)
    for code, spec in codes.items():
        assert ledger.ERROR_HTTP_STATUS[code] == spec["http"]
        assert ledger.ERROR_RETRYABLE[code] is spec["retryable"]


def test_mock_is_standalone(ledger: ModuleType) -> None:
    assert ledger.__file__ is not None
    path = Path(ledger.__file__)
    if path.parent.name != "mocks":
        pytest.skip("该断言只针对 Mock")
    source = path.read_text(encoding="utf-8")
    assert re.search(r"^\s*(from|import)\s+modules\b", source, re.MULTILINE) is None


# 提案 20261127-entrypoint.md（已受理，方案 A）：入口由契约 implementation 唯一决定。
def test_contract_declares_implementation_entrypoint(contract: dict) -> None:
    implementation = contract.get("implementation")
    assert isinstance(implementation, dict), "契约缺少 implementation 块"

    factory = str(implementation.get("factory", ""))
    module_name, _, attr = factory.partition(":")
    assert module_name and attr, f"factory 必须写成 <import 名>:<类名>: {factory!r}"
    assert implementation.get("module_path"), "implementation.module_path 不能为空"
    assert implementation.get("bootstrap") == "sys_path"


def test_contract_declares_semantics_for_stateful_methods(contract: dict) -> None:
    methods = {method["name"]: method for method in _methods(contract)}

    for name in ("record_entry", "get_balance", "list_entries"):
        assert "semantics" in methods[name], f"{name} 缺少 semantics（提案 20261127-semantics.md）"
    assert set(methods["record_entry"]["semantics"]) >= {
        "amount",
        "category_default",
        "category_normalization",
        "memo_default",
        "memo_normalization",
        "date_input",
        "precondition_violation",
    }
    assert {"as_of", "amount", "date_input"} <= set(methods["get_balance"]["semantics"])
    assert {"range", "order", "limit", "date_input"} <= set(methods["list_entries"]["semantics"])


def test_implementation_entrypoint_resolves(contract: dict) -> None:
    implementation = contract["implementation"]
    module_path = (REPO_ROOT / implementation["module_path"]).resolve()
    assert module_path.is_dir(), f"implementation.module_path 不存在: {module_path}"
    if str(module_path) not in sys.path:
        sys.path.insert(0, str(module_path))

    module_name, _, attr = implementation["factory"].partition(":")
    module = importlib.import_module(module_name)
    assert module.__file__ is not None
    assert Path(module.__file__).resolve().is_relative_to(module_path), (
        f"factory 解析到的模块不在 module_path 下: {module.__file__}"
    )

    service = getattr(module, attr)()
    for method in _methods(contract):
        assert callable(getattr(service, method["name"], None)), (
            f"入口对象缺少契约方法 {method['name']}"
        )


# 提案 20261127-semantics.md（已受理）：日期输入只接受 YYYY-MM-DD，长度必须为 10。
@pytest.mark.parametrize("occurred_on", ["20260101", "2026-W01-4"])
def test_record_entry_rejects_non_yyyy_mm_dd(ledger: ModuleType, occurred_on: str) -> None:
    service = ledger.LedgerService()
    account = service.create_account(name="Cash", currency="USD")["account"]

    with pytest.raises(ValueError):
        service.record_entry(
            account_id=account["id"],
            amount=1,
            kind="income",
            occurred_on=occurred_on,
        )


@pytest.mark.parametrize("value", ["20260101", "2026-W01-4"])
@pytest.mark.parametrize(
    ("method", "field"),
    [("list_entries", "from"), ("list_entries", "to"), ("get_balance", "as_of")],
)
def test_read_side_rejects_non_yyyy_mm_dd(
    ledger: ModuleType, method: str, field: str, value: str
) -> None:
    service = ledger.LedgerService()
    account = service.create_account(name="Cash", currency="USD")["account"]

    with pytest.raises(ValueError):
        getattr(service, method)(account_id=account["id"], **{field: value})
