from app.config import (
    ANNUAL_WITHDRAWAL_DEFAULT,
    DEFAULT_SETTINGS,
    SETTING_ANNUAL_WITHDRAWAL_PCT,
)
from app.models.settings import AppSettings, clamp_annual_withdrawal_pct


def test_annual_withdrawal_defaults_to_ten_percent() -> None:
    settings = AppSettings.from_dict({})
    assert settings.annual_withdrawal_pct == 10
    assert ANNUAL_WITHDRAWAL_DEFAULT == 10
    assert DEFAULT_SETTINGS[SETTING_ANNUAL_WITHDRAWAL_PCT] == "10"


def test_annual_withdrawal_clamps_and_snaps_to_options() -> None:
    assert clamp_annual_withdrawal_pct(1) == 5
    assert clamp_annual_withdrawal_pct(6) == 5
    assert clamp_annual_withdrawal_pct(7) == 8
    assert clamp_annual_withdrawal_pct(10) == 10
    assert clamp_annual_withdrawal_pct(11) == 10
    assert clamp_annual_withdrawal_pct(18) == 20
    assert clamp_annual_withdrawal_pct(99) == 30
    assert (
        AppSettings.from_dict({SETTING_ANNUAL_WITHDRAWAL_PCT: "15"}).annual_withdrawal_pct
        == 15
    )
    assert (
        AppSettings.from_dict({SETTING_ANNUAL_WITHDRAWAL_PCT: "nope"}).annual_withdrawal_pct
        == 10
    )
