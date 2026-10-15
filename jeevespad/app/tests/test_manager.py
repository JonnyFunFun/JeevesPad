"""End-to-end tests of the manager's API against fake wallPads and a fake ssh."""

from __future__ import annotations

import asyncio
import io
import os
import plistlib
import stat
import subprocess
import zipfile

import aiohttp
import pytest
from aiohttp.test_utils import TestClient, TestServer

from jeevespad_manager import fleet, manager as manager_module, settings
from jeevespad_manager.discovery import Advertisement
from jeevespad_manager.manager import Manager
from jeevespad_manager.server import create_app

from fake_wallpad import FakeWallPad

CODE = "test-fleet-code"

FAKE_SSHPASS = r"""#!/bin/sh
# Records each call; "ssh"/"scp" behave like a reachable iPad with the given password
echo "$@" >> "$FAKE_SSH_LOG"
if [ "$SSHPASS" != "$FAKE_SSH_PASSWORD" ]; then exit 5; fi
case "$*" in
  *"for t in uicache"*) printf 'uicache=1\nopen=1\nuiopen=0\nkillall=1\nios=9.3.5\nmodel=iPad2,5\ninstalled=0\n' ;;
  *"cat > /var/mobile/Library/Jeeves/provision.plist"*) cat > "$FAKE_PROVISION" ;;
  *"Jeeves-exception.log"*) echo "=== Last uncaught exception ==="; echo "(none)" ;;
esac
exit 0
"""


def make_ipa(version="1.2") -> bytes:
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as z:
        z.writestr("Payload/Jeeves.app/Info.plist", plistlib.dumps(
            {"CFBundleIdentifier": "com.jeeves.Jeeves", "CFBundleShortVersionString": version, "CFBundleVersion": "7"}))
        z.writestr("Payload/Jeeves.app/Jeeves", b"binary")
    return buf.getvalue()


@pytest.fixture
def env(tmp_path, monkeypatch):
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    sshpass = bin_dir / "sshpass"
    sshpass.write_text(FAKE_SSHPASS)
    sshpass.chmod(sshpass.stat().st_mode | stat.S_IEXEC)
    monkeypatch.setenv("PATH", f"{bin_dir}:{os.environ['PATH']}")
    monkeypatch.setenv("FAKE_SSH_LOG", str(tmp_path / "ssh.log"))
    monkeypatch.setenv("FAKE_SSH_PASSWORD", "alpine")
    monkeypatch.setenv("FAKE_PROVISION", str(tmp_path / "provision.plist"))
    monkeypatch.delenv("SUPERVISOR_TOKEN", raising=False)
    return tmp_path


async def start(env, options=None):
    data = env / "data"
    data.mkdir(exist_ok=True)
    m = Manager(str(data), options or {"fleet_code": CODE, "ssh_password": "alpine"})
    client = TestClient(TestServer(create_app(m, dev=True)))
    await client.start_server()
    return m, client


async def advertise(m: Manager, pad: FakeWallPad, host="127.0.0.1"):
    m.discovery.advertisements[pad.name] = Advertisement(
        name=pad.name, host=host, port=pad.port, instance_id=pad.instance_id, app_version="1.0", sync_enabled=pad.sync)
    m._discovery_changed()
    await asyncio.sleep(0.2)  # first sighting fetches status


async def wait_job(client, job_id):
    for _ in range(100):
        job = await (await client.get(f"/api/jobs/{job_id}")).json()
        if job["state"] != "running":
            return job
        await asyncio.sleep(0.1)
    raise AssertionError(f"job didn't finish: {job}")


def test_crypto_matches_openssl():
    """The box is plain AES-256-CBC/PKCS7 + HMAC-SHA256, as CommonCrypto produces."""
    crypto = fleet.FleetCrypto(CODE)
    box = crypto.seal(b"hello wallPad")
    iv, ciphertext = box[:16], box[16:-32]
    out = subprocess.run(["openssl", "enc", "-d", "-aes-256-cbc", "-K", crypto._enc_key.hex(), "-iv", iv.hex()],
                         input=ciphertext, capture_output=True, check=True)
    assert out.stdout == b"hello wallPad"
    assert crypto.open(box) == b"hello wallPad"
    tampered = box[:-1] + bytes([box[-1] ^ 1])
    assert crypto.open(tampered) is None
    assert fleet.FleetCrypto("other").open(box) is None


def test_settings_roundtrip():
    pad = FakeWallPad("Kitchen", CODE)
    view = settings.to_view(pad.snapshot())
    assert view["dashboards"]["home_cards"][0] == {"entity_id": "light.kitchen", "name": "Kitchen", "size": "wide"}
    assert view["dashboards"]["rooms"][0]["cards"][0]["size"] == "xsmall"
    assert view["idle"]["home_timeout"] == 300
    assert view["connection"]["ha_token_set"] is True

    view["dashboards"]["rooms"].append({"room_id": "", "name": "Office", "icon": "work",
                                        "cards": [{"entity_id": "light.desk", "name": "Desk", "size": "small"}]})
    snap = settings.from_view(view, ["dashboards"], view)
    assert snap["keys"] == ["HomeSensorIds", "JeevesCardSettings"]
    new_room = snap["rooms"][1]
    assert new_room["roomId"] and new_room["iconType"] == 6
    cards = snap["values"]["JeevesCardSettings"]
    assert cards[new_room["roomId"]] == {"light.desk": {"name": "Desk"}}
    assert cards["lovelace-x"] == {"light.y": {"name": "kept"}}  # dashboards the editor doesn't show are kept
    assert "HAAccessToken" not in snap["values"]


@pytest.mark.asyncio
async def test_status_settings_and_commands(env):
    pad = FakeWallPad("Kitchen", CODE)
    other = FakeWallPad("Hall", CODE, instance_id="ffff0000")
    await pad.start(); await other.start()
    m, client = await start(env)
    try:
        await advertise(m, pad)
        await advertise(m, other)
        state = await (await client.get("/api/state")).json()
        kitchen = next(p for p in state["wallpads"] if p["name"] == "Kitchen")
        assert kitchen["id"] == "abcd1234" and kitchen["online"] and kitchen["status"]["battery"] == 0.8
        assert "ssh_password" not in kitchen

        view = await (await client.get("/api/wallpads/abcd1234/settings")).json()
        assert "_other_card_settings" not in view
        view["idle"]["home_timeout"] = 600
        view["connection"]["ha_token"] = ""
        res = await client.put("/api/wallpads/abcd1234/settings",
                               json={"settings": view, "sections": ["idle", "connection"], "also": ["ffff0000"]})
        assert res.status == 200, await res.text()
        assert pad.defaults["JeevesIdleHomeTimeout"] == 600
        assert pad.defaults["HAAccessToken"] == "secret-token"  # empty token field keeps the token
        assert other.defaults["JeevesIdleHomeTimeout"] == 600

        res = await client.post("/api/wallpads/abcd1234/command", json={"command": "brightness", "value": 0.3})
        assert res.status == 200
        assert pad.commands == [("brightness", 0.3)]

        # Integration API needs the key
        assert (await client.get("/api/v1/wallpads")).status == 401
        res = await client.get("/api/v1/wallpads", headers={"Authorization": f"Bearer {m.api_key}"})
        assert (await res.json())[0]["name"] in ("Hall", "Kitchen")
    finally:
        await client.close(); await pad.stop(); await other.stop()


@pytest.mark.asyncio
async def test_wrong_fleet_code_and_sync_off(env):
    pad = FakeWallPad("Kitchen", "another-code")
    await pad.start()
    m, client = await start(env)
    try:
        await advertise(m, pad)
        res = await client.get("/api/wallpads/abcd1234/settings")
        assert res.status == 400
        assert "different fleet code" in (await res.json())["error"]
        pad.crypto = fleet.FleetCrypto(CODE)
        pad.sync = False
        res = await client.get("/api/wallpads/abcd1234/settings")
        assert "Enrol it" in (await res.json())["error"]
    finally:
        await client.close(); await pad.stop()


@pytest.mark.asyncio
async def test_provision_installs_and_enrols(env, monkeypatch):
    monkeypatch.setattr(manager_module, "WAIT_FOR_APP", 3)
    source = FakeWallPad("Kitchen", CODE)
    await source.start()
    m, client = await start(env)
    try:
        await advertise(m, source)
        form = aiohttp.FormData()
        form.add_field("file", make_ipa("1.2"), filename="Jeeves.ipa")
        res = await client.post("/api/package/upload", data=form)
        assert (await res.json())["custom"]["version"] == "1.2"

        # Wrong password without one given: a clear message
        monkeypatch.setenv("FAKE_SSH_PASSWORD", "s3cret")
        job = await (await client.post("/api/provision", json={"host": "10.0.0.9", "settings_source": "copy:abcd1234"})).json()
        job = await wait_job(client, job["id"])
        assert job["state"] == "failed" and "rejected the root password" in job["error"]

        job = await (await client.post("/api/provision", json={"host": "10.0.0.9", "password": "s3cret",
                                                               "settings_source": "copy:abcd1234"})).json()
        job = await wait_job(client, job["id"])
        assert job["state"] == "done", job["log"]
        assert any("your uploaded package, Jeeves 1.2" in l["line"] for l in job["log"])

        log = (env / "ssh.log").read_text()
        assert "scp" in log and "/Applications/" in log and "uicache" in log
        provision = plistlib.loads((env / "provision.plist").read_bytes())
        assert provision["fleetCode"] == CODE and provision["fleetEnabled"] is True
        assert provision["settings"]["values"]["HAAccessToken"] == "secret-token"
        assert provision["settings"]["rooms"][0]["name"] == "Bedroom"

        # Didn't appear on the network in time: kept as an SSH-only wallPad with its password
        pad = m.wallpads["host:10.0.0.9"]
        assert pad.ssh_password == "s3cret" and pad.ssh_host == "10.0.0.9"
        res = await client.post(f"/api/wallpads/host:10.0.0.9/ssh/logs", json={})
        assert "Last uncaught exception" in (await res.json())["result"]["text"]
    finally:
        await client.close(); await source.stop()


@pytest.mark.asyncio
async def test_rejects_requests_not_from_ingress(env):
    m = Manager(str(env), {"fleet_code": CODE})
    client = TestClient(TestServer(create_app(m, dev=False)))
    await client.start_server()
    try:
        assert (await client.get("/api/state")).status == 403
        assert (await client.get("/")).status == 403
    finally:
        await client.close()


def test_generated_fleet_code_is_kept(env):
    a = Manager(str(env), {})
    b = Manager(str(env), {})
    assert a.fleet_code == b.fleet_code and len(a.fleet_code) == 19
    assert a.fleet_code_is_generated


async def _upload(client, data: bytes, name="Jeeves.ipa"):
    form = aiohttp.FormData()
    form.add_field("file", data, filename=name)
    return await client.post("/api/package/upload", data=form)


@pytest.mark.asyncio
async def test_uploaded_package_overrides_published(env, monkeypatch):
    m, client = await start(env)
    try:
        async def fake_download(url):
            return m.package.published.store(make_ipa("1.0"), url)
        monkeypatch.setattr(m.package, "download", fake_download)

        info = await (await client.post("/api/package/download", json={})).json()
        assert info["active"] == "published" and info["published"]["version"] == "1.0"
        assert info["published"]["source"].startswith("https://github.com/")

        info = await (await _upload(client, make_ipa("2.0-dev"))).json()
        assert info["active"] == "custom" and info["custom"]["source"] == "Jeeves.ipa"
        assert m.package.describe_active() == "your uploaded package, Jeeves 2.0-dev (7)"
        assert m.package.install_ready().startswith(str(env / "data" / "packages" / "custom"))

        # A new published release doesn't replace the uploaded package
        info = await (await client.post("/api/package/download", json={})).json()
        assert info["active"] == "custom"

        # A bad upload keeps the current one
        res = await _upload(client, b"not a zip")
        assert res.status == 400 and "isn't an .ipa" in (await res.json())["error"]
        bad = io.BytesIO()
        with zipfile.ZipFile(bad, "w") as z:
            z.writestr("Payload/Other.app/Info.plist", b"")
        res = await _upload(client, bad.getvalue())
        assert res.status == 400
        assert m.package.custom.info()["version"] == "2.0-dev"

        # Not while an install is copying files
        m._installs = 1
        res = await client.delete("/api/package/custom")
        assert res.status == 400 and "being installed" in (await res.json())["error"]
        m._installs = 0

        info = await (await client.delete("/api/package/custom")).json()
        assert info["active"] == "published" and info["custom"] is None
        assert m.package.describe_active() == "the published release, Jeeves 1.0 (7)"
    finally:
        await client.close()


def test_single_package_from_earlier_versions_is_migrated(env):
    data = env / "data"
    data.mkdir()
    (data / "Jeeves.ipa").write_bytes(make_ipa("0.9"))
    (data / "Jeeves.ipa.json").write_text('{"version": "0.9", "build": "7", "source": "my-build.ipa", "size": 1, "added": 0}')
    (data / "payload").mkdir()
    m = Manager(str(data), {"fleet_code": CODE})
    assert m.package.info()["active"] == "custom"
    assert m.package.custom.info()["version"] == "0.9"
    assert not (data / "Jeeves.ipa").exists() and not (data / "payload").exists()
    assert m.package.install_ready().endswith("Jeeves.app")
