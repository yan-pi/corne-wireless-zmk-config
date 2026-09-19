# Background monitor and notifications

The monitor is a long-running process that reads both battery values once per
minute. It sends a macOS notification when a battery crosses from above 15% to
15% or below.

## Foreground test

Run this first to verify Bluetooth access and device selection:

```sh
cd ~/www/personal/corne-wireless-zmk-config/tools/corne-battery
swift run --configuration release corne-battery monitor --name Corne
```

Stop it with `Ctrl-C`.

The monitor does not repeat an alert while a pack remains low. It re-arms when
that pack recovers to 20% or higher. If the monitor starts while a pack is
already below 15%, it records the value but waits for a new downward crossing.

Notifications are sent through `/usr/bin/osascript`, which works from a CLI and
from a LaunchAgent without the `UNUserNotificationCenter` bundle crash.

## Install as a LaunchAgent

```sh
cd ~/www/personal/corne-wireless-zmk-config/tools/corne-battery
CORNE_DEVICE_NAME=Corne bash scripts/install-monitor.sh
```

The installer:

1. builds `.build/release/corne-battery` if needed;
2. creates `~/Library/LaunchAgents/sh.indianboy.corne-battery.plist`;
3. starts it in the user's GUI session;
4. configures `KeepAlive` and `RunAtLoad`.

No terminal needs to stay open. The monitor polls every 60 seconds.

Verify the agent:

```sh
launchctl print gui/$(id -u)/sh.indianboy.corne-battery
```

Logs are written to:

```text
~/Library/Logs/corne-battery.log
~/Library/Logs/corne-battery.error.log
```

Remove the agent:

```sh
bash scripts/uninstall-monitor.sh
```

## macOS notification permissions

The notification sender is determined by macOS because delivery uses
`osascript`. If alerts are not visible, inspect **System Settings >
Notifications** for the sender shown after the first notification and enable
alerts and sounds. Run the foreground monitor once so macOS can associate the
sender with the logged-in user session.

## LaunchAgent caveats

The agent requires the user to be logged in to a graphical macOS session. It is
not a system daemon and should not be installed as root. It also requires the
Corne to be paired with the Mac and the left central to be awake/available.

If the right side is unavailable, the monitor logs the read error or reports
that half as unavailable; it does not fabricate a value.
