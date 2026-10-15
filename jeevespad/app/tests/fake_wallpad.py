"""A stand-in for Jeeves's fleet server (JeevesFleetService.m), for tests."""

from __future__ import annotations

import asyncio
import plistlib

from jeevespad_manager import fleet


class FakeWallPad:
    def __init__(self, name: str, fleet_code: str, instance_id: str = "abcd1234", sync: bool = True) -> None:
        self.name = name
        self.crypto = fleet.FleetCrypto(fleet_code)
        self.instance_id = instance_id
        self.sync = sync
        self.defaults: dict = {
            "HABaseURL": "http://ha.local:8123",
            "HAAccessToken": "secret-token",
            "HomeSensorIds": ["light.kitchen", "sensor.temp"],
            "JeevesCardSettings": {"home": {"light.kitchen": {"name": "Kitchen", "size": 1}},
                                   "ROOM-1": {"light.bed": {"size": 4}},
                                   "lovelace-x": {"light.y": {"name": "kept"}}},
            "JeevesRooms": b"archived",
            "JeevesIdleHomeTimeout": 300,
        }
        self.rooms = [{"roomId": "ROOM-1", "name": "Bedroom", "iconType": 4, "entityIds": ["light.bed"], "sortOrder": 0}]
        self.commands: list = []
        self.pushes: list = []
        self.server: asyncio.base_events.Server | None = None
        self.port = 0

    async def start(self) -> None:
        self.server = await asyncio.start_server(self._handle, "127.0.0.1", 0)
        self.port = self.server.sockets[0].getsockname()[1]

    async def stop(self) -> None:
        self.server.close()
        await self.server.wait_closed()

    def snapshot(self) -> dict:
        keys = ["HABaseURL", "HAAccessToken", "HABatteryReportingEnabled", "JeevesRooms", "HomeSensorIds",
                "JeevesCardSettings", "JeevesWeatherSource", "JeevesWeatherEntityId", "JeevesWeatherTemperatureEntityId",
                "JeevesWeatherReadingEntityIds", "JeevesIdleHomeTimeout", "JeevesIdleDimsWhenIdle", "JellyfinEnabled",
                "JellyfinServerURL"]
        return {"keys": keys, "values": dict(self.defaults), "rooms": list(self.rooms)}

    def apply(self, snapshot: dict) -> None:
        self.pushes.append(snapshot)
        keys, values = list(snapshot["keys"]), snapshot["values"]
        if isinstance(snapshot.get("rooms"), list):
            self.rooms = snapshot["rooms"]
            if "JeevesRooms" not in keys:
                keys.append("JeevesRooms")
            values = dict(values, JeevesRooms=b"rearchived")
        for key in keys:
            if key in values:
                self.defaults[key] = values[key]
            else:
                self.defaults.pop(key, None)

    def respond(self, request: dict) -> dict:
        if not self.sync:
            return {"v": 1, "type": "result", "error": f"Fleet sync is turned off on {self.name}"}
        payload = fleet.open_payload(self.crypto, request)
        if payload is None:
            return {"v": 1, "type": "result", "error": f"{self.name} has a different fleet code"}
        error = fleet.validate_payload(payload)
        if error:
            return {"v": 1, "type": "result", "error": error}
        rtype = request.get("type")
        if rtype == "push":
            self.apply(payload["settings"])
            body = {"ok": True}
        elif rtype == "pull":
            body = {"ok": True, "settings": self.snapshot()}
        elif rtype == "status":
            body = {"ok": True, "status": {"id": self.instance_id, "name": self.name, "model": "iPad2,5",
                                           "systemVersion": "9.3.5", "appVersion": "1.0", "appBuild": "1",
                                           "battery": 0.8, "batteryState": "charging", "brightness": 0.6,
                                           "dimmed": False, "idleSeconds": 30, "haConfigured": True,
                                           "haConnected": True, "features": ["push", "pull", "status", "command", "rooms"]}}
        elif rtype == "command":
            self.commands.append((payload.get("command"), payload.get("value")))
            body = {"ok": True}
        else:
            return {"v": 1, "type": "result", "error": "Unknown request"}
        return fleet.seal_payload(self.crypto, body, "result", sender=self.name)

    async def _handle(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
        try:
            request = await fleet.read_message(reader)
            writer.write(fleet.encode_message(self.respond(request)))
            await writer.drain()
        finally:
            writer.close()


def roundtrip_plist(value):
    return plistlib.loads(plistlib.dumps(value, fmt=plistlib.FMT_BINARY))
