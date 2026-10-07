# Jeeves

A native iOS app for controlling Home Assistant, designed for jailbroken devices running iOS 9 — so an old iPad can live on as a wall-mounted smart home panel. Named after P.G. Wodehouse's gentleman's personal gentleman, who always knew just what was wanted.

**Repository:** [github.com/JonnyFunFun/JeevesPad](https://github.com/JonnyFunFun/JeevesPad) · [Issues](https://github.com/JonnyFunFun/JeevesPad/issues)

https://github.com/user-attachments/assets/7f0fc34f-93f5-4bdb-b7bc-e2405993784f

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
- **Jellyfin**: Browse your libraries and play to (and remote-control) any Jellyfin client
- **Battery reporting**: Reports battery level to Home Assistant, e.g. to drive a smart plug that keeps the iPad's battery healthy
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

- Weather comes from the first `weather.*` entity in Home Assistant
- Tap the **pencil** to choose which entities appear (up to 10)

### Rooms

- Tap **+** to create a room and pick its entities
- Select a room tile to see its dashboard; tap the **pencil** to edit the room

### Working with cards

The same gestures work on every dashboard:

| Gesture | Action |
|---------|--------|
| Tap | Default action (see below) |
| Long-press, then release | Open the more-info screen |
| Long-press, then drag | Reorder; drop on 🗑 to remove from the dashboard |
| Drag up/down (room cards) | Set a light's brightness |

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
| `POST /api/services/{domain}/{service}` | Control entities |
| `POST /api/services/weather/get_forecasts` | Weather forecast |
| `POST /api/webhook/jeeves_<id>_battery` | Battery reporting |

Jellyfin uses the server's REST API (`/Users/AuthenticateByName`, `/UserViews`, `/Items`, `/Sessions`, …), controlling playback through the Sessions API.

## Project Structure

```
Jeeves/
├── API/
│   ├── HAAPIClient            # Home Assistant REST API client
│   ├── JeevesBatteryReporter  # Battery webhook reporting
│   └── JeevesJellyfinClient   # Jellyfin API client
├── Models/
│   ├── HAEntity               # Entity model and capability helpers
│   ├── JeevesRoom             # Rooms and their persistence
│   ├── JeevesCardSettings     # Per-dashboard card names/sizes, grid packing
│   └── JeevesJellyfin*        # Jellyfin items, sessions, streams, targets
├── ViewControllers/
│   ├── JeevesDashboardViewController       # Home and room dashboards
│   ├── JeevesEntityMoreInfoViewController  # More-info screen
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
