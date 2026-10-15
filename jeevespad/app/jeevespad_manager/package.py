"""The Jeeves app package (Jeeves.ipa) installed on wallPads.

The add-on can't build Jeeves (that needs Theos and the iOS 9.3 SDK), so it installs a
package built with build_ipa.sh: uploaded on the App page, or downloaded from a URL
(by default the latest GitHub release).
"""

from __future__ import annotations

import json
import os
import plistlib
import shutil
import time
import zipfile

import aiohttp

DEFAULT_URL = "https://github.com/JonnyFunFun/JeevesPad/releases/latest/download/Jeeves.ipa"
MAX_SIZE = 200 * 1024 * 1024
APP_DIR_NAME = "Jeeves.app"


class PackageError(Exception):
    pass


class Package:
    def __init__(self, data_dir: str) -> None:
        self.ipa_path = os.path.join(data_dir, "Jeeves.ipa")
        self.meta_path = os.path.join(data_dir, "Jeeves.ipa.json")
        self.extract_dir = os.path.join(data_dir, "payload")

    @property
    def app_dir(self) -> str:
        return os.path.join(self.extract_dir, "Payload", APP_DIR_NAME)

    def info(self) -> dict | None:
        if not os.path.exists(self.ipa_path):
            return None
        try:
            with open(self.meta_path) as f:
                return json.load(f)
        except (OSError, ValueError):
            return None

    def install_ready(self) -> str:
        """Path of the extracted Jeeves.app, extracting it if needed."""
        if not os.path.exists(self.ipa_path):
            raise PackageError("There's no Jeeves app package yet. Upload Jeeves.ipa or download it on the App page.")
        if not os.path.isdir(self.app_dir):
            self._extract()
        return self.app_dir

    def _extract(self) -> dict:
        shutil.rmtree(self.extract_dir, ignore_errors=True)
        os.makedirs(self.extract_dir)
        root = os.path.realpath(self.extract_dir)
        with zipfile.ZipFile(self.ipa_path) as archive:
            for member in archive.infolist():
                target = os.path.realpath(os.path.join(root, member.filename))
                if not target.startswith(root + os.sep):
                    raise PackageError(f"The package contains an unsafe path: {member.filename}")
            archive.extractall(root)
        info_plist = os.path.join(self.app_dir, "Info.plist")
        if not os.path.exists(info_plist):
            raise PackageError("That isn't a Jeeves package (no Payload/Jeeves.app/Info.plist)")
        with open(info_plist, "rb") as f:
            info = plistlib.load(f)
        if info.get("CFBundleIdentifier") != "com.jeeves.Jeeves":
            raise PackageError(f"That package is {info.get('CFBundleIdentifier')!r}, not Jeeves")
        return info

    def store(self, data: bytes, source: str) -> dict:
        """Saves and validates a new package."""
        if not data.startswith(b"PK"):
            raise PackageError("That isn't an .ipa file (a zip archive)")
        tmp = self.ipa_path + ".new"
        with open(tmp, "wb") as f:
            f.write(data)
        old = self.ipa_path + ".old"
        if os.path.exists(self.ipa_path):
            os.replace(self.ipa_path, old)
        os.replace(tmp, self.ipa_path)
        try:
            info = self._extract()
        except (PackageError, zipfile.BadZipFile, plistlib.InvalidFileException) as err:
            # Put the previous package back
            if os.path.exists(old):
                os.replace(old, self.ipa_path)
                self._extract()
            else:
                os.remove(self.ipa_path)
                shutil.rmtree(self.extract_dir, ignore_errors=True)
            raise PackageError(str(err) if isinstance(err, PackageError) else "The package couldn't be read") from err
        if os.path.exists(old):
            os.remove(old)
        meta = {
            "version": info.get("CFBundleShortVersionString", "?"),
            "build": info.get("CFBundleVersion", "?"),
            "size": len(data),
            "source": source,
            "added": time.time(),
        }
        with open(self.meta_path, "w") as f:
            json.dump(meta, f)
        return meta

    async def download(self, url: str) -> dict:
        timeout = aiohttp.ClientTimeout(total=300)
        try:
            async with aiohttp.ClientSession(timeout=timeout) as session:
                async with session.get(url) as response:
                    if response.status != 200:
                        raise PackageError(f"Download failed: HTTP {response.status} from {url}")
                    data = bytearray()
                    async for chunk in response.content.iter_chunked(65536):
                        data.extend(chunk)
                        if len(data) > MAX_SIZE:
                            raise PackageError("The download is too large to be a Jeeves package")
        except aiohttp.ClientError as err:
            raise PackageError(f"Download failed: {err}") from err
        return self.store(bytes(data), url)
