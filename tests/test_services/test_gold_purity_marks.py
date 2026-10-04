from app.services.trade_service import TradeService
from app.utils.gold_purity import (
    grams_to_18k_equivalent,
    scale_gold_price_from_18k,
)


def test_scale_gold_price_from_18k_24k() -> None:
    p18 = 40_000_000.0
    assert abs(scale_gold_price_from_18k(p18, None) - p18) < 1e-6
    assert abs(scale_gold_price_from_18k(p18, "18") - p18) < 1e-6
    assert abs(scale_gold_price_from_18k(p18, "24") - p18 / 0.75) < 1e-6


def test_grams_to_18k_equivalent() -> None:
    assert abs(grams_to_18k_equivalent(10, "24") - 10 / 0.75) < 1e-9
    assert abs(grams_to_18k_equivalent(10, None) - 10) < 1e-9


def test_apply_live_gold_scales_by_purity(trade_service: TradeService) -> None:
    asset = trade_service.create_asset(
        name="آبشده ۲۴",
        symbol="GOLD",
        quantity=1,
        avg_buy_price=30_000_000,
        current_price=30_000_000,
        notes='[kind:gold][meta:{"purity":"24"}]',
    )
    trade_service.apply_live_market_prices(gold_tmn=40_000_000, update_usdt=False)
    refreshed = trade_service.assets.get(asset.id)
    assert refreshed is not None
    assert abs(refreshed.current_price - 40_000_000 / 0.75) < 1.0


def test_gold_fund_counts_kind_marker_and_18k_eq(trade_service: TradeService) -> None:
    trade_service.create_asset(
        name="آبشده",
        symbol="",
        quantity=10,
        avg_buy_price=1,
        current_price=1,
        notes='[kind:gold][meta:{"purity":"24"}]',
    )
    m = trade_service.gold_fund_metrics()
    assert abs(m.gold_holding_g - 10 / 0.75) < 1e-6
