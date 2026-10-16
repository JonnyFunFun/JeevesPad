# Jeeves Development Guide

Jeeves is a Home Assistant control app for jailbroken iOS devices (targets iOS 9.3.5).

## Build Systems

This project uses **two build systems** that must be kept in sync:

1. **Theos** - Primary build for deployment to jailbroken devices
2. **Xcode** - For code editing, IDE features, and simulator testing

When adding new files, update BOTH:
- `Makefile` - Add `.m` files to `Jeeves_FILES`
- `Jeeves.xcodeproj/project.pbxproj` - Add file references and build phases

## Deploying to Device

### Prerequisites

- [Theos](https://theos.dev/docs/installation) installed
- Jailbroken iOS device with SSH enabled
- `sshpass` installed (`brew install hudochenkov/sshpass/sshpass`)

### Deploy

```bash
# Set your device IP and run
IPAD_IP=192.168.1.xxx ./deploy.sh

# Or every iPad in the fleet (Bonjour discovery and/or -f hosts file)
./deploy_fleet.sh
```

Or edit `deploy.sh` and set `IPAD_IP` directly. Both scripts share `deploy_common.sh` (password check/prompt, build, install).

### SSH Access

```bash
ssh root@<DEVICE_IP>
# Default password: alpine
```

### Viewing Logs

```bash
ssh root@<DEVICE_IP>
tail -f /var/log/syslog | grep Jeeves
```

`/var/log/syslog` only exists if a syslog-to-file package is installed on the device.

Crash logs:
```bash
ls -la /var/mobile/Library/Logs/CrashReporter/
cat /var/mobile/Library/Logs/CrashReporter/Jeeves-*.ips
```

iOS 9 crash reports don't include the exception message, so the app records the last uncaught exception (name, reason and symbolicated call stack) itself:
```bash
cat /var/mobile/Library/Logs/Jeeves-exception.log
```

If the app disappears with no `Jeeves-*.ips` report, it was probably killed for using too much memory: look for a `JetsamEvent-*.ips` in the same directory (`largestProcess` and each process's `rpages` × 4KB). Target devices have little RAM (an iPad mini has 512MB), so keep caches bounded and release them on memory warnings.

## Building

### Theos (for deployment)
```bash
make clean && make package FINALPACKAGE=1
```

Output: `packages/com.jeeves.app_X.X.X_iphoneos-arm.deb`

### IPA (for distribution)
```bash
./build_ipa.sh
```

Output: `Jeeves.ipa`

## Architecture

### UI Layout
- **Standard Spacing**: 12.0 points throughout the app
- **Entity Cards**: Tap to toggle, vertical drag for brightness (dimmable lights only; disabled via `allowsBrightnessDrag` where cards scroll — HA dashboards, and rooms that overflow — so drags scroll and the inline brightness slider is shown instead)
- **Tap Feedback**: 6px golden border animation (100ms fade in/out)

### Orientation-Aware Layouts

The app uses different layouts for landscape and portrait. Orientation is detected using `isPortraitOrientation` which compares `contentView.bounds` width vs height.

**Home Screen - Landscape:**
- Left 50%: Weather (current top, 6-day forecast bottom in 2x3 grid)
- Right 50%: Entity cards in 2-column grid

**Home Screen - Portrait:**
- Top: Entity cards in 4-column grid
- Bottom: Weather section

### Supported Entity Types

| Type | Behavior |
|------|----------|
| `light.*` | Toggle on/off, brightness slider (if supported) |
| `switch.*` | Toggle on/off |
| `sensor.*` | Display only (read-only) |
| `binary_sensor.*` | Display only (read-only) |
| `script.*` | Tap to trigger (play icon) |
| `input_boolean.*` | Toggle on/off |

### Drag-Drop Reordering

Entity cards on the Home screen support drag-to-reorder:

1. **Long-press** (0.5s) lifts a card
2. **Drag**: Dashed placeholder shows drop position
3. **Release**: Order persists to UserDefaults

Key methods:
- `handleHomeSensorLongPress:` - Gesture handler
- `createDropPlaceholderWithFrame:` - Visual feedback
- `updateDropPlaceholderToIndex:` - Position updates

### Card Customization

Each card can be renamed and resized per dashboard (Home or a room) from the "Card" section of the more-info screen (long-press a card). Settings live in `JeevesCardSettings`, keyed by dashboard ID (`JeevesHomeDashboardID` or the room's `roomId`) and entity ID; the entity isn't renamed in Home Assistant.

- **Sizes**: X-Small 1×½, Small 1×1, Wide 2×1, Tall 1×2, Large 2×2 cells. Rows are packed in half-row units (Small = 2 half-rows), so two X-Small cards stack in one Small slot. `JeevesCardSize` raw values are persisted — append new sizes, and use `+orderedSizes` for display order
- **Short cards**: Home cards under 76pt tall switch to a single-row layout (name, value, effect button); room cards under 110pt use a one-line name and smaller status
- **Layout**: cards are packed first-fit in order (`+[JeevesCardSettings packSpans:columns:rowCount:]`) — by hand on Home, via `JeevesGridLayout` in rooms

### Fleets

Every running Jeeves advertises `_jeeves._tcp` (`JeevesFleetService`, `NSNetService` with `NSNetServiceListenForConnections`) and browses for the others; `deploy_fleet.sh` uses the same service type. Settings are shared with one request per connection (length-prefixed binary plists; `push` applies the sender's settings, `pull` returns the receiver's), sealed with the fleet code (`JeevesFleetCrypto`). Incoming requests are refused when replayed (MACs remembered for the clock-skew window), beyond 8 simultaneous connections, or when the fleet code is shorter than `JeevesFleetMinimumCodeLength` (8). `JeevesFleetSettings` defines which `NSUserDefaults` keys are shared (`+sharedKeys`) — add new settings there if they should sync, and add a `reloadFromDefaults` to any singleton that caches them. After applying, `AppDelegate -fleetSettingsApplied:` rebuilds the root UI (calling `-[JeevesDashboardViewController stopUpdates]` so the old dashboard is released).

### Home Assistant App and Integration

- `jeevespad/` is a Home Assistant app (formerly add-on; `repository.yaml` at the root makes this repo an app repository). Python (aiohttp) in `jeevespad/app/jeevespad_manager/`, UI in `static/` (plain JS, no build step), served through ingress. Entities are chosen with `entityPicker`/`entityListPicker` in `app.js` (search over name, ID, area, device and type; `ENTITY_FILTERS` limits each picker to suitable entities); `/api/entities` adds areas and device names with one `/api/template` render (`LOCATIONS_TEMPLATE`, tested against HA's engine in `tests_integration`). Colours come from Home Assistant: `theme.js` copies HA's theme variables (`--primary-background-color`, `--primary-color`, …) from the parent page's root element (ingress is same-origin) and follows changes; `style.css` holds HA's default light/dark palette as the fallback. It runs on the host network for Bonjour, so `__main__` only listens on localhost and the Supervisor network's gateway (option `listen_on_all_addresses` as an escape hatch), and `server.py` only answers the ingress proxy (172.30.32.2 plus its `X-Ingress-Path` header) and, under `/api/v1/`, the integration's API key (throttled). UI requests that change something need `X-Requested-With: jeevespad` (CSRF); keep the strict CSP (no inline scripts or `style` attributes in markup; set styles from JS). Every wallPad address goes through `hosts.normalize_host` (it becomes an ssh argument); Bonjour addresses (`seen_host`) only become the SSH address (`host`) after an authenticated fleet reply. Base image is set in the `Dockerfile` (no `build.yaml` since Supervisor 2026.04), and the command runs under s6's `with-contenv`, or `SUPERVISOR_TOKEN` is missing.
- `fleet.py` reimplements `JeevesFleetCrypto`/`JeevesFleetService` (keep them in sync). Requests the app sends: `status`, `command`, `pull`, `push` (partial: only listed `keys` change; portable `rooms`). `settings.py` maps snapshots to the editor's JSON. Never send `rooms` to an iPad whose status lacks the `rooms` feature.
- App packages (`package.py`): a `custom` slot (uploaded) overrides the `published` slot (downloaded, default the latest GitHub release) under `/data/packages/`; the manager refuses to change packages while an install job runs.
- SSH maintenance (`ssh.py`) uses the same commands as `deploy_common.sh`. Every install first runs the same dependency script (`DEPENDENCIES_SCRIPT` / `JEEVES_DEPENDENCIES_SCRIPT`, keep identical) to `apt-get install` missing Cydia packages: `uikittools` (uicache, required) and `com.conradkramer.open` (open, for remote launch; a warning if it can't be installed). Setting up an iPad writes `~mobile/Library/Jeeves/provision.plist` (fleet code + optional settings snapshot), which `-[JeevesFleetSettings applyProvisioningFileIfPresent]` applies and deletes at launch.
- `custom_components/jeevespad/` (with `hacs.json`) is the HACS integration: discovered via Supervisor discovery (`discovery: [jeevespad]`), polls `/api/v1/wallpads`.
- Tests: `cd jeevespad/app && pytest` (fake wallPads and a fake `sshpass`; needs `requirements.txt` + `pytest-asyncio`); `pytest -c tests_integration/pytest.ini tests_integration` (needs `pytest-homeassistant-custom-component`). Use separate virtualenvs: the Home Assistant pytest plugin loads globally and breaks the app's tests.

### Presence (Bermuda)

`JeevesPhoneRegistry` registers phones' IRKs with Home Assistant's `private_ble_device` integration (which Bermuda tracks automatically) by driving its config flow over REST (`/api/config/config_entries/flow`), then names the config entry and device over the WebSocket API (Bermuda copies the device's `name_by_user`). Keys are normalised the way HA does: hex as given, base64 byte-reversed. HA only accepts a key for a phone a Bluetooth scanner currently sees (`irk_not_found`), and these endpoints need an admin token. When given several possible keys (pairing), it tries each until HA stops answering `irk_not_found`.

Pairing (`JeevesPhonePairer`): the iPad advertises a `CBPeripheralManager` service whose characteristic needs encryption, so reading it (from nRF Connect/LightBlue) pairs. Pairing initiated by the phone (Android's Settings → Pair new device) connects, shows the iPad's own name, then drops: an iOS peripheral only takes pairing it requested. iOS's `bluetoothd` stores the peer's keys in the keychain: generic passwords in access group `apple`, service `MobileBluetooth` (`BluetoothGlobal` holds the iPad's own). The `ledevices.*.db` databases have no keys. Jeeves is signed with `keychain-access-groups` [`com.jeeves.Jeeves`, `apple`] (`entitlements.plist`, applied by `build_ipa.sh`). It snapshots those items, polls for new or changed ones after pairing, and offers every 16-byte value in both byte orders (IRK-named ones first). The item layout isn't documented, so this was worked out on the device; `/var/mobile/Library/Logs/Jeeves-pairing.log` records it (no key values). On iOS 9, `keychain-2.db` stores `svce`/`acct` as SHA-1 hashes, so service names can be checked offline by hashing candidates.

UI: Settings → Presence (`JeevesPresenceViewController`; `JeevesPairPhoneViewController` pairs, `JeevesAddPhoneViewController` takes a pasted key).

### Guided Access

`JeevesGuidedAccess` starts and ends Guided Access with `UIAccessibilityRequestGuidedAccessSession` (Autonomous Single App Mode), which iOS only allows on a supervised iPad whose profile lists `com.jeeves.Jeeves` in `autonomousSingleAppModePermittedAppIDs`. Whether it's wanted is per-device (`JeevesGuidedAccessWanted`, re-requested at launch); the unlock code (`JeevesGuidedAccessCode`) is a shared fleet setting, since these sessions have no Guided Access passcode. Remote control: the fleet `command` `guided_access` (value true/false), with the result in `status` (`guidedAccess`, `guidedAccessError`). UI: Settings → Guided Access (`JeevesGuidedAccessViewController`).

### Maintenance Mode

`JeevesMaintenance` shows a full-screen notice in its own `UIWindow` at `UIWindowLevelAlert + 1` (above alerts), which takes every touch. On/off and the message are per-device defaults (`JeevesMaintenanceActive`, `JeevesMaintenanceMessage`), restored at launch. Remote: fleet `command` `maintenance` with value `{on, message}`; status reports `maintenance`/`maintenanceMessage`. Local escape: hold the notice 5s, enter the Guided Access unlock code (5 wrong → 60s lockout); no code set → only Home Assistant can end it.

### Idle Mode

`JeevesApplication` (a `UIApplication` subclass set in `main.m`) reports every touch to `JeevesIdleManager`, which returns to Home after `homeTimeout` (default 180s; `AppDelegate -returnToHome`) and dims the screen via `UIScreen.brightness` at twice that, holding off Auto-Lock while dimming is enabled. The touch that wakes a dimmed screen is swallowed. `JeevesMotionDetector` (front camera, frame differencing; opt-in) wakes the screen while dimmed. Pre-dim brightness is persisted and restored on resign-active or relaunch.

### Home Weather Column

Configured in `JeevesWeatherSettings` (edited in `JeevesWeatherSettingsViewController`; long-press the weather column or Settings → Customize Home Weather): weather entity (automatic/none/specific — supplies condition, icon and forecast), temperature source (weather entity or a sensor), and extra sensor readings shown as tiles. Without a weather entity the conditions card fills the column. The column is only rebuilt when its layout signature changes (`weatherLayoutSignature`); values update every refresh via `updateCurrentConditions`.

### Home Assistant (Lovelace) Dashboards

The HA frontend requires iOS/Safari 12+, so dashboards can't be shown in a web view. Instead `JeevesLovelaceViewController` fetches the config over HA's WebSocket API (`HAWebSocketClient`, using `JeevesWebSocket` since iOS 9 has no WebSocket support) and `JeevesLovelaceDashboard` translates cards into native items (entity cards, headings, text, placeholders) shown in a `JeevesGridLayout`. Auto-generated dashboards return `config_not_found` and can't be shown.

## Key Files

| File | Purpose |
|------|---------|
| `AppDelegate.m` | Entry point, loads JeevesDashboardViewController |
| `JeevesDashboardViewController.h/m` | Main dashboard (Home/Rooms tabs, weather, entities) |
| `JeevesRoom.h/m` | Room model + JeevesRoomManager singleton |
| `JeevesRoomDetailViewController.h/m` | Individual room view |
| `JeevesLightToggleCell.h/m` | Entity card (tap-toggle, brightness drag) |
| `JeevesThemeManager.h/m` | Centralized theming |
| `HAAPIClient.h/m` | Home Assistant REST API client |
| `HAEntity.h/m` | Entity model |

## API Integration

Uses Home Assistant REST API:

```
GET  /api/states                           # Fetch all entities
POST /api/services/{domain}/{service}      # Call services
POST /api/services/weather/get_forecasts   # Weather forecast
GET  /api/camera_proxy/{entity_id}         # Camera stream
```

Lovelace dashboards are only available over the WebSocket API (`/api/websocket`: `lovelace/dashboards/list`, `lovelace/config`).

All requests use Bearer token authentication.

## Theming

Colors defined in `JeevesThemeManager`:
- `backgroundColor` - Main background
- `cardBackgroundColor` - Entity cards
- `textColor` / `secondaryTextColor` - Text
- `onColor` - Active state (golden yellow)
- `offColor` - Inactive state

## iOS 9 UIStackView Pitfall

On iOS 9, a `UIStackView` with a non-default `alignment` (center, leading, …) or an `EqualSpacing`/`EqualCentering` distribution crashes when it's deallocated: `-[_UILayoutSpacer _didRemoveDependentConstraint:]: unrecognized selector` (fixed in iOS 10). Only use stack views with the default `Fill` alignment and `Fill`/`FillEqually` distribution; build anything else with plain constraints or frames (see `rowWithTitle:control:` in `JeevesEntityMoreInfoViewController` and `JeevesSwatchRowView`).

## Modal Presentation

All modals use `UIModalPresentationFullScreen` for consistent appearance across iOS versions.
