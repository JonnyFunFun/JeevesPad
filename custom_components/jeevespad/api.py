"""Client for the JeevesPad Manager app's integration API."""

from __future__ import annotations

from typing import Any

import aiohttp


class JeevesPadError(Exception):
    """The app couldn't be reached or refused the request."""


class JeevesPadAuthError(JeevesPadError):
    """The API key was rejected."""


class JeevesPadClient:
    def __init__(self, session: aiohttp.ClientSession, host: str, port: int, api_key: str) -> None:
        self._session = session
        self._base = f"http://{host}:{port}/api/v1"
        self._headers = {"Authorization": f"Bearer {api_key}"}

    async def _request(self, method: str, path: str, json: dict | None = None) -> Any:
        try:
            async with self._session.request(method, f"{self._base}{path}", json=json, headers=self._headers,
                                             timeout=aiohttp.ClientTimeout(total=30)) as response:
                if response.status == 401:
                    raise JeevesPadAuthError("The JeevesPad app rejected the API key")
                data = await response.json(content_type=None)
                if response.status != 200:
                    message = data.get("error") if isinstance(data, dict) else None
                    raise JeevesPadError(message or f"HTTP {response.status}")
                return data
        except (aiohttp.ClientError, TimeoutError) as err:
            raise JeevesPadError(f"Couldn't reach the JeevesPad app: {err}") from err

    async def wallpads(self) -> list[dict]:
        return await self._request("GET", "/wallpads")

    async def command(self, pad_id: str, command: str, value: Any = None) -> None:
        body: dict[str, Any] = {"command": command}
        if value is not None:
            body["value"] = value
        await self._request("POST", f"/wallpads/{pad_id}/command", body)

    async def ssh_action(self, pad_id: str, action: str) -> None:
        await self._request("POST", f"/wallpads/{pad_id}/ssh/{action}", {})
