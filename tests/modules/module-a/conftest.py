"""module-a 单元测试夹具。"""

from __future__ import annotations

import importlib
import sys
from pathlib import Path
from types import ModuleType

import pytest

MODULE_A_DIR = Path(__file__).resolve().parents[3] / "modules" / "module-a"

if str(MODULE_A_DIR) not in sys.path:
    sys.path.insert(0, str(MODULE_A_DIR))


@pytest.fixture(scope="session")
def ledger() -> ModuleType:
    return importlib.import_module("ledger")


@pytest.fixture()
def service(ledger: ModuleType):
    return ledger.LedgerService()


@pytest.fixture()
def account(service) -> dict:
    return service.create_account(name="Cash", currency="CNY")["account"]
