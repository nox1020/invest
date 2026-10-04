"""Live gold quotes from free Iranian 18k feeds (WallGold / TGJU)."""

from __future__ import annotations

import json
import logging
import time
import urllib.request
from dataclasses import dataclass

from app.config import (
    DEFAULT_GOLD_API_URL,
    DEFAULT_MARKET_URL,
    DEFAULT_TGJU_AJAX_URL,
)

logger = logging.getLogger(__name__)

DEFAULT_CACHE_SECONDS = 60
WALLGOLD_SYMBOL = "GLD_18C_750TMN"


@dataclass
class GoldQuote:
    """Gold price per gram in Tomans (Iranian 18k)."""

    price_toman: float
    change_24h: float | None
    source: str
    fetched_at: float

    @property
    def age_seconds(self) -> float:
        return max(0.0, time.time() - self.fetched_at)


def _as_float(value) -> float | None:
    if value is None:
        return None
    if isinstance(value, (int, float)):
        return float(value)
    text = str(value).strip().replace(",", "").replace("٬", "")
    if not text:
        return None
    try:
        return float(text)
    except ValueError:
        return None


def parse_wallgold_gold(payload) -> GoldQuote | None:
    markets = None
    if isinstance(payload, list):
        markets = payload
    elif isinstance(payload, dict):
        if isinstance(payload.get("result"), list):
            markets = payload["result"]
        elif isinstance(payload.get("data"), list):
            markets = payload["data"]
    if not markets:
        return None
    for item in markets:
        if not isinstance(item, dict):
            continue
        if str(item.get("symbol") or "").upper() != WALLGOLD_SYMBOL:
            continue
        cap = item.get("marketCap") if isinstance(item.get("marketCap"), dict) else item
        price = _as_float(cap.get("lastPrice")) or _as_float(cap.get("lastBuyPrice"))
        if price is None or price <= 0:
            return None
        raw_change = _as_float(cap.get("24hChangePrice"))
        if raw_change is None:
            change = None
        elif abs(raw_change) <= 1:
            change = raw_change * 100.0
        else:
            change = raw_change
        return GoldQuote(
            price_toman=price,
            change_24h=change,
            source="wallgold",
            fetched_at=time.time(),
        )
    return None


def parse_tgju_gold(payload) -> GoldQuote | None:
    if not isinstance(payload, dict):
        return None
    current = payload.get("current")
    if not isinstance(current, dict):
        return None
    geram = current.get("geram18")
    if not isinstance(geram, dict):
        return None
    irr = _as_float(geram.get("p"))
    if irr is None or irr <= 0:
        return None
    return GoldQuote(
        price_toman=irr / 10.0,
        change_24h=_as_float(geram.get("dp")),
        source="tgju",
        fetched_at=time.time(),
    )


def parse_persiantoolbox_gold(payload, *, assume_24k_spot: bool = True) -> GoldQuote | None:
    if not isinstance(payload, dict):
        return None
    data = payload.get("data") if isinstance(payload.get("data"), dict) else payload
    gold = data.get("gold") if isinstance(data, dict) else None
    if not isinstance(gold, dict):
        return None
    price = _as_float(gold.get("pricePerGram"))
    if price is None or price <= 0:
        return None
    units = data.get("units") if isinstance(data.get("units"), dict) else {}
    unit = str(units.get("goldPricePerGram") or "IRR").upper()
    if "IRR" in unit or "RIAL" in unit or "RLS" in unit:
        price = price / 10.0
    if assume_24k_spot:
        price = price * 0.75
    change = _as_float(gold.get("change24h"))
    return GoldQuote(
        price_toman=price,
        change_24h=change,
        source="persiantoolbox",
        fetched_at=time.time(),
    )


def is_stale_gold_url(url: str | None) -> bool:
    text = (url or "").strip().lower()
    if not text:
        return True
    if "api.persiantoolbox.com" in text:
        return True
    if "persiantoolbox.ir" in text and "/market" in text:
        return True
    return False


def resolve_gold_api_url(url: str | None) -> str:
    text = (url or "").strip()
    if is_stale_gold_url(text):
        return DEFAULT_GOLD_API_URL
    return text


class MarketService:
    """Fetch Iranian 18k gold quotes from free public feeds."""

    def __init__(
        self,
        *,
        cache_seconds: float = DEFAULT_CACHE_SECONDS,
        api_url: str | None = None,
    ) -> None:
        self._cache_seconds = cache_seconds
        self.api_url = resolve_gold_api_url(api_url or DEFAULT_GOLD_API_URL)
        self._gold: GoldQuote | None = None
        self._last_error: str | None = None
        self._raw: dict | None = None
        self.enabled: bool = True

    @property
    def cache_seconds(self) -> float:
        return self._cache_seconds

    @cache_seconds.setter
    def cache_seconds(self, value: float) -> None:
        self._cache_seconds = max(1.0, float(value))

    @property
    def last_error(self) -> str | None:
        return self._last_error

    @property
    def gold(self) -> GoldQuote | None:
        return self._gold

    @property
    def gold_toman_per_gram(self) -> float | None:
        return self._gold.price_toman if self._gold else None

    def seed_gold(self, price_toman: float, *, source: str = "saved") -> None:
        if price_toman > 0:
            self._gold = GoldQuote(
                price_toman=price_toman,
                change_24h=None,
                source=source,
                fetched_at=0.0,
            )

    def apply_fetched_gold(
        self,
        price_toman: float,
        *,
        change_24h: float | None = None,
        source: str = "wallgold",
    ) -> None:
        """Apply gold quote fetched off-thread (call from UI thread only)."""
        if price_toman > 0:
            self._gold = GoldQuote(
                price_toman=price_toman,
                change_24h=change_24h,
                source=source,
                fetched_at=time.time(),
            )
            self._last_error = None

    def get_gold_toman(self, *, force: bool = False) -> float | None:
        if not self.enabled:
            return self._gold.price_toman if self._gold else None
        if (
            not force
            and self._gold is not None
            and self._gold.fetched_at > 0
            and self._gold.age_seconds < self._cache_seconds
        ):
            return self._gold.price_toman

        quote = self._fetch_gold()
        if quote is not None:
            self._gold = quote
            self._last_error = None
            return quote.price_toman

        if self._gold is not None:
            return self._gold.price_toman
        return None

    def refresh(self, *, force: bool = True) -> dict[str, float | None]:
        """Refresh quotes used by the app."""
        return {"gold_toman": self.get_gold_toman(force=force)}

    def _fetch_gold(self) -> GoldQuote | None:
        configured = resolve_gold_api_url(self.api_url)
        urls: list[str] = [DEFAULT_GOLD_API_URL, DEFAULT_TGJU_AJAX_URL]
        if configured not in urls:
            urls.append(configured)
        # Keep legacy toolbox market as a distant last resort.
        if DEFAULT_MARKET_URL not in urls:
            urls.append(DEFAULT_MARKET_URL)

        errors: list[str] = []
        for url in urls:
            try:
                data = self._http_get_json(url)
            except Exception as exc:  # noqa: BLE001
                errors.append(f"{url}: {exc}")
                continue
            host = url.lower()
            if "wallgold" in host:
                quote = parse_wallgold_gold(data)
            elif "tgju" in host:
                quote = parse_tgju_gold(data)
            elif "persiantoolbox" in host:
                quote = parse_persiantoolbox_gold(data)
            else:
                quote = (
                    parse_wallgold_gold(data)
                    or parse_tgju_gold(data)
                    or parse_persiantoolbox_gold(data)
                )
            if quote is not None:
                if isinstance(data, dict):
                    self._raw = data
                return quote
            errors.append(f"{url}: unrecognized gold payload")

        self._last_error = "; ".join(errors) if errors else "gold fetch failed"
        logger.debug("Gold fetch failed: %s", self._last_error)
        return None

    def _http_get_json(self, url: str) -> dict | list:
        req = urllib.request.Request(
            url,
            headers={
                "User-Agent": "V+/1.0",
                "Accept": "application/json, text/plain, */*",
            },
            method="GET",
        )
        with urllib.request.urlopen(req, timeout=12) as resp:
            return json.loads(resp.read().decode("utf-8"))
