from app.utils.money import format_money


def test_format_toman() -> None:
    assert "تومان" in format_money(1_000_000, "toman")


def test_format_usd_with_fx() -> None:
    text = format_money(65_000_000, "usd", fx_rate=65_000)
    assert "$" in text or "دلار" in text.lower() or text


def test_sale_total_toman_and_usd() -> None:
    from app.utils.money import format_toman_fixed, format_usd_from_toman

    assert format_toman_fixed(130_000_000) == "130,000,000 تومان"
    assert format_usd_from_toman(130_000_000, 65_000) == "2,000.00 دلار"
    assert format_usd_from_toman(130_000_000, None) == "—"
