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
```

Or edit `deploy.sh` and set `IPAD_IP` directly.

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
- **Entity Cards**: Tap to toggle, vertical drag for brightness (dimmable lights)
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
