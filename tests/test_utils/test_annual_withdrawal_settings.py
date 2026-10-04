from app.config import (
    ANNUAL_WITHDRAWAL_DEFAULT,
    ANNUAL_WITHDRAWAL_MAX,
    DEFAULT_SETTINGS,
    SETTING_ANNUAL_WITHDRAWAL_PCT,
)
from app.models.settings import AppSettings, clamp_annual_withdrawal_pct


def test_annual_withdrawal_defaults_to_ten_percent() -> None:
    settings = AppSettings.from_dict({})
    assert settings.annual_withdrawal_pct == 10
    assert ANNUAL_WITHDRAWAL_DEFAULT == 10
    assert DEFAULT_SETTINGS[SETTING_ANNUAL_WITHDRAWAL_PCT] == "10"
    assert ANNUAL_WITHDRAWAL_MAX == 100


def test_annual_withdrawal_clamps_to_one_through_one_hundred() -> None:
    assert clamp_annual_withdrawal_pct(0) == 1
    assert clamp_annual_withdrawal_pct(1) == 1
    assert clamp_annual_withdrawal_pct(6) == 6
    assert clamp_annual_withdrawal_pct(10) == 10
    assert clamp_annual_withdrawal_pct(37) == 37
    assert clamp_annual_withdrawal_pct(99) == 99
    assert clamp_annual_withdrawal_pct(100) == 100
    assert clamp_annual_withdrawal_pct(150) == 100
    assert (
        AppSettings.from_dict({SETTING_ANNUAL_WITHDRAWAL_PCT: "15"}).annual_withdrawal_pct
        == 15
    )
    assert (
        AppSettings.from_dict({SETTING_ANNUAL_WITHDRAWAL_PCT: "73"}).annual_withdrawal_pct
        == 73
    )
    assert (
        AppSettings.from_dict({SETTING_ANNUAL_WITHDRAWAL_PCT: "nope"}).annual_withdrawal_pct
        == 10
    )
