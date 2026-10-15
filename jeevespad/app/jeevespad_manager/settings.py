"""Converts a wallPad's settings snapshot (its NSUserDefaults keys) to and from the
editor's JSON form.

A snapshot is {keys, values, rooms}: `keys` lists the settings being sent; a listed key
without a value is removed. So a partial update lists only the keys it changes. `rooms`
holds the rooms as plain dictionaries (JeevesRooms itself is an NSKeyedArchiver blob).
"""

from __future__ import annotations

import uuid
from typing import Any

HOME_DASHBOARD = "home"

# JeevesCardSize raw values
SIZES = {"small": 0, "wide": 1, "tall": 2, "large": 3, "xsmall": 4}
SIZE_NAMES = {v: k for k, v in SIZES.items()}

# JeevesIconType values offered for rooms (as in JeevesAddRoomViewController)
ROOM_ICONS = {"living_room": 1, "bed": 4, "kitchen": 2, "bath": 3, "house": 0, "garage": 5, "work": 6, "crib": 7}
ROOM_ICON_NAMES = {v: k for k, v in ROOM_ICONS.items()}

WEATHER_SOURCES = {"automatic": 0, "none": 1, "entity": 2}
WEATHER_SOURCE_NAMES = {v: k for k, v in WEATHER_SOURCES.items()}

DEFAULT_HOME_TIMEOUT = 180

SECTION_KEYS = {
    "connection": ["HABaseURL", "HABatteryReportingEnabled"],  # + HAAccessToken when replaced
    "dashboards": ["HomeSensorIds", "JeevesCardSettings"],     # + rooms
    "weather": ["JeevesWeatherSource", "JeevesWeatherEntityId", "JeevesWeatherTemperatureEntityId",
                "JeevesWeatherReadingEntityIds"],
    "idle": ["JeevesIdleHomeTimeout", "JeevesIdleDimsWhenIdle"],
    "jellyfin": ["JellyfinEnabled", "JellyfinServerURL"],
}


def _str(value: Any) -> str | None:
    return value if isinstance(value, str) and value else None


def _cards(entity_ids: list, dashboard: dict) -> list[dict]:
    cards = []
    for entity_id in entity_ids:
        if not isinstance(entity_id, str):
            continue
        custom = dashboard.get(entity_id) if isinstance(dashboard, dict) else None
        custom = custom if isinstance(custom, dict) else {}
        cards.append({
            "entity_id": entity_id,
            "name": _str(custom.get("name")) or "",
            "size": SIZE_NAMES.get(custom.get("size", 0), "small"),
        })
    return cards


def to_view(snapshot: dict) -> dict:
    values = snapshot.get("values") if isinstance(snapshot.get("values"), dict) else {}
    card_settings = values.get("JeevesCardSettings") if isinstance(values.get("JeevesCardSettings"), dict) else {}

    rooms_in = snapshot.get("rooms")
    rooms = []
    room_ids = set()
    if isinstance(rooms_in, list):
        for room in sorted((r for r in rooms_in if isinstance(r, dict)), key=lambda r: r.get("sortOrder", 0)):
            room_id = _str(room.get("roomId")) or ""
            room_ids.add(room_id)
            rooms.append({
                "room_id": room_id,
                "name": room.get("name") or "",
                "icon": ROOM_ICON_NAMES.get(room.get("iconType"), "house"),
                "cards": _cards(room.get("entityIds") or [], card_settings.get(room_id, {})),
            })

    timeout = values.get("JeevesIdleHomeTimeout")
    reading_ids = values.get("JeevesWeatherReadingEntityIds")
    return {
        "connection": {
            "ha_url": _str(values.get("HABaseURL")) or "",
            "ha_token_set": bool(_str(values.get("HAAccessToken"))),
            "battery_reporting": bool(values.get("HABatteryReportingEnabled", False)),
        },
        "dashboards": {
            "home_cards": _cards(values.get("HomeSensorIds") or [], card_settings.get(HOME_DASHBOARD, {})),
            "rooms": rooms,
            "rooms_editable": isinstance(rooms_in, list),  # older app versions don't send portable rooms
        },
        "weather": {
            "source": WEATHER_SOURCE_NAMES.get(values.get("JeevesWeatherSource", 0), "automatic"),
            "entity_id": _str(values.get("JeevesWeatherEntityId")) or "",
            "temperature_entity_id": _str(values.get("JeevesWeatherTemperatureEntityId")) or "",
            "reading_entity_ids": [r for r in reading_ids if isinstance(r, str)] if isinstance(reading_ids, list) else [],
        },
        "idle": {
            "home_timeout": int(timeout) if isinstance(timeout, (int, float)) else DEFAULT_HOME_TIMEOUT,
            "dims_when_idle": bool(values.get("JeevesIdleDimsWhenIdle", True)),
        },
        "jellyfin": {
            "enabled": bool(values.get("JellyfinEnabled", False)),
            "server_url": _str(values.get("JellyfinServerURL")) or "",
        },
        # Card settings for dashboards the editor doesn't show; kept when saving
        "_other_card_settings": {k: v for k, v in card_settings.items()
                                 if k != HOME_DASHBOARD and k not in room_ids},
    }


def _card_settings_entry(card: dict) -> dict:
    entry = {}
    name = (card.get("name") or "").strip()
    if name:
        entry["name"] = name
    size = SIZES.get(card.get("size"), 0)
    if size:
        entry["size"] = size
    return entry


class InvalidSettings(ValueError):
    pass


def from_view(view: dict, sections: list[str], current: dict | None = None) -> dict:
    """Builds a partial snapshot that updates only `sections` of the settings.

    `current` is the wallPad's current view (for card settings the editor doesn't show).
    """
    keys: list[str] = []
    values: dict[str, Any] = {}
    snapshot: dict[str, Any] = {"keys": keys, "values": values}

    for section in sections:
        if section not in SECTION_KEYS:
            raise InvalidSettings(f"Unknown settings section {section!r}")
        data = view.get(section)
        if not isinstance(data, dict):
            raise InvalidSettings(f"Missing settings for {section}")
        keys.extend(SECTION_KEYS[section])

        if section == "connection":
            url = (data.get("ha_url") or "").strip().rstrip("/")
            if url and not url.startswith(("http://", "https://")):
                raise InvalidSettings("The Home Assistant URL must start with http:// or https://")
            values["HABaseURL"] = url or None
            values["HABatteryReportingEnabled"] = bool(data.get("battery_reporting"))
            token = (data.get("ha_token") or "").strip()
            if token:
                keys.append("HAAccessToken")
                values["HAAccessToken"] = token

        elif section == "dashboards":
            card_settings = dict((current or {}).get("_other_card_settings") or {})
            home = data.get("home_cards") or []
            values["HomeSensorIds"] = [c["entity_id"] for c in home if c.get("entity_id")]
            home_settings = {c["entity_id"]: _card_settings_entry(c) for c in home if c.get("entity_id")}
            home_settings = {k: v for k, v in home_settings.items() if v}
            if home_settings:
                card_settings[HOME_DASHBOARD] = home_settings

            rooms = data.get("rooms")
            if rooms is not None:
                portable = []
                for index, room in enumerate(rooms):
                    name = (room.get("name") or "").strip()
                    if not name:
                        raise InvalidSettings("Every room needs a name")
                    # New rooms get their ID here, so their card settings can refer to it
                    room_id = room.get("room_id") or str(uuid.uuid4()).upper()
                    cards = room.get("cards") or []
                    portable.append({
                        "roomId": room_id,
                        "name": name,
                        "iconType": ROOM_ICONS.get(room.get("icon"), 0),
                        "entityIds": [c["entity_id"] for c in cards if c.get("entity_id")],
                        "sortOrder": index,
                    })
                    room_settings = {c["entity_id"]: _card_settings_entry(c) for c in cards if c.get("entity_id")}
                    room_settings = {k: v for k, v in room_settings.items() if v}
                    if room_settings:
                        card_settings[room_id] = room_settings
                snapshot["rooms"] = portable
            values["JeevesCardSettings"] = card_settings

        elif section == "weather":
            source = data.get("source", "automatic")
            if source not in WEATHER_SOURCES:
                raise InvalidSettings("Unknown weather source")
            values["JeevesWeatherSource"] = WEATHER_SOURCES[source]
            values["JeevesWeatherEntityId"] = (data.get("entity_id") or None) if source == "entity" else None
            values["JeevesWeatherTemperatureEntityId"] = data.get("temperature_entity_id") or None
            values["JeevesWeatherReadingEntityIds"] = [r for r in data.get("reading_entity_ids") or [] if r]

        elif section == "idle":
            try:
                timeout = int(data.get("home_timeout", DEFAULT_HOME_TIMEOUT))
            except (TypeError, ValueError) as err:
                raise InvalidSettings("The idle timeout must be a number of seconds") from err
            values["JeevesIdleHomeTimeout"] = max(0, timeout)
            values["JeevesIdleDimsWhenIdle"] = bool(data.get("dims_when_idle", True))

        elif section == "jellyfin":
            values["JellyfinEnabled"] = bool(data.get("enabled"))
            values["JellyfinServerURL"] = (data.get("server_url") or "").strip().rstrip("/") or None

    # A listed key without a value is removed on the wallPad
    for key in list(values):
        if values[key] is None:
            del values[key]
    return snapshot


def connection_snapshot(ha_url: str, ha_token: str) -> dict:
    """Settings for a newly set-up wallPad that only has Home Assistant's address and a token."""
    return {"keys": ["HABaseURL", "HAAccessToken"],
            "values": {"HABaseURL": ha_url.strip().rstrip("/"), "HAAccessToken": ha_token.strip()}}
