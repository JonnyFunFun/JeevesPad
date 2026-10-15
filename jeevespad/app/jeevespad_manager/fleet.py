"""Jeeves fleet protocol: the same encrypted requests iPads use to share settings.

Mirrors Jeeves/Helpers/JeevesFleetCrypto.m and Jeeves/API/JeevesFleetService.m.
One request per TCP connection; each message is a 4-byte big-endian length followed by
a binary property list {v, type, box} (or {v, type, error}). `box` is the payload (a
binary plist with `ts` and `from`) sealed with keys derived from the fleet code:
PBKDF2-HMAC-SHA256 (20000 rounds) gives an AES-256-CBC key and an HMAC-SHA256 key;
box = IV ‖ ciphertext ‖ HMAC(IV ‖ ciphertext).
"""

from __future__ import annotations

import asyncio
import hashlib
import hmac
import os
import plistlib
import struct
import time
from functools import lru_cache
from typing import Any

from cryptography.hazmat.primitives import padding
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes

PROTOCOL_VERSION = 1
SALT = b"JeevesPad-fleet-v1"
ROUNDS = 20000
KEY_LENGTH = 32
MAX_MESSAGE = 4 * 1024 * 1024
MAX_CLOCK_SKEW = 600
SENDER_NAME = "Home Assistant"


class FleetError(Exception):
    """A request failed; the message is shown to the user."""


class FleetCrypto:
    def __init__(self, fleet_code: str) -> None:
        derived = hashlib.pbkdf2_hmac("sha256", fleet_code.encode("utf-8"), SALT, ROUNDS, KEY_LENGTH * 2)
        self._enc_key = derived[:KEY_LENGTH]
        self._mac_key = derived[KEY_LENGTH:]

    def _mac(self, data: bytes) -> bytes:
        return hmac.new(self._mac_key, data, hashlib.sha256).digest()

    def seal(self, plaintext: bytes) -> bytes:
        iv = os.urandom(16)
        padder = padding.PKCS7(128).padder()
        padded = padder.update(plaintext) + padder.finalize()
        encryptor = Cipher(algorithms.AES(self._enc_key), modes.CBC(iv)).encryptor()
        signed = iv + encryptor.update(padded) + encryptor.finalize()
        return signed + self._mac(signed)

    def open(self, box: bytes) -> bytes | None:
        if len(box) < 16 * 2 + 32:
            return None
        signed, mac = box[:-32], box[-32:]
        if not hmac.compare_digest(mac, self._mac(signed)):
            return None
        iv, ciphertext = signed[:16], signed[16:]
        try:
            decryptor = Cipher(algorithms.AES(self._enc_key), modes.CBC(iv)).decryptor()
            padded = decryptor.update(ciphertext) + decryptor.finalize()
            unpadder = padding.PKCS7(128).unpadder()
            return unpadder.update(padded) + unpadder.finalize()
        except ValueError:
            return None


@lru_cache(maxsize=4)
def crypto_for(fleet_code: str) -> FleetCrypto:
    """Key derivation is deliberately slow, so cache it per code."""
    return FleetCrypto(fleet_code)


def _plist_safe(value: Any) -> Any:
    """Property lists can't hold None: drop those entries."""
    if isinstance(value, dict):
        return {str(k): _plist_safe(v) for k, v in value.items() if v is not None}
    if isinstance(value, (list, tuple)):
        return [_plist_safe(v) for v in value if v is not None]
    return value


def encode_message(message: dict) -> bytes:
    body = plistlib.dumps(_plist_safe(message), fmt=plistlib.FMT_BINARY)
    return struct.pack(">I", len(body)) + body


async def read_message(reader: asyncio.StreamReader) -> dict:
    header = await reader.readexactly(4)
    (length,) = struct.unpack(">I", header)
    if length > MAX_MESSAGE:
        raise FleetError("Message too large")
    message = plistlib.loads(await reader.readexactly(length))
    if not isinstance(message, dict):
        raise FleetError("Invalid message")
    return message


def seal_payload(crypto: FleetCrypto, payload: dict, rtype: str, sender: str = SENDER_NAME) -> dict:
    body = dict(payload)
    body["ts"] = time.time()
    body["from"] = sender
    sealed = crypto.seal(plistlib.dumps(_plist_safe(body), fmt=plistlib.FMT_BINARY))
    return {"v": PROTOCOL_VERSION, "type": rtype, "box": sealed}


def open_payload(crypto: FleetCrypto, message: dict) -> dict | None:
    box = message.get("box")
    if not isinstance(box, bytes):
        return None
    plaintext = crypto.open(box)
    if plaintext is None:
        return None
    try:
        payload = plistlib.loads(plaintext)
    except Exception:  # noqa: BLE001 - any parse failure means a bad payload
        return None
    return payload if isinstance(payload, dict) else None


def validate_payload(payload: dict) -> str | None:
    ts = payload.get("ts")
    if not isinstance(ts, (int, float)) or abs(time.time() - ts) > MAX_CLOCK_SKEW:
        return "Request expired (check the clocks of the wallPad and Home Assistant)"
    return None


async def request(host: str, port: int, fleet_code: str, rtype: str, payload: dict | None = None,
                  timeout: float = 15.0, device_name: str | None = None) -> dict:
    """Sends one request to a wallPad and returns its decrypted response payload."""
    name = device_name or host
    crypto = await asyncio.get_running_loop().run_in_executor(None, crypto_for, fleet_code)
    try:
        reader, writer = await asyncio.wait_for(asyncio.open_connection(host, port), timeout)
    except (OSError, asyncio.TimeoutError) as err:
        raise FleetError(f"Couldn't connect to {name}: {err or 'timed out'}") from err
    try:
        writer.write(encode_message(seal_payload(crypto, payload or {}, rtype)))
        await writer.drain()
        message = await asyncio.wait_for(read_message(reader), timeout)
    except asyncio.IncompleteReadError as err:
        raise FleetError(f"{name} closed the connection") from err
    except (OSError, asyncio.TimeoutError) as err:
        raise FleetError(f"{name}: {err or 'timed out'}") from err
    finally:
        writer.close()
        try:
            await writer.wait_closed()
        except OSError:
            pass

    if isinstance(message.get("error"), str):
        raise FleetError(message["error"])
    response = open_payload(crypto, message)
    if response is None:
        raise FleetError(f"{name} has a different fleet code")
    error = validate_payload(response)
    if error:
        raise FleetError(error)
    return response
