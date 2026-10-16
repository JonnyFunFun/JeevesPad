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
  *"deps="*)
    if [ -n "$FAKE_MISSING_DEPS" ]; then echo "Installing $FAKE_MISSING_DEPS from Cydia..."; fi
    if [ "$FAKE_DEPS_RESULT" = "fail" ]; then echo "deps=failed uikittools"; exit 4; fi
    echo "deps=ok" ;;
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
    client = TestClient(TestServer(create_app(m, dev=True)), headers={"X-Requested-With": "jeevespad"})
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
        assert "Enroll it" in (await res.json())["error"]
    finally:
        await client.close(); await pad.stop()


@pytest.mark.asyncio
async def test_provision_installs_and_enrolls(env, monkeypatch):
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

        log = (env / "ssh.log").read_text().splitlines()
        mkdir = next(i for i, line in enumerate(log) if "mkdir -p /Applications/Jeeves.app" in line)
        copy = next(i for i, line in enumerate(log) if line.startswith("scp ") and "/Applications/" in line)
        removal = max(i for i, line in enumerate(log) if "rm -rf /Applications/Jeeves.app" in line)
        assert removal < mkdir < copy  # the app folder exists when scp copies into it
        assert any("uicache" in line for line in log[copy:])
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


@pytest.mark.asyncio
async def test_ui_assets_are_versioned(env):
    m, client = await start(env)
    try:
        html = await (await client.get("/")).text()
        assert 'src="static/app.js?v=' in html and 'href="static/style.css?v=' in html
        assert 'src="static/theme.js?v=' in html
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


@pytest.mark.asyncio
async def test_guided_access_and_unlock_code(env, monkeypatch):
    monkeypatch.setattr(manager_module, "GUIDED_ACCESS_WAIT", 3)
    pad = FakeWallPad("Kitchen", CODE)
    unsupervised = FakeWallPad("Hall", CODE, instance_id="ffff0000")
    unsupervised.supervised = False
    await pad.start(); await unsupervised.start()
    m, client = await start(env)
    try:
        await advertise(m, pad)
        await advertise(m, unsupervised)

        res = await client.post("/api/wallpads/abcd1234/guided-access", json={"on": True})
        assert res.status == 200 and (await res.json())["status"]["guidedAccess"] is True
        assert ("guided_access", True) in pad.commands
        res = await client.post("/api/wallpads/ffff0000/guided-access", json={"on": True})
        assert res.status == 400 and "didn't let Jeeves" in (await res.json())["error"]

        # Integration API reports it, and can toggle it
        headers = {"Authorization": f"Bearer {m.api_key}"}
        pads = {p["id"]: p for p in await (await client.get("/api/v1/wallpads", headers=headers)).json()}
        assert pads["abcd1234"]["guided_access"] is True
        res = await client.post("/api/v1/wallpads/abcd1234/guided-access", json={"on": False}, headers=headers)
        assert res.status == 200 and pad.guided_access is False

        # The unlock code goes to every wallPad and is kept for new ones
        assert (await (await client.post("/api/guided-access-code", json={"code": "12ab"})).json())["error"]
        res = await (await client.post("/api/guided-access-code", json={"code": "4826"})).json()
        assert res["results"] == {"abcd1234": None, "ffff0000": None}
        assert pad.defaults["JeevesGuidedAccessCode"] == "4826" and unsupervised.defaults["JeevesGuidedAccessCode"] == "4826"
        assert pad.defaults["JeevesIdleHomeTimeout"] == 300  # nothing else changed
        assert (await (await client.get("/api/state")).json())["guided_access_code_set"] is True
        provision = await m._provision_payload(manager_module.Job(id="x", title="t"), None, None, None)
        assert provision["settings"]["values"]["JeevesGuidedAccessCode"] == "4826"

        await client.post("/api/guided-access-code", json={"code": ""})
        assert "JeevesGuidedAccessCode" not in pad.defaults
        assert m.unlock_code is None
    finally:
        await client.close(); await pad.stop(); await unsupervised.stop()


@pytest.mark.asyncio
async def test_install_adds_missing_cydia_packages(env, monkeypatch):
    m, client = await start(env)
    try:
        form = aiohttp.FormData()
        form.add_field("file", make_ipa("1.2"), filename="Jeeves.ipa")
        await client.post("/api/package/upload", data=form)
        pad = m.add_manual("10.0.0.7")

        monkeypatch.setenv("FAKE_MISSING_DEPS", "uikittools com.conradkramer.open")
        job = await wait_job(client, (await (await client.post("/api/update-app", json={"wallpads": [pad.id]})).json())["id"])
        assert job["state"] == "done", job["log"]
        lines = [l["line"] for l in job["log"]]
        assert "Installing uikittools com.conradkramer.open from Cydia..." in lines
        log = (env / "ssh.log").read_text().splitlines()
        deps = next(i for i, line in enumerate(log) if "deps=" in line)
        copy = next(i for i, line in enumerate(log) if line.startswith("scp "))
        assert deps < copy

        monkeypatch.setenv("FAKE_DEPS_RESULT", "fail")
        job = await wait_job(client, (await (await client.post("/api/update-app", json={"wallpads": [pad.id]})).json())["id"])
        assert job["state"] == "failed"
        assert any("Couldn't install UIKit Tools" in l["line"] for l in job["log"])
    finally:
        await client.close()


# --- hardening -------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_csrf_and_security_headers(env):
    m, client = await start(env)
    try:
        # Changing something needs the header this page sends; another site's page can't send it
        res = await client.post("/api/wallpads", json={"host": "10.0.0.8"}, headers={"X-Requested-With": ""})
        assert res.status == 403
        res = await client.post("/api/wallpads", json={"host": "10.0.0.8"}, headers={"Sec-Fetch-Site": "cross-site"})
        assert res.status == 403
        assert (await client.post("/api/wallpads", json={"host": "10.0.0.8"})).status == 200

        res = await client.get("/")
        csp = res.headers["Content-Security-Policy"]
        assert "script-src 'self'" in csp and "frame-ancestors 'self'" in csp and "unsafe" not in csp
        assert res.headers["X-Content-Type-Options"] == "nosniff"
        assert (await client.get("/api/state")).headers["Cache-Control"] == "no-store"

        # Request bodies are limited (uploads are streamed separately)
        res = await client.post("/api/wallpads", data=b"{" + b" " * (2 * 1024 * 1024) + b"}",
                                headers={"Content-Type": "application/json"})
        assert res.status == 413
    finally:
        await client.close()


@pytest.mark.asyncio
async def test_ingress_only_and_api_key_throttle(env):
    m = Manager(str(env), {"fleet_code": CODE})
    client = TestClient(TestServer(create_app(m, dev=False)), headers={"X-Requested-With": "jeevespad"})
    await client.start_server()
    try:
        # Not the ingress proxy: refused, even with ingress's header
        assert (await client.get("/api/state", headers={"X-Ingress-Path": "/x"})).status == 403
        # Integration API: wrong keys are throttled, and then even the right key waits
        for _ in range(10):
            assert (await client.get("/api/v1/wallpads", headers={"Authorization": "Bearer nope"})).status == 401
        assert (await client.get("/api/v1/wallpads", headers={"Authorization": f"Bearer {m.api_key}"})).status == 429
        assert (await client.get("/api/v1/wallpads")).status == 429
    finally:
        await client.close()


@pytest.mark.asyncio
async def test_addresses_are_validated(env):
    m, client = await start(env)
    try:
        for bad in ["-oProxyCommand=touch /tmp/pwned", "10.0.0.1 -oX", "host;reboot", "a..b", "$(id)", "root@10.0.0.1"]:
            res = await client.post("/api/wallpads", json={"host": bad})
            assert res.status == 400, bad
            res = await client.post("/api/provision", json={"host": bad})
            assert res.status == 400, bad
        pad = (await (await client.post("/api/wallpads", json={"host": " 10.0.0.8 "})).json())
        assert pad["address"] == "10.0.0.8"
        res = await client.patch(f"/api/wallpads/{pad['id']}", json={"ssh_host": "-oProxyCommand=x"})
        assert res.status == 400
        assert (await client.post("/api/wallpads", json={"host": "kitchen-ipad.local"})).status == 200
        assert (await client.post("/api/wallpads", json={"host": "fe80::1"})).status == 200
        # And ssh itself refuses, should anything get past the checks
        with pytest.raises(Exception, match="valid IP address"):
            await m.ssh.run("-oProxyCommand=x", "alpine", "true")
        assert not (env / "ssh.log").exists()
    finally:
        await client.close()


@pytest.mark.asyncio
async def test_spoofed_advertisement_does_not_redirect_ssh(env):
    pad = FakeWallPad("Kitchen", CODE)
    impostor = FakeWallPad("Kitchen", "the-attackers-code", instance_id=pad.instance_id)
    await pad.start(); await impostor.start("127.0.0.2")
    m, client = await start(env)
    try:
        await advertise(m, pad, host="127.0.0.1")
        await client.post(f"/api/wallpads/{pad.instance_id}/refresh")
        assert m.wallpads[pad.instance_id].address == "127.0.0.1"  # verified by a fleet reply

        # Something else on the network claims to be the same wallPad
        m.discovery.advertisements["Kitchen"] = Advertisement(
            name="Kitchen", host="127.0.0.2", port=impostor.port, instance_id=pad.instance_id,
            app_version="1.0", sync_enabled=True)
        m._discovery_changed()
        await asyncio.sleep(0.2)
        await client.post(f"/api/wallpads/{pad.instance_id}/refresh")
        target = m.wallpads[pad.instance_id]
        assert target.seen_host == "127.0.0.2"
        assert "different fleet code" in target.status_error  # it answered, but couldn't prove itself
        assert target.address == "127.0.0.1"  # SSH (and the root password) still goes to the real iPad
    finally:
        await client.close(); await pad.stop(); await impostor.stop()


@pytest.mark.asyncio
async def test_commands_are_limited(env):
    pad = FakeWallPad("Kitchen", CODE)
    await pad.start()
    m, client = await start(env)
    try:
        await advertise(m, pad)
        for body in [{"command": "rm -rf"}, {"command": "brightness", "value": 7}, {"command": "brightness", "value": "1"},
                     {"command": "guided_access", "value": False}]:
            res = await client.post("/api/wallpads/abcd1234/command", json=body)
            assert res.status == 400, body
        assert pad.commands == []
    finally:
        await client.close(); await pad.stop()


def test_short_fleet_code_is_refused(env):
    with pytest.raises(manager_module.ManagerError, match="at least 8"):
        Manager(str(env), {"fleet_code": "1234"})


@pytest.mark.asyncio
async def test_malicious_packages_are_refused(env, monkeypatch):
    m, client = await start(env)
    try:
        def ipa_with(name, data=b"x", attr=None):
            buf = io.BytesIO()
            with zipfile.ZipFile(buf, "w") as z:
                z.writestr("Payload/Jeeves.app/Info.plist", plistlib.dumps({"CFBundleIdentifier": "com.jeeves.Jeeves"}))
                info = zipfile.ZipInfo(name)
                if attr is not None:
                    info.external_attr = attr
                z.writestr(info, data)
            return buf.getvalue()

        for data, why in [(ipa_with("../../evil.sh"), "unsafe path"),
                          (ipa_with("Payload/Jeeves.app/link", b"/etc/passwd", (0o120777 << 16)), "symbolic link")]:
            form = aiohttp.FormData()
            form.add_field("file", data, filename="Jeeves.ipa")
            res = await client.post("/api/package/upload", data=form)
            assert res.status == 400 and why in (await res.json())["error"]
        monkeypatch.setattr("jeevespad_manager.package.MAX_UNPACKED", 1000)
        form = aiohttp.FormData()
        form.add_field("file", ipa_with("Payload/Jeeves.app/big", b"0" * 5000), filename="Jeeves.ipa")
        res = await client.post("/api/package/upload", data=form)
        assert res.status == 400 and "too large" in (await res.json())["error"]

        res = await client.post("/api/package/download", json={"url": "file:///etc/passwd"})
        assert res.status == 400 and "https://" in (await res.json())["error"]
    finally:
        await client.close()


@pytest.mark.asyncio
async def test_listens_only_where_needed(env, monkeypatch):
    from jeevespad_manager.__main__ import listen_addresses
    m = Manager(str(env), {"fleet_code": CODE})
    assert await listen_addresses(m, dev=True) == ["0.0.0.0"]
    m.supervisor.token = "token"  # running in Home Assistant

    async def gateway():
        return "172.30.32.1"
    monkeypatch.setattr(m.supervisor, "network_gateway", gateway)
    assert await listen_addresses(m, dev=False) == ["127.0.0.1", "172.30.32.1"]
    m.options["listen_on_all_addresses"] = True
    assert await listen_addresses(m, dev=False) == ["0.0.0.0"]


@pytest.mark.asyncio
async def test_enroll_sets_fleet_code_over_ssh(env):
    pad = FakeWallPad("Kitchen", CODE)
    await pad.start()
    m, client = await start(env)
    try:
        await advertise(m, pad)
        await client.post("/api/wallpads/abcd1234/refresh")  # verifies its address for SSH
        res = await client.post("/api/wallpads/abcd1234/enroll", json={"settings_source": None})
        assert res.status == 200, await res.text()
        job = await wait_job(client, (await res.json())["id"])
        assert job["title"] == "Enroll Kitchen" and job["state"] == "done", job["log"]
        provision = plistlib.loads((env / "provision.plist").read_bytes())
        assert provision["fleetCode"] == CODE and provision["fleetEnabled"] is True
        assert any("killall Jeeves" in line for line in (env / "ssh.log").read_text().splitlines())
    finally:
        await client.close(); await pad.stop()


@pytest.mark.asyncio
async def test_entity_list_for_pickers(monkeypatch):
    from jeevespad_manager.supervisor import Supervisor
    sup = Supervisor()

    async def core(method, path, json=None):
        return [{"entity_id": "sensor.porch_temp", "state": "14", "attributes": {
                    "friendly_name": "Porch Temperature", "unit_of_measurement": "°C", "device_class": "temperature"}},
                {"entity_id": "weather.home", "state": "sunny", "attributes": {}}]

    async def core_text(method, path, json_body=None):
        assert path == "/api/template" and "area_name" in json_body["template"]
        return '[["sensor.porch_temp", "Porch", "Multisensor"], ["weather.home", "", ""]]'
    monkeypatch.setattr(sup, "core", core)
    monkeypatch.setattr(sup, "core_text", core_text)
    entities = {e["entity_id"]: e for e in await sup.entities()}
    assert entities["sensor.porch_temp"] == {"entity_id": "sensor.porch_temp", "name": "Porch Temperature", "domain": "sensor",
                                             "state": "14", "unit": "°C", "device_class": "temperature",
                                             "area": "Porch", "device": "Multisensor"}
    assert entities["weather.home"]["name"] == "weather.home" and entities["weather.home"]["area"] == ""

    async def broken(method, path, json_body=None):
        raise RuntimeError("template API unavailable")
    monkeypatch.setattr(sup, "core_text", broken)  # areas are optional
    assert (await sup.entities())[0]["area"] == ""


@pytest.mark.asyncio
async def test_maintenance_mode(env):
    pad = FakeWallPad("Kitchen", CODE)
    await pad.start()
    m, client = await start(env)
    try:
        await advertise(m, pad)
        res = await client.post("/api/wallpads/abcd1234/maintenance", json={"on": True, "message": "  Back at 3pm  "})
        assert res.status == 200, await res.text()
        assert (await res.json())["status"]["maintenance"] is True
        assert pad.maintenance and pad.maintenance_message == "Back at 3pm"

        headers = {"Authorization": f"Bearer {m.api_key}"}
        pads = {p["id"]: p for p in await (await client.get("/api/v1/wallpads", headers=headers)).json()}
        assert pads["abcd1234"]["maintenance"] is True
        res = await client.post("/api/v1/wallpads/abcd1234/maintenance", json={"on": False}, headers=headers)
        assert res.status == 200 and pad.maintenance is False

        for body in [{"on": "yes"}, {"on": True, "message": 7}, {"on": True, "message": "x" * 501}]:
            assert (await client.post("/api/wallpads/abcd1234/maintenance", json=body)).status == 400, body
        assert pad.maintenance is False
        # Only through its own endpoint: not as a generic command
        assert (await client.post("/api/wallpads/abcd1234/command", json={"command": "maintenance"})).status == 400
    finally:
        await client.close(); await pad.stop()
