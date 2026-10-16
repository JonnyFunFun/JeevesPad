"""Guided Access (keeps the iPad in Jeeves) and maintenance mode (locks it behind a notice)."""

from __future__ import annotations

from typing import Any

from homeassistant.components.switch import SwitchEntity
from homeassistant.core import HomeAssistant
from homeassistant.exceptions import HomeAssistantError
from homeassistant.helpers.entity_platform import AddConfigEntryEntitiesCallback

from .api import JeevesPadError
from .coordinator import JeevesPadConfigEntry, JeevesPadCoordinator
from .entity import WallPadEntity, add_entities_for_new_pads

PARALLEL_UPDATES = 1


async def async_setup_entry(hass: HomeAssistant, entry: JeevesPadConfigEntry,
                            async_add_entities: AddConfigEntryEntitiesCallback) -> None:
    coordinator = entry.runtime_data
    entry.async_on_unload(add_entities_for_new_pads(coordinator, async_add_entities, lambda pad_id: [
        GuidedAccessSwitch(coordinator, pad_id),
        MaintenanceSwitch(coordinator, pad_id),
    ]))


class GuidedAccessSwitch(WallPadEntity, SwitchEntity):
    def __init__(self, coordinator: JeevesPadCoordinator, pad_id: str) -> None:
        super().__init__(coordinator, pad_id, "guided_access")

    @property
    def available(self) -> bool:
        return super().available and "guided_access" in (self.pad.get("features") or [])

    @property
    def is_on(self) -> bool | None:
        return self.pad.get("guided_access")

    async def _set(self, on: bool) -> None:
        try:
            await self.coordinator.client.guided_access(self.pad_id, on)
        except JeevesPadError as err:
            raise HomeAssistantError(str(err)) from err
        self.coordinator.data.get(self.pad_id, {})["guided_access"] = on
        self.async_write_ha_state()

    async def async_turn_on(self, **kwargs: Any) -> None:
        await self._set(True)

    async def async_turn_off(self, **kwargs: Any) -> None:
        await self._set(False)


class MaintenanceSwitch(WallPadEntity, SwitchEntity):
    """On: the wallPad shows its maintenance notice and can't be used."""

    def __init__(self, coordinator: JeevesPadCoordinator, pad_id: str) -> None:
        super().__init__(coordinator, pad_id, "maintenance")

    @property
    def available(self) -> bool:
        return super().available and "maintenance" in (self.pad.get("features") or [])

    @property
    def is_on(self) -> bool | None:
        return self.pad.get("maintenance")

    async def _set(self, on: bool) -> None:
        try:
            await self.coordinator.client.maintenance(self.pad_id, on)
        except JeevesPadError as err:
            raise HomeAssistantError(str(err)) from err
        self.coordinator.data.get(self.pad_id, {})["maintenance"] = on
        self.async_write_ha_state()

    async def async_turn_on(self, **kwargs: Any) -> None:
        await self._set(True)

    async def async_turn_off(self, **kwargs: Any) -> None:
        await self._set(False)
