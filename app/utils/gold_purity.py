"""Gold karat / millesimal helpers (aligned with Flutter gold_purity.dart)."""

from __future__ import annotations

import json
import re
from typing import Any


K18_GOLD_PURITY = 0.75

_KIND_RE = re.compile(r"\[kind:([a-z]+)\]", re.IGNORECASE)
_META_RE = re.compile(r"\[meta:(\{.*?\})\]", re.IGNORECASE | re.DOTALL)


def parse_gold_purity_fraction(raw: str | None) -> float | None:
    """Parse Iranian karat (`18`, `۲۴`) or millesimal (`750`) to a 24k fraction."""
    if raw is None:
        return None
    t = str(raw).strip()
    if not t:
        return None
    t = (
        t.replace("عیار", "")
        .replace("%", "")
        .replace("k", "")
        .replace("K", "")
        .replace("ک", "")
        .strip()
    )
    # Persian / Arabic digits → ASCII
    trans = str.maketrans("۰۱۲۳۴۵۶۷۸۹٠١٢٣٤٥٦٧٨٩", "01234567890123456789")
    t = t.translate(trans)
    try:
        n = float(t.replace(",", ""))
    except ValueError:
        return None
    if n <= 0:
        return None
    if 24.5 < n <= 1000:
        return max(0.5, min(1.0, n / 1000.0))
    if 14 <= n <= 24.5:
        return max(0.5, min(1.0, n / 24.0))
    return None


def scale_gold_price_from_18k(price_18k_per_gram: float, purity_raw: str | None) -> float:
    """Convert an 18k Toman/gram index quote to the holding's karat."""
    if price_18k_per_gram <= 0:
        return price_18k_per_gram
    frac = parse_gold_purity_fraction(purity_raw)
    if frac is None:
        return float(price_18k_per_gram)
    return float(price_18k_per_gram) * (frac / K18_GOLD_PURITY)


def grams_to_18k_equivalent(qty: float, purity_raw: str | None) -> float:
    frac = parse_gold_purity_fraction(purity_raw) or K18_GOLD_PURITY
    return float(qty) * (frac / K18_GOLD_PURITY)


def parse_asset_notes(notes: str | None) -> tuple[str | None, dict[str, Any]]:
    """Return (kind_id, meta_dict) from Flutter-style asset notes."""
    text = notes or ""
    kind: str | None = None
    km = _KIND_RE.search(text)
    if km:
        kind = km.group(1).lower()
    meta: dict[str, Any] = {}
    mm = _META_RE.search(text)
    if mm:
        try:
            parsed = json.loads(mm.group(1))
            if isinstance(parsed, dict):
                meta = parsed
        except json.JSONDecodeError:
            meta = {}
    return kind, meta


def purity_from_notes(notes: str | None) -> str | None:
    _, meta = parse_asset_notes(notes)
    raw = meta.get("purity")
    if raw is None:
        return None
    s = str(raw).strip()
    return s or None
