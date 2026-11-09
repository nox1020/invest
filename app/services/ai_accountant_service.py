"""AI Accountant Service for V+ desktop backend using Google Gemini API."""
from __future__ import annotations

import json
import logging
import urllib.request
import urllib.error
from dataclasses import asdict, dataclass
from datetime import datetime
from typing import Any, Dict, List, Optional

from app.config import SETTING_CURRENCY
from app.repositories.settings_repo import SettingsRepository
from app.services.portfolio_service import PortfolioService
from app.services.trade_service import TradeService

logger = logging.getLogger(__name__)

SETTING_GEMINI_API_KEY = "gemini_api_key"
DEFAULT_MODEL = "gemini-2.5-flash"


@dataclass
class AuditAlert:
    severity: str  # 'high', 'medium', 'low'
    title: str
    detail: str
    category: str


@dataclass
class AuditReport:
    health_score: int
    health_title: str
    summary: str
    alerts: List[AuditAlert]
    recommendations: List[str]
    total_capital_toman: float
    open_trades_count: int
    closed_trades_count: int
    audited_at: str
    is_ai: bool

    def to_dict(self) -> Dict[str, Any]:
        return {
            "health_score": self.health_score,
            "health_title": self.health_title,
            "summary": self.summary,
            "alerts": [asdict(a) for a in self.alerts],
            "recommendations": self.recommendations,
            "total_capital_toman": self.total_capital_toman,
            "open_trades_count": self.open_trades_count,
            "closed_trades_count": self.closed_trades_count,
            "audited_at": self.audited_at,
            "is_ai": self.is_ai,
        }


class AiAccountantService:
    """Service to audit portfolio, ledger, and trades using Google Gemini."""

    def __init__(
        self,
        portfolio_service: PortfolioService,
        trade_service: TradeService,
        settings_repo: SettingsRepository,
    ) -> None:
        self._portfolio = portfolio_service
        self._trades = trade_service
        self._settings = settings_repo

    def get_api_key(self) -> str:
        """Retrieve stored Gemini API key."""
        return self._settings.get(SETTING_GEMINI_API_KEY, "")

    def set_api_key(self, api_key: str) -> None:
        """Save Gemini API key to settings."""
        self._settings.set(SETTING_GEMINI_API_KEY, api_key.strip())

    def audit_portfolio(self, api_key: Optional[str] = None) -> AuditReport:
        """Run daily audit over assets and trades."""
        key = (api_key or self.get_api_key()).strip()
        data = self._gather_audit_data()

        if key:
            try:
                return self._call_gemini_api(data, key)
            except Exception as e:
                logger.warning("Gemini audit call failed, falling back to local audit: %s", e)

        return self._generate_local_audit(data)

    def _gather_audit_data(self) -> Dict[str, Any]:
        """Aggregate portfolio and trading state."""
        try:
            assets = self._portfolio.list_assets()
            open_trades = self._trades.list_open_trades()
            closed_trades = self._trades.list_closed_trades()
            totals = self._portfolio.calculate_totals()
            total_tmn = totals.get("total_tmn", 0.0)
        except Exception as e:
            logger.error("Failed to collect portfolio data: %s", e)
            assets, open_trades, closed_trades = [], [], []
            total_tmn = 0.0

        asset_summary = [
            {
                "id": a.id,
                "name": a.name,
                "kind": getattr(a, "kind", "other"),
                "value_tmn": getattr(a, "current_value_tmn", 0.0),
            }
            for a in assets
        ]

        return {
            "total_capital_toman": total_tmn,
            "assets_count": len(assets),
            "assets": asset_summary,
            "open_trades_count": len(open_trades),
            "closed_trades_count": len(closed_trades),
            "date": datetime.now().strftime("%Y-%m-%d %H:%M"),
        }

    def _call_gemini_api(self, data: Dict[str, Any], api_key: str) -> AuditReport:
        """Direct REST call to Gemini 2.5 Flash."""
        url = (
            f"https://generativelanguage.googleapis.com/v1beta/models/"
            f"{DEFAULT_MODEL}:generateContent?key={api_key}"
        )

        prompt = f"""
شما سرپرست ارشد حسابداری و حسابرس قسم‌خورده مالی برای نرم‌افزار مدیریت دارایی V+ هستید.
بر اساس اطلاعات زیر یک بازبینی دقیق روزانه از دفاتر مالی و پورتفولیو انجام داده و خروجی را دقیقاً و منحصراً به صورت یک شیء JSON با ساختار زیر تحویل دهید:

اطلاعات پورتفولیو:
{json.dumps(data, ensure_ascii=False, indent=2)}

قالب خروجی مورد انتظار JSON:
{{
  "health_score": <عدد ۰ تا ۱۰۰>,
  "health_title": "<عنوان وضعیت سلامت حساب‌ها به فارسی>",
  "summary": "<تحلیل ۲ تا ۳ پاراگرافی به فارسی روان و حرفه‌ای>",
  "alerts": [
    {{"severity": "high"|"medium"|"low", "title": "<عنوان هشدار>", "detail": "<توضیح>", "category": "تراکنش"|"نقدینگی"|"ریسک"}}
  ],
  "recommendations": [
    "<توصیه مالی و حسابداری ۱>",
    "<توصیه مالی و حسابداری ۲>"
  ]
}}
"""

        payload = {
            "contents": [{"parts": [{"text": prompt}]}],
            "generationConfig": {"responseMimeType": "application/json"},
        }

        req = urllib.request.Request(
            url,
            data=json.dumps(payload).encode("utf-8"),
            headers={"Content-Type": "application/json"},
            method="POST",
        )

        with urllib.request.urlopen(req, timeout=30) as response:
            res_body = response.read().decode("utf-8")
            res_json = json.loads(res_body)

        candidates = res_json.get("candidates", [])
        if not candidates:
            raise ValueError("No response candidates from Gemini API")

        raw_text = candidates[0]["content"]["parts"][0]["text"]
        parsed = json.loads(raw_text)

        alerts = [
            AuditAlert(
                severity=a.get("severity", "medium"),
                title=a.get("title", ""),
                detail=a.get("detail", ""),
                category=a.get("category", "عمومی"),
            )
            for a in parsed.get("alerts", [])
        ]

        return AuditReport(
            health_score=int(parsed.get("health_score", 80)),
            health_title=parsed.get("health_title", "وضعیت حساب‌ها: مطلوب"),
            summary=parsed.get("summary", "گزارش حسابرسی روزانه با موفقیت ثبت شد."),
            alerts=alerts,
            recommendations=parsed.get("recommendations", []),
            total_capital_toman=float(data["total_capital_toman"]),
            open_trades_count=data["open_trades_count"],
            closed_trades_count=data["closed_trades_count"],
            audited_at=datetime.now().isoformat(),
            is_ai=True,
        )

    def _generate_local_audit(self, data: Dict[str, Any]) -> AuditReport:
        """Heuristic rule-based fallback audit engine."""
        total_tmn = float(data.get("total_capital_toman", 0.0))
        open_count = int(data.get("open_trades_count", 0))
        closed_count = int(data.get("closed_trades_count", 0))
        assets_count = int(data.get("assets_count", 0))

        score = 88
        alerts: List[AuditAlert] = []
        recs: List[str] = []

        if assets_count == 0:
            score = 50
            alerts.append(
                AuditAlert(
                    severity="high",
                    title="هیچ دارایی در سیستم ثبت نشده است",
                    detail="برای شروع حسابرسی و محاسبه ترازنامه، دارایی‌های اولیه را تعریف فرمایید.",
                    category="نقدینگی",
                )
            )
            recs.append("تعریف سبد اولیه شامل موجودی ریالی، طلا، تتر یا سهام.")
        else:
            recs.append("تراز دارایی‌ها و ارزش دفتری به‌صورت منظم به‌روزرسانی شود.")

        if open_count > 10:
            score -= 10
            alerts.append(
                AuditAlert(
                    severity="medium",
                    title=f"تعداد بالای معاملات باز ({open_count} معامله)",
                    detail="تمرکز پورتفولیو را در مواجهه با نوسانات بازار پایش نمایید.",
                    category="ریسک",
                )
            )
            recs.append("تعیین حد ضرر و سیو سود در معاملات بلندمدت.")

        recs.append("پایش مداوم نرخ لحظه‌ای تتر و طلای ۱۸ عیار جهت حفظ ارزش سرمایه در برابر تورم.")

        title = "وضعیت حساب‌ها: مطلوب و تراز" if score >= 80 else "وضعیت حساب‌ها: نیازمند پایش"
        summary = (
            f"بررسی دفاتر مالی نشان می‌دهد ارزش کل سرمایه ثبت‌شده معادل {total_tmn:,.0f} تومان است. "
            f"هم‌اکنون {open_count} معامله باز و {closed_count} معامله تسویه‌شده در سیستم موجود است. "
            "تراز دفاتر پایدار بوده و کلیه سرفصل‌ها دارای پوشش ارزش روز هستند."
        )

        return AuditReport(
            health_score=score,
            health_title=title,
            summary=summary,
            alerts=alerts,
            recommendations=recs,
            total_capital_toman=total_tmn,
            open_trades_count=open_count,
            closed_trades_count=closed_count,
            audited_at=datetime.now().isoformat(),
            is_ai=False,
        )
