# Jeeves

A native iOS app for controlling Home Assistant, designed for jailbroken devices running iOS 9 — so an old iPad can live on as a wall-mounted smart home panel. Named after P.G. Wodehouse's gentleman's personal gentleman, who always knew just what was wanted.

**Repository:** [github.com/JonnyFunFun/JeevesPad](https://github.com/JonnyFunFun/JeevesPad) · [Issues](https://github.com/JonnyFunFun/JeevesPad/issues)

![iOS 9.3.5](https://img.shields.io/badge/iOS-9.3.5-blue)
![Objective-C](https://img.shields.io/badge/language-Objective--C-orange)
![Home Assistant](https://img.shields.io/badge/Home%20Assistant-REST%20API-41BDF5)
![Jellyfin](https://img.shields.io/badge/Jellyfin-remote%20control-AA5CC3)

## About this fork

Jeeves (JeevesPad) is a hard fork of [HomeButler](https://github.com/markcipolla/HomeButler) by [Mark Cipolla](https://github.com/markcipolla), which laid the foundation: the native dashboard, rooms, weather, entity cards and Home Assistant integration. JeevesPad has since gone its own way and is developed independently; changes aren't merged back upstream. Highlights of the fork:

- Renamed to Jeeves, with a new icon, bundle ID and settings migration from HomeButler
- Jellyfin in place of Plex
- Home Assistant-style card interactions (tap to toggle, long-press for a more-info screen)
- Light color, color temperature and effect controls, on cards and in more-info
- Card renaming and sizing per dashboard
- Builds against the iOS 9.3 SDK, plus fixes for iOS 9-specific crashes

If you're coming from HomeButler, see [Upgrading from HomeButler](#upgrading-from-homebutler).

## Features

- **Home dashboard**: Weather (current conditions and 6-day forecast) alongside your chosen entity cards
- **Rooms**: Group entities into rooms, each with its own dashboard
- **Entity cards**: Tap to toggle, long-press for more options, drag to reorder — just like Home Assistant
- **Card customization**: Rename cards and choose their size (X-Small, Small, Wide, Tall, Large) per dashboard
- **Light controls**: Brightness, color, color temperature and effects — on the card itself when there's room, and on the more-info screen
- **More-info screen**: Full controls and attributes for any entity, including climate, vacuums, numbers and selects
- **Home Assistant dashboards**: Show your Lovelace dashboards, rebuilt natively with interactive Jeeves cards
- **Jellyfin**: Browse your libraries and play to (and remote-control) any Jellyfin client
- **Battery reporting**: Reports battery level to Home Assistant, e.g. to drive a smart plug that keeps the iPad's battery healthy
- **Fleets**: iPads running Jeeves find each other on the network and share settings; `deploy_fleet.sh` updates them all at once
- **Home Assistant app and integration**: Manage every wall panel from Home Assistant, edit their dashboards, update them and set up new iPads; each panel becomes a Home Assistant device
- **Presence**: Register household phones with Home Assistant so [Bermuda](https://github.com/agittins/bermuda) can track which room they're in
- **Idle mode**: Returns to Home after a few minutes without a touch, then dims the screen (without turning it off) until the next touch — or movement in front of the camera
- **Dark theme**: Designed for always-on displays

## Requirements

- A jailbroken iOS device running iOS 9 (developed and tested on iOS 9.3.5; minimum iOS 9.0)
- A Home Assistant instance reachable from the device, and a long-lived access token
- To build: [Theos](https://theos.dev/docs/installation) with the iPhoneOS 9.3 SDK, and `ldid`
- To deploy with `deploy.sh`: SSH on the device and `sshpass` on your computer
- Optional: a Jellyfin server (10.9 or newer) for the Jellyfin features

## Installation

### Build

1. Clone the repository:
   ```bash
   git clone https://github.com/JonnyFunFun/JeevesPad.git
   cd JeevesPad
   ```

2. Build with Theos. The `Makefile` expects Theos at `~/dev/theos`; point it elsewhere with `THEOS=`:
   ```bash
   make clean && make package FINALPACKAGE=1             # .deb in packages/
   make clean && make package THEOS=/opt/theos           # with Theos elsewhere
   ./build_ipa.sh                                         # Jeeves.ipa
   ```

### Deploy

```bash
IPAD_IP=192.168.1.xxx ./deploy.sh
```

`deploy.sh` builds the app, copies it to `/Applications` on the device over SSH, refreshes the home screen and launches it. It tries the default root password `alpine` first and prompts for yours if that's rejected (or set `IPAD_PASS`). If the device still has the old HomeButler app, the script removes it.

### Deploying to a fleet

```bash
./deploy_fleet.sh                    # every iPad running Jeeves on the network
./deploy_fleet.sh -f ipads.txt       # plus the iPads listed in a file (one per line)
./deploy_fleet.sh -n 10.0.0.20 10.0.0.21   # only these iPads, no discovery
```

`deploy_fleet.sh` finds iPads with Bonjour — every running copy of Jeeves advertises itself — using `avahi-browse` on Linux (`avahi-utils`) or `dns-sd` on macOS. iPads where Jeeves isn't running can be listed with `-f FILE`, `IPADS="..."` or as arguments. It builds once, then installs on each iPad in turn and prints a summary. The root password is checked once (`IPAD_PASS`, default `alpine`, prompting if that's rejected) and the same password is used for every iPad. Run `./deploy_fleet.sh -h` for all options.

### Upgrading from HomeButler

Jeeves is a separate app as far as iOS is concerned (new bundle ID), so:

- On first launch Jeeves copies HomeButler's settings — Home Assistant connection, rooms, card order and Jellyfin sign-in — and then deletes the old settings.
- **Battery reporting uses a new webhook ID** (see [Battery Reporting](#battery-reporting-smart-plug-automation)); update the `webhook_id` in your Home Assistant automation.
- Plex support has been replaced by Jellyfin; sign in again under Settings → Jellyfin.

### Getting a Home Assistant token

1. Open the Home Assistant web interface
2. Click your profile (bottom left), then the **Security** tab
3. Under "Long-lived access tokens", click **Create token**
4. Copy the token — you'll paste it into Jeeves

## Usage

### First launch

1. Enter your Home Assistant URL (e.g. `http://192.168.1.100:8123`)
2. Enter your long-lived access token
3. Tap **Test Connection** to check it, then **Save & Continue**

### Navigation

The bar along the bottom holds:

- **Home** — the Home dashboard
- **Room tiles** — one per room (scroll sideways; long-press and drag to reorder)
- **Settings** (gear)
- **Jellyfin** — shown when Jellyfin is enabled in Settings
- **+** — create a room

### Home dashboard

- The weather column shows the first `weather.*` entity by default. To customize it — for example to use a personal weather station's sensors — long-press the weather column or go to **Settings → Customize Home Weather**:
  - **Weather entity**: Automatic (first `weather.*`), a specific one, or **None**. A weather entity provides the condition, icon and 6-day forecast; with None, the conditions card fills the column
  - **Temperature**: from the weather entity, or any sensor (e.g. your station's outdoor temperature)
  - **Readings**: any sensors to show as tiles on the weather card — humidity, wind speed and gusts, wind direction (shown as a compass point), rain, pressure, UV… Drag to reorder; tap a tile on Home for its details
- Tap the **pencil** to choose which entities appear (up to 10)

### Rooms

- Tap **+** to create a room and pick its entities
- Select a room tile to see its dashboard; tap the **pencil** to edit the room

### When idle

Jeeves is built to live on the wall, so it tidies up after itself. Configure this under **Settings → When Idle**:

- **Return to Home after** (default 3 minutes; or Never): with no touches for this long, any open screen closes and the Home dashboard is shown
- **Dim screen when idle** (default on): after twice that time, the screen fades to 10% brightness. It stays on — while this is enabled, iOS Auto-Lock is held off — and the next touch restores full brightness. The touch that wakes the screen doesn't press anything
- **Wake on motion (front camera)** (default off): iPads have no proximity sensor, so Jeeves can watch the front camera for movement while the screen is dimmed and brighten when someone walks by. The camera runs only while dimmed, at a very low resolution and frame rate; images are analyzed on the device and never stored or sent. Turning it on asks for camera permission

Your original brightness is restored when Jeeves leaves the foreground, or on the next launch if it was closed while dimmed.

### Working with cards

The same gestures work on every dashboard:

| Gesture | Action |
|---------|--------|
| Tap | Default action (see below) |
| Long-press, then release | Open the more-info screen |
| Long-press, then drag | Reorder; drop on 🗑 to remove from the dashboard |
| Drag up/down (room cards) | Set a dimmable light's brightness (when the room fits on screen; in rooms that scroll, and on Home Assistant dashboards, vertical drags scroll and cards show a brightness slider instead) |

What a tap does depends on the entity, following Home Assistant's defaults:

| Entity | Tap |
|--------|-----|
| `light`, `switch`, `input_boolean`, `fan` | Toggle on/off |
| `script` | Run |
| `button` | Press |
| `sensor`, `binary_sensor`, `climate`, `vacuum`, `number`, `select` | Open more-info |

On room cards, a tap toggles (`turn_on`/`turn_off`) anything that isn't a sensor, script or button.

### More-info screen

Long-press a card and release without dragging to open it. It shows the entity's state, when it last changed and all of its attributes, refreshing every couple of seconds, plus controls for its type:

| Entity | Controls |
|--------|----------|
| Lights | Power, brightness, color (presets plus hue/saturation), color temperature, effect |
| Switches, input booleans, fans | Power |
| Scripts / buttons | Run / Press |
| Vacuums | Start, Pause, Dock |
| Climate | Target temperature, HVAC mode |
| Numbers | Step the value within its min/max |
| Selects | Choose an option |

Only the controls an entity actually supports are shown (for lights, based on `supported_color_modes` and `effect_list`).

### Customizing cards

The more-info screen's **Card** section (shown when opened from a card) lets you:

- **Rename the card** — leave the name empty to use the Home Assistant name
- **Resize the card** — X-Small (1×½, half the height of Small), Small (1×1), Wide (2×1), Tall (1×2) or Large (2×2). Two X-Small cards stack in the space of one Small card; X-Small cards show the name, state and effect button on a single row

Customizations apply to that card on that dashboard only and are stored on the device; nothing is renamed in Home Assistant. Cards fill the grid in order, each taking the first space it fits, so drag cards to rearrange the layout.

### Light controls on cards

When a light's card has room, its controls appear directly on the card: a brightness slider (Home cards — room cards use the vertical drag instead), color swatches and a color temperature slider. Bigger cards fit more of them.

Lights with effects always show an **effect** button (✨) on the card's bottom row, right-aligned beside the on/off status, whatever the card's size.

## Fleets: Sharing Settings Between iPads

iPads running Jeeves on the same network discover each other (Bonjour) and can share their settings, so you only set up one. Open **Settings → Fleet**:

1. Turn on **Fleet sync** and enter a **fleet code** — the same code on every iPad
2. Other iPads running Jeeves appear in the list
3. Tap an iPad to **Send My Settings** to it or **Copy Its Settings Here**, or use **Send My Settings to All iPads**

The receiving iPad applies the settings straight away and shows a brief notice.

| Shared | Kept per iPad |
|--------|---------------|
| Home Assistant URL and token, battery reporting on/off | Battery webhook ID |
| Rooms, Home cards, card names and sizes | Jellyfin sign-in and playback target |
| Home weather settings | Wake on motion |
| Idle timeout and dimming | Last-viewed dashboard and screen brightness |
| Jellyfin on/off and server | |

Settings include your Home Assistant token, so everything sent between iPads is encrypted and authenticated with the fleet code (AES-256 and HMAC-SHA256, with a key derived by PBKDF2). iPads without the same code can neither change this iPad's settings nor read them. Requests are rejected if the two iPads' clocks differ by more than 10 minutes.

## Home Assistant App and Integration

Manage every wallPad (a wall-mounted iPad running Jeeves) from Home Assistant. This repository holds two pieces:

- **JeevesPad Manager**, a Home Assistant app (formerly called an add-on), in [`jeevespad/`](jeevespad). It adds a **wallPads** page to the sidebar for status, settings, dashboard editing (Home cards, rooms, card names and sizes), copying settings between wallPads, remote commands, app updates, SSH maintenance, and setting up newly jailbroken iPads.
- **JeevesPad**, an integration you can install with HACS, in [`custom_components/jeevespad/`](custom_components/jeevespad). It makes each wallPad a Home Assistant device: battery, charging, screen dimmed, idle time, a screen brightness slider for automations, and identify / go Home / wake / reload / restart buttons.

HACS only installs integrations (and dashboard cards, themes and the like), not apps, so they're installed separately:

1. **App:** Settings → Apps → App store → ⋮ → Repositories, add `https://github.com/JonnyFunFun/JeevesPad`, then install **JeevesPad Manager**. See its [documentation](jeevespad/DOCS.md).
2. **Integration:** HACS → ⋮ → Custom repositories, add `https://github.com/JonnyFunFun/JeevesPad` as an *Integration*, install **JeevesPad** and restart Home Assistant. Home Assistant then offers to add the wallPads found by the app.

The app reaches wallPads two ways: through Jeeves's fleet protocol (the same encrypted connection iPads use to share settings, so wallPads need fleet sync on and the app's fleet code; **Enrol in this fleet** sets that up over SSH), and over SSH for installing, updating, restarting and rebooting. It installs the published `Jeeves.ipa` from this repository's GitHub releases, or your own build from `build_ipa.sh` if you upload one (yours takes precedence until you remove it); it can't build Jeeves itself.

## Presence: Tracking Phones with Bermuda

[Bermuda](https://github.com/agittins/bermuda) tracks Bluetooth devices room by room using your Bluetooth proxies. Phones change their Bluetooth address every few minutes, so Home Assistant needs each phone's Identity Resolving Key (IRK) to recognise it; Bermuda picks up every phone registered with Home Assistant's **Private BLE Device** integration. **Settings → Presence** does that registration from the panel:

- **Pair a Phone with This Panel** (easiest): enter a name and tap **Start Pairing**. The panel shows up as a Bluetooth accessory called "Jeeves Pairing". On an iPhone, connect to it with a Bluetooth app such as LightBlue or nRF Connect and read its characteristic, then tap **Pair**; on Android, pair from Settings → Bluetooth → Pair new device. The phone hands over its key while pairing; Jeeves reads it from the iPad's keychain and registers the phone. Afterwards the phone can forget "Jeeves Pairing" and tracking keeps working. (If something goes wrong, `/var/mobile/Library/Logs/Jeeves-pairing.log` describes what Jeeves found, without key values.)
- **Add a Phone with Its Bluetooth Key**: enter a name and the phone's key (hex, with or without an `irk:` prefix, or base64 as a Mac's Keychain shows it). Keep the phone unlocked and near a Bluetooth proxy: Home Assistant only accepts a key for a phone it can currently see. Jeeves names the device in Home Assistant, and Bermuda uses that name.
- **Rename** or **Stop Tracking** registered phones. The list is stored in Home Assistant, so every panel shows the same phones.
- **Android phones**: many stop advertising when the screen is off, so the Home Assistant app's **BLE Transmitter** sensor (an iBeacon Bermuda tracks directly) works better; the screen explains how to turn it on.

A phone only shares its key with devices it pairs with. Ways to get it: a Mac the iPhone is paired with (Keychain Access, "Remote IRK"), an ESP32 running [ESPresense](https://espresense.com) or [IRK Capture](https://github.com/DerekSeaman/irk-capture), or a Linux computer the phone is paired with (`/var/lib/bluetooth/<adapter>/<phone>/info`). See Bermuda's [guide to getting IRKs](https://github.com/agittins/bermuda/wiki/How-to-get-the-IRK-(Identity-Resolving-Keys)-for-iOS,-Android-etc).

Pairing needs the keychain permission that `deploy.sh`, `deploy_fleet.sh` and `build_ipa.sh` sign Jeeves with (see Security Notes); an IPA re-signed by other tools can still add phones by key.

Registering phones uses Home Assistant's admin-only configuration API, so Jeeves's access token must belong to an administrator.

## Home Assistant Dashboards

Tap **Dashboards** in the bottom bar to show one of your Home Assistant (Lovelace) dashboards. Home Assistant's own dashboard UI needs iOS 12 or newer, so instead Jeeves fetches the dashboard's configuration and rebuilds it with native Jeeves cards, scaled to the screen. Cards work like everywhere else in Jeeves: tap to toggle, long-press for more-info, drag for brightness, inline light controls.

- **Dashboards** (top right) switches between your dashboards; views appear as tabs along the top
- Uses the Home Assistant connection from Settings — nothing else to set up
- Pull down to reload the dashboard after changing it in Home Assistant

How cards are translated:

| Lovelace card | In Jeeves |
|---------------|-----------|
| `tile`, `button`, `light`, `entity`, `sensor`, `thermostat`, and other cards for a single entity | Entity card (using the card's `name`, if set) |
| `entities`, `glance` | Heading plus a card per entity |
| `grid`, `vertical-stack`, `horizontal-stack` | Their cards, in order (titles become headings) |
| `heading`, `markdown` | Heading / text (templates aren't evaluated) |
| `conditional` | Its card, always shown |
| Anything else (`custom:` cards, graphs, maps, pictures, …) | A placeholder naming the card |

Dashboards that Home Assistant generates automatically (the default Overview, until you choose "Take control" in Home Assistant) have no configuration to fetch, so Jeeves asks you to take control or pick another dashboard. Both classic and "sections" views are supported.

## Jellyfin

Jeeves works as a Jellyfin remote: browse on the iPad, play on your TV or other Jellyfin client.

### Setup

1. **Settings → Jellyfin**: turn on **Enable Jellyfin** and enter the server URL (e.g. `http://192.168.1.x:8096`)
2. Enter your Jellyfin username and password and tap **Sign In** (only the resulting access token is stored, never the password)
3. Start the Jellyfin app you want to play to, then tap **Pick Target Client** and choose it. Only clients that support remote control and were active in the last ~15 minutes are listed.
4. **Save & Continue** — a **Jellyfin** button appears in the bottom bar

### Using it

- Rows for **Continue Watching** (in-progress items and next-up episodes), **Recently Added** and each library; tap a row title to see the whole library
- Search across movies, shows, episodes and music
- **Play** / **Resume** sends playback to the target client
- The now-playing screen offers play/pause, stop, previous/next, seeking, volume, and audio/subtitle track selection

## Battery Reporting (Smart Plug Automation)

Jeeves can report battery level to Home Assistant every 60 seconds, allowing you to automate charging with a smart plug to preserve battery health.

### Setup

1. **In Jeeves**: Go to Settings and enable "Battery Reporting". Note the **Webhook ID** shown below the toggle (e.g. `jeeves_3fa9c2d1_battery`). Each install gets its own ID, so several devices can report to the same Home Assistant; create one webhook automation per device.

2. **In Home Assistant**: Create helper entities via Settings → Devices & Services → Helpers:
   - **Number** helper: Name `iPad Battery Level`, min 0, max 100, unit `%`
   - **Text** helper: Name `iPad Battery State`

3. **Create the webhook automation** (Settings → Automations → + Create Automation → Edit in YAML):

```yaml
alias: Jeeves Battery Webhook
description: ""
mode: single
triggers:
  - trigger: webhook
    webhook_id: jeeves_3fa9c2d1_battery  # use the Webhook ID from Jeeves' Settings
    local_only: true
conditions: []
actions:
  - action: input_number.set_value
    target:
      entity_id: input_number.ipad_battery_level
    data:
      value: "{{ trigger.json.battery_level }}"
  - action: input_text.set_value
    target:
      entity_id: input_text.ipad_battery_state
    data:
      value: "{{ trigger.json.battery_state }}"
```

4. **Create smart plug automations**:

**Stop charging at 80%:**
```yaml
alias: iPad Stop Charging at 80%
description: ""
mode: single
triggers:
  - trigger: numeric_state
    entity_id: input_number.ipad_battery_level
    above: 80
conditions:
  - condition: state
    entity_id: input_text.ipad_battery_state
    state: "charging"
actions:
  - action: switch.turn_off
    entity_id: switch.ipad_charger
```

**Start charging at 20%:**
```yaml
alias: iPad Start Charging at 20%
description: ""
mode: single
triggers:
  - trigger: numeric_state
    entity_id: input_number.ipad_battery_level
    below: 20
conditions: []
actions:
  - action: switch.turn_on
    entity_id: switch.ipad_charger
```

### Webhook payload

The app sends this JSON to `{your_ha_url}/api/webhook/jeeves_<identifier>_battery`:

```json
{
  "battery_level": 75,
  "battery_state": "charging",
  "device_name": "iPad",
  "device_model": "iPad4,1",
  "ios_version": "9.3.5",
  "app": "Jeeves",
  "instance_id": "3fa9c2d1"
}
```

`battery_state` can be: `charging`, `unplugged`, `full`, or `unknown`.

## API Integration

Jeeves talks to Home Assistant's REST API with Bearer token authentication:

| Endpoint | Purpose |
|----------|---------|
| `GET /api/states` | Fetch all entities (every second while the dashboard is open) |
| `GET /api/states/{entity_id}` | Refresh one entity (more-info screen) |
| WebSocket `/api/websocket`: `lovelace/dashboards/list`, `lovelace/config` | Home Assistant dashboards (not available over REST) |
| `POST /api/services/{domain}/{service}` | Control entities |
| `POST /api/services/weather/get_forecasts` | Weather forecast |
| `POST /api/webhook/jeeves_<id>_battery` | Battery reporting |
| `GET/DELETE /api/config/config_entries/entry`, `POST /api/config/config_entries/flow` | Presence: list, remove and register phones (Private BLE Device; admin token) |
| WebSocket: `config_entries/update`, `config/device_registry/list`, `config/device_registry/update` | Presence: name registered phones |

Jellyfin uses the server's REST API (`/Users/AuthenticateByName`, `/UserViews`, `/Items`, `/Sessions`, …), controlling playback through the Sessions API.

## Project Structure

```
Jeeves/
├── API/
│   ├── HAAPIClient            # Home Assistant REST API client
│   ├── HAWebSocketClient      # Home Assistant WebSocket commands (dashboards)
│   ├── JeevesWebSocket        # Minimal WebSocket client (iOS 9 has none)
│   ├── JeevesBatteryReporter  # Battery webhook reporting
│   └── JeevesJellyfinClient   # Jellyfin API client
├── Models/
│   ├── HAEntity               # Entity model and capability helpers
│   ├── JeevesRoom             # Rooms and their persistence
│   ├── JeevesCardSettings     # Per-dashboard card names/sizes, grid packing
│   ├── JeevesLovelaceDashboard # Lovelace config → native dashboard items
│   └── JeevesJellyfin*        # Jellyfin items, sessions, streams, targets
├── ViewControllers/
│   ├── JeevesDashboardViewController       # Home and room dashboards
│   ├── JeevesEntityMoreInfoViewController  # More-info screen
│   ├── JeevesLovelaceViewController        # Home Assistant dashboards
│   ├── JeevesAddRoomViewController         # Room editor
│   ├── SettingsViewController              # Settings
│   └── JeevesJellyfin*                     # Jellyfin browsing and remote
├── Views/
│   ├── JeevesLightToggleCell   # Room entity card
│   ├── JeevesLightControlsView # Brightness/color/temperature/effect controls
│   ├── JeevesGridLayout        # Room card grid with multi-cell cards
│   └── JeevesJellyfin*         # Jellyfin cells, rows, now-playing pill
├── Helpers/                    # Pull-to-refresh and polling for Jellyfin screens
└── Theme/
    └── JeevesThemeManager      # Colors and styling
Resources/                      # App bundle resources (Info.plist, icons)
tools/                          # App icon source (AppIcon.svg) and render script
```

## Development

See [CLAUDE.md](CLAUDE.md) for development documentation: build systems (Theos and Xcode must be kept in sync), architecture, key files, and logging/crash-log locations on the device.

The app icon is drawn in `tools/AppIcon.svg`; after editing it, run `tools/render_icons.sh` (needs `rsvg-convert` and ImageMagick) to regenerate every icon size.

## Security Notes

- The Home Assistant token and Jellyfin access token are stored in the app's preferences (`NSUserDefaults`); the Jellyfin password is not stored
- To read paired phones' Bluetooth keys, Jeeves is signed with access to the iPad's `apple` keychain group (`entitlements.plist`), where iOS's Bluetooth service keeps them. That group also holds other Apple services' items; Jeeves only reads `MobileBluetooth` items, and only while pairing
- `NSAllowsArbitraryLoads` is enabled so the app can reach servers over plain HTTP on your network
- Both API clients accept any TLS certificate, so self-signed certificates work — but this also means HTTPS connections aren't protected against interception. Prefer using Jeeves on a trusted network.

## Troubleshooting

**Connection fails:**
- Check the Home Assistant URL is reachable from the device (try it in Safari)
- Check the access token is valid
- Try the IP address instead of the hostname

**Entities don't appear:**
- The dashboard refreshes every second; if nothing appears, check Home Assistant is running and the connection overlay isn't showing
- The entity picker lists lights, switches, sensors, binary sensors, scripts, input booleans, buttons, fans, vacuums, climate, numbers and selects

**No Jellyfin clients when picking a target:**
- Start the client first and make sure it supports remote control (e.g. Jellyfin Media Player, Jellyfin for Android TV, or the web client)

**Linker errors building with the iPhoneOS 9.3 SDK** (e.g. `file not found: libcache.dylib`, or undefined `_memset` / `__Unwind_Resume`):
- The `.tbd` library stubs in the commonly distributed iPhoneOS 9.3 SDK are incomplete: `libSystem.tbd` re-exports its sub-libraries by bare name, `liblaunch` has no stub, `libsystem_platform.tbd` omits `memset`/`memcpy`/`bzero` and friends, and `libunwind.tbd` lacks the arm64 unwinder symbols. Patch those stubs in your SDK copy.

## License

MIT License - See [LICENSE](LICENSE) for details.

## Acknowledgments

- [Mark Cipolla](https://github.com/markcipolla), who created [HomeButler](https://github.com/markcipolla/HomeButler), the project Jeeves is forked from
- Built for the Home Assistant and Jellyfin communities
- Designed for legacy iOS devices that deserve smart home control
- Named for Reginald Jeeves, created by P.G. Wodehouse
