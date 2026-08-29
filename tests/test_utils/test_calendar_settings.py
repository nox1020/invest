from app.config import CALENDAR_GREGORIAN, CALENDAR_JALALI, DEFAULT_SETTINGS
from app.models.settings import AppSettings
from app.utils.dates import format_short_date, normalize_calendar


def test_normalize_calendar_defaults_to_shamsi() -> None:
    assert normalize_calendar(None) == CALENDAR_JALALI
    assert normalize_calendar("") == CALENDAR_JALALI
    assert normalize_calendar("shamsi") == CALENDAR_JALALI
    assert normalize_calendar("persian") == CALENDAR_JALALI


def test_normalize_calendar_gregorian() -> None:
    assert normalize_calendar("gregorian") == CALENDAR_GREGORIAN
    assert normalize_calendar(CALENDAR_GREGORIAN) == CALENDAR_GREGORIAN


def test_app_settings_default_calendar_is_shamsi() -> None:
    settings = AppSettings.from_dict({})
    assert settings.calendar == CALENDAR_JALALI
    assert DEFAULT_SETTINGS["calendar"] == CALENDAR_JALALI


def test_format_short_date_shamsi() -> None:
    text = format_short_date("2024-03-20", CALENDAR_JALALI)
    assert text.startswith("1403/")

