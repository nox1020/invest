from app.config import DEFAULT_GOLD_API_URL
from app.services.market_service import (
    parse_persiantoolbox_gold,
    parse_tgju_gold,
    parse_wallgold_gold,
    resolve_gold_api_url,
)


def test_parse_wallgold_gold() -> None:
    quote = parse_wallgold_gold(
        {
            "result": [
                {
                    "symbol": "GLD_18C_750TMN",
                    "marketCap": {
                        "lastPrice": "26422000",
                        "24hChangePrice": "0.02",
                    },
                }
            ]
        }
    )
    assert quote is not None
    assert quote.price_toman == 26422000
    assert quote.change_24h == 2.0
    assert quote.source == "wallgold"


def test_parse_tgju_gold() -> None:
    quote = parse_tgju_gold(
        {"current": {"geram18": {"p": "264,550,000", "dp": 0.88}}}
    )
    assert quote is not None
    assert quote.price_toman == 26455000
    assert quote.change_24h == 0.88
    assert quote.source == "tgju"


def test_parse_toolbox_converts_24k_spot() -> None:
    quote = parse_persiantoolbox_gold(
        {
            "ok": True,
            "data": {
                "gold": {"pricePerGram": 177480399, "change24h": 0.03},
                "units": {"goldPricePerGram": "IRR"},
            },
        }
    )
    assert quote is not None
    assert abs(quote.price_toman - 177480399 / 10 * 0.75) < 0.1


def test_resolve_stale_gold_urls() -> None:
    assert (
        resolve_gold_api_url("https://persiantoolbox.ir/api/market")
        == DEFAULT_GOLD_API_URL
    )
    assert (
        resolve_gold_api_url("https://api.persiantoolbox.com/v1/metal")
        == DEFAULT_GOLD_API_URL
    )
    assert (
        resolve_gold_api_url("https://api.wallgold.ir/api/v1/markets")
        == "https://api.wallgold.ir/api/v1/markets"
    )
