# JeevesPad Manager

Open **wallPads** in the sidebar to manage your Jeeves wall panels.

## How it reaches wallPads

- **Through Jeeves itself.** Status, settings, dashboards and commands use the same encrypted fleet connection iPads use to share settings with each other. The wallPad must be running Jeeves, be on the same network (it's found with Bonjour), have **fleet sync** turned on, and use the same **fleet code** as this app. Jeeves 1.0 builds from before this app existed can share settings but can't report status or take commands; update them.
- **Over SSH.** Installing and updating Jeeves, enrolling a wallPad into the fleet, restarting Jeeves, rebooting and reading logs log in as root, so they work even when Jeeves isn't running.

## First steps

1. Start the app and open **wallPads**. Any iPad running Jeeves on your network appears.
2. Open the **Fleet** tab. The app made a fleet code (or uses the one in its configuration).
3. For each existing wallPad, open **Maintenance → Enrol in this fleet**. Jeeves restarts with fleet sync on and the fleet code. Or enter the code yourself in Settings → Fleet on the iPad.
4. On the **App package** tab, download the published release, or upload your own `Jeeves.ipa` (made with `build_ipa.sh`), so you can update wallPads and set up new ones.

## App packages

The **App package** tab holds up to two copies of Jeeves:

- **Your package**: a `Jeeves.ipa` you upload, such as your own build from `build_ipa.sh`. While it's there, it's what gets installed, and downloading a newer published release doesn't replace it.
- **Published release**: downloaded from the JeevesPad releases on GitHub (or the address in the configuration, or one you enter). It's used when you haven't uploaded a package, and is downloaded automatically the first time it's needed.

**Remove my package** goes back to the published release. Neither changes wallPads by itself: choose wallPads under **Update wallPads** to install the package in use. Packages can't be changed while one is being installed.

## Setting up a new iPad

On the **Set up an iPad** tab, enter the iPad's IP address and root password. Before you start, jailbreak the iPad, install **OpenSSH**, **UIKit Tools** and **Open** from Cydia, and connect it to your network.

Choose what the new wallPad starts with: a copy of another wallPad's settings (Home Assistant connection, dashboards, weather and idle settings), just the Home Assistant address and an access token, or nothing. The app installs Jeeves, saves the settings and fleet code for Jeeves to pick up when it starts, starts it, and waits for it to appear.

## Configuration

| Option | Description |
|--------|-------------|
| Fleet code | The code every wallPad shares. Leave empty to have one generated. |
| Root password | SSH root password of the wallPads (jailbreaks start with `alpine`; please change it). You can enter a different one for a single iPad; it's remembered for that wallPad. |
| Home Assistant URL for wallPads | The address wallPads use to reach Home Assistant, for new iPads. |
| Access token for wallPads | A long-lived access token for new iPads. Use an administrator's token if people will register phones from the panels. |
| Extra wallPad addresses | wallPads to manage over SSH even when Bonjour can't find them. |
| Jeeves app package URL | Where **Download** fetches `Jeeves.ipa` from (default: the latest GitHub release). |

## Security

- The app runs on the host network so it can find wallPads with Bonjour. Its web interface only answers Home Assistant's ingress (so only Home Assistant administrators can use it) and the JeevesPad integration (with an API key it receives through discovery).
- Settings sent to and from wallPads include Home Assistant access tokens. They're encrypted and authenticated with the fleet code, as between iPads.
- SSH host keys are remembered the first time the app connects to a wallPad. If an iPad is restored or re-jailbroken, its key changes and the app refuses to connect until you choose **Forget SSH host key**.
- The root password is stored in the app's configuration, and per-wallPad passwords in its data folder. Both are included in Home Assistant backups.

## The JeevesPad integration

Install **JeevesPad** with HACS (custom repository `https://github.com/JonnyFunFun/JeevesPad`, type *Integration*) and restart Home Assistant. When this app is running, Home Assistant offers to add the wallPads. Each wallPad becomes a device with:

- Battery, charging, screen dimmed, time since last touch, Jeeves running, Home Assistant connection
- Screen brightness (a slider you can use in automations, for example to dim every panel at night)
- Buttons: identify, go to Home, wake screen, reload screen, restart Jeeves
