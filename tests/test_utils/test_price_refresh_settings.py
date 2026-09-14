from app.config import DEFAULT_SETTINGS, PRICE_REFRESH_DEFAULT, SETTING_PRICE_REFRESH_SEC
from app.models.settings import AppSettings, clamp_price_refresh_seconds


def test_price_refresh_defaults_to_five_seconds() -> None:
    settings = AppSettings.from_dict({})
    assert settings.price_refresh_seconds == 5
    assert PRICE_REFRESH_DEFAULT == 5
    assert DEFAULT_SETTINGS[SETTING_PRICE_REFRESH_SEC] == "5"


def test_price_refresh_clamps_and_snaps_to_options() -> None:
    assert clamp_price_refresh_seconds(1) == 5
    assert clamp_price_refresh_seconds(7) == 5
    assert clamp_price_refresh_seconds(8) == 10
    assert clamp_price_refresh_seconds(15) == 15
    assert clamp_price_refresh_seconds(45) == 30
    assert clamp_price_refresh_seconds(90) == 60
    assert clamp_price_refresh_seconds(99999) == 300
    assert AppSettings.from_dict({SETTING_PRICE_REFRESH_SEC: "10"}).price_refresh_seconds == 10
    assert AppSettings.from_dict({SETTING_PRICE_REFRESH_SEC: "nope"}).price_refresh_seconds == 5
