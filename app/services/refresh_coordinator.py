"""Coalesce overlapping UI refresh requests on the Qt main thread."""

from __future__ import annotations

from dataclasses import dataclass

from PySide6.QtCore import QObject, QTimer


@dataclass
class RefreshPlan:
    """Merged refresh intent."""

    dashboard: bool = False
    holdings: bool = False
    quotes: bool = False
    full: bool = False

    def merge(self, other: RefreshPlan) -> RefreshPlan:
        self.dashboard = self.dashboard or other.dashboard
        self.holdings = self.holdings or other.holdings
        self.quotes = self.quotes or other.quotes
        self.full = self.full or other.full
        return self


class RefreshCoordinator(QObject):
    """Single-shot timer that merges refresh requests within a short window."""

    def __init__(self, parent: QObject | None = None, *, delay_ms: int = 450) -> None:
        super().__init__(parent)
        self._delay_ms = delay_ms
        self._pending = RefreshPlan()
        self._timer = QTimer(self)
        self._timer.setSingleShot(True)
        self._timer.setInterval(delay_ms)
        self._handler = None

    def bind(self, handler) -> None:
        self._handler = handler
        self._timer.timeout.connect(self._flush)

    @property
    def is_running(self) -> bool:
        return self._timer.isActive()

    def request(
        self,
        *,
        dashboard: bool = False,
        holdings: bool = False,
        quotes: bool = False,
        full: bool = False,
    ) -> None:
        self._pending.merge(
            RefreshPlan(
                dashboard=dashboard,
                holdings=holdings,
                quotes=quotes,
                full=full,
            )
        )
        if not self._timer.isActive():
            self._timer.start(self._delay_ms)

    def _flush(self) -> None:
        if self._handler is None:
            self._pending = RefreshPlan()
            return
        plan = self._pending
        self._pending = RefreshPlan()
        self._handler(plan)
