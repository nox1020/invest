"""Tests for refresh coalescing on the Qt main thread."""

from __future__ import annotations

import pytest
from PySide6.QtCore import QCoreApplication

from app.services.refresh_coordinator import RefreshCoordinator, RefreshPlan


@pytest.fixture(scope="module")
def qapp():
    app = QCoreApplication.instance()
    if app is None:
        app = QCoreApplication([])
    return app


def test_merge_refresh_plans() -> None:
    a = RefreshPlan(dashboard=True)
    b = RefreshPlan(holdings=True, quotes=True)
    a.merge(b)
    assert a.dashboard is True
    assert a.holdings is True
    assert a.quotes is True


def test_coordinator_flushes_merged_plan(qapp) -> None:
    coord = RefreshCoordinator()
    seen: list[RefreshPlan] = []

    def handler(plan: RefreshPlan) -> None:
        seen.append(plan)

    coord.bind(handler)
    coord.request(holdings=True)
    coord.request(quotes=True)
    coord._timer.stop()
    coord._flush()

    assert len(seen) == 1
    assert seen[0].holdings is True
    assert seen[0].quotes is True
