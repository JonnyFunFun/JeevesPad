# Changelog

## 0.1.2

- Fix installing Jeeves (setting up an iPad, and updating wallPads): the app folder on the iPad is now created before the app is copied into it, instead of the copy failing.
- Start and end Guided Access on wallPads, and set the unlock code that ends it at the panel (Fleet tab). Needs a supervised iPad; see the documentation.
- Setting up and updating wallPads installs missing Cydia packages (UIKit Tools, Open).
- Maintenance mode: lock a wallPad behind a full-screen notice (with your own message) from its Maintenance panel or the integration's switch, until you turn it off. At the panel, holding the notice for 5 seconds and entering the unlock code also ends it.
- Searchable entity pickers everywhere an entity is chosen: search by name, entity ID, area, device or type, with the current state shown. Weather, temperature and reading pickers only offer suitable entities.
- The wallPads page uses Home Assistant's colours and follows its light or dark mode (and custom themes).
- Security: the web server is no longer reachable from your network (new **Listen on all addresses** option, off by default, in case the page doesn't load); protection against cross-site requests; strict security headers; request size limits; repeated wrong integration API keys are blocked; wallPad addresses are validated before use with SSH; SSH only uses addresses a wallPad has proved with the fleet code; stricter checks on app packages; fleet codes must be at least 8 characters.
- Bumps iPad app to 1.1 - releases will now include prebuilt iPad binaries; clone, compile, and upload your own for personal customizations.
- Some UI label & translation updates and typo corrections

## 0.1.1

- Fix the dashboard editor's Rooms section, which showed text like "[object HTMLParagraphElement]" instead of the rooms, and a stray "null" in the Maintenance panel.
- Browsers load the new page files after an update instead of keeping old ones.

## 0.1.0

- First release: wallPad status, settings and dashboard editing, copying settings between wallPads, remote commands, SSH maintenance, app updates, and setting up new iPads.
- Upload your own Jeeves.ipa to install instead of the published release; remove it to go back.
