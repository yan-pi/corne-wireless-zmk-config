# Troubleshooting

## Keyboard does not wake after inactivity

The previous configuration enabled `CONFIG_ZMK_SLEEP=y`. Deep sleep disconnects
Bluetooth and requires a valid wakeup source; the split could fail to recover
reliably. The production configuration now sets:

```text
CONFIG_ZMK_SLEEP=n
```

Flash both matching left and right images from the same successful workflow run.
Normal ZMK idle remains enabled and should preserve Bluetooth connectivity.

If the latest firmware still fails to wake:

1. confirm both halves are powered and close together;
2. remove the Corne from macOS Bluetooth settings;
3. clear the active ZMK bond with the keymap's `BT_CLR` binding;
4. pair only the left central again;
5. test the right peripheral without pairing it separately to macOS.

## Left works but right does not

This is a split-link, right firmware, or power problem rather than a CLI problem.
The right cannot operate as a standalone host keyboard. Reflash matching
`corne_left` and `corne_right` images, power-cycle both halves, and keep them
near each other.

The CLI can show the right value only when the left central has fetched it and
exposed the auxiliary BAS service.

## CLI cannot find the Corne

```sh
corne-battery devices
```

Then select the exact UUID:

```sh
corne-battery status --device <UUID> --json
```

Also check:

- Bluetooth is enabled;
- macOS Bluetooth permission is allowed;
- the left central is paired;
- both halves are awake;
- the device name is exactly `Corne` if using `--name`.

After changing the GATT database, forget and re-pair the keyboard so macOS does
not retain a stale CoreBluetooth cache.

## Finder error `-36` while flashing UF2

Finder can fail to copy UF2 files to the nice!nano bootloader volume. Use a
Terminal copy instead:

```sh
ls /Volumes
cp ~/Downloads/settings_reset-nice_nano_v2-zmk.uf2 /Volumes/NICENANO/
sync
diskutil eject /Volumes/NICENANO
```

For normal operation, flash `corne_left` to the left and `corne_right` to the
right. `settings_reset` is only a recovery image and must be followed by the
matching production image.

Use a data-capable cable and avoid hubs while flashing.

## Monitor crashes with `bundleProxyForCurrentProcess`

This was caused by using `UNUserNotificationCenter` from a SwiftPM executable.
The monitor now uses `/usr/bin/osascript` and must be rebuilt:

```sh
swift build --configuration release
```

If a LaunchAgent still uses an old binary, reinstall it:

```sh
bash tools/corne-battery/scripts/uninstall-monitor.sh
CORNE_DEVICE_NAME=Corne bash tools/corne-battery/scripts/install-monitor.sh
```

## Monitor runs but no notification appears

- verify the monitor is running with `launchctl print`;
- inspect `~/Library/Logs/corne-battery.error.log`;
- enable notifications for the sender displayed by macOS;
- remember that alerts trigger only when crossing from above 15% to 15% or below;
- a monitor started while already below 15% does not alert immediately;
- recover above 20% to re-arm the next alert.

## Percentage appears wrong

Use the optional debug image and compare the logged millivolts with a multimeter.
Fix sensor/wiring/scaling before changing the voltage-to-percentage mapping. A
parallel pair still has the voltage range of one 1S LiPo pack.

Do not interpret percentage as battery health. Cycle count and degradation
require a fuel gauge or additional firmware/hardware support.
