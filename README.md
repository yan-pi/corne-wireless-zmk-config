# Corne wireless ZMK battery tools

This repository contains the ZMK configuration and a macOS battery utility for a
wireless Corne running on two nice!nano v2 controllers.

## What the hardware can report

Each half has **two identical 1-cell (1S) LiPo batteries in parallel**. The
parallel pair has one voltage and one battery input, so ZMK sees it as one pack.
The maximum useful resolution with the current wiring is:

- `left`: the left half's combined pack;
- `right`: the right half's combined pack.

It is not possible to report four independent percentages without a separate
fuel gauge/ADC channel for every battery. Parallel batteries increase capacity,
not voltage; do not average or add two percentages in the firmware.

ZMK reports an estimated state of charge from voltage. The current firmware does
not report cycle count, original/full capacity, temperature, internal
resistance, or degradation health. The CLI therefore calls these values
**status**, and reports true health as unavailable rather than inventing it.

## Firmware configuration

`config/corne.conf` already enables the required path and explicitly selects
ZMK v0.3's 1S lithium voltage mapping:

```text
CONFIG_BT_BAS=y
CONFIG_ZMK_BATTERY_REPORTING=y
CONFIG_ZMK_BATTERY_REPORTING_FETCH_MODE_LITHIUM_VOLTAGE=y
CONFIG_ZMK_BATTERY_REPORT_INTERVAL=60
CONFIG_ZMK_SPLIT_BLE_CENTRAL_BATTERY_LEVEL_FETCHING=y
CONFIG_ZMK_SPLIT_BLE_CENTRAL_BATTERY_LEVEL_PROXY=y
```

The left half is the split central and the right half is the BLE peripheral.
Only the left central communicates with the computer as a keyboard. The right
half cannot become a standalone keyboard just by plugging its USB cable into a
computer; that cable is useful for charging/debugging/flashing, while normal
split operation requires the right half to connect wirelessly to the left.

When a computer connects to the left central over BLE, it should expose its own
standard Battery Service and an auxiliary Battery Service for the right half.
macOS may display only one of multiple BAS instances; the CLI enumerates them
directly.

Build the normal production firmware with the existing GitHub Actions workflow.
Flash the left and right artifacts to the corresponding halves. After changing
BLE services, use the `settings_reset` artifact only when necessary, forget the
old Corne pairing in macOS, and pair again so CoreBluetooth does not retain an
old GATT cache.

The host-side path has been exercised against a paired Corne: CoreBluetooth
found two Battery Services and two Battery Level characteristics. The CLI
uses ZMK's CPF `auxiliary` descriptor instead of relying on service order. The
current flash returned `0%` for the main/left reading and `100%` for the
auxiliary/right reading, so the split link works and the remaining issue is the
left firmware sensor/percentage validation. Run the debug build below
and compare its millivolt value to a multimeter before changing the mapping.

### Optional battery debug build

The opt-in `battery-debug` Zephyr snippet enables USB logging, debug logging, and
a 10-second battery report interval. It is intentionally not in the production
matrix because logging increases power use.

When building from a ZMK checkout that has this config repository available:

```sh
west build -s zmk/app -b nice_nano_v2 -S battery-debug \
  -- -DSHIELD=corne_left -DZMK_CONFIG="$PWD/config"
west build -s zmk/app -b nice_nano_v2 -S battery-debug \
  -- -DSHIELD=corne_right -DZMK_CONFIG="$PWD/config"
```

The debug log should include lines like `State of change N from M mv`. If `M`
is wrong, fix the board/sensor wiring or devicetree scaling. If `M` is correct
but `N` is wrong, the pinned ZMK v0.3 mapping is the layer to revisit. The
repository deliberately does not add a guessed custom curve without those
measurements.

Use the generated debug logs to compare the reported millivolts and percentage
with a multimeter. ZMK v0.3's default lithium mapping is approximately linear
from 3450 mV (0%) to 4200 mV (100%). Correct sensor scaling first; only change
the mapping after confirming the sensed voltage is accurate. Do not use a
percentage taken while a cell is under a transient load as a calibration point.

## macOS CLI

The package is at `tools/corne-battery` and uses only Apple CoreBluetooth and
UserNotifications APIs:

```sh
cd tools/corne-battery
swift test
swift build -c release
.build/release/corne-battery devices
.build/release/corne-battery status --name Corne
.build/release/corne-battery status --device <COREBLUETOOTH-UUID> --json
```

`status` connects to the selected keyboard, discovers every `180F` Battery
Service and every `2A19` Battery Level characteristic, then prints both logical
halves. A missing/read-failed half is reported as `unavailable`. BAS does not
carry a sensor timestamp, so `observed` means when this CLI read the value; a
proxy value can still be stale if the right half is asleep or disconnected. The
UUID printed by `devices` is the
CoreBluetooth identifier, which can change after forgetting a pairing.

Example human output:

```text
Corne (A1B2C3D4-...)
  left: 83% [normal]
  right: 76% [normal]
  observed: 2026-01-01T12:00:00Z
  health: unavailable (not reported by ZMK firmware)
```

The JSON schema is stable enough for scripts and includes `health: null`:

```json
{
  "batteries": [
    {"label":"left","percentage":83,"role":"main","status":"normal"},
    {"label":"right","percentage":76,"role":"auxiliary","status":"normal"}
  ],
  "health": null
}
```

If discovery fails:

1. wake both halves and ensure the computer is paired to the **left** central;
2. run `devices` and select an exact `--device` UUID if names are ambiguous;
3. confirm the production firmware contains the split BLE and battery Kconfig options;
4. test typing with only the left connected to the computer; the right should
   be powered and nearby, not separately paired to macOS;
5. reflash the right peripheral and left central from the matching workflow
   commit, then power-cycle both halves;
6. forget/re-pair after a firmware service change;
7. check **System Settings > Privacy & Security > Bluetooth** for permission.

If the left works but the right never participates, this is a split-link or
right-half firmware/power problem, not a CLI problem. The CLI can only report
the right value after the left central has fetched it and exposed the auxiliary
BAS service. Use the battery-debug build and the ZMK logs to check whether the
right peripheral is discovered by the left; a USB connection to the right alone
will not prove that split BLE is working.

## 15% notifications

Run the foreground monitor first to verify permissions and device selection:

```sh
.build/release/corne-battery monitor --name Corne
```

It polls once per minute, reads both halves, and sends a native macOS
notification when a half crosses from above 15% to 15% or below. CLI status is
`normal` above 15%, `low` from 6–15%, and `critical` at 5% or below. It does not
repeat the alert while that half remains low; it re-arms after recovery to 20%
or higher. If the monitor starts while a pack is already below 15%, it records
that state but does not create a surprise notification until the next downward
crossing.

To install it as a user LaunchAgent (not done automatically):

```sh
CORNE_DEVICE_NAME=Corne bash tools/corne-battery/scripts/install-monitor.sh
```

Allow notifications in **System Settings > Notifications**. To remove it:

```sh
bash tools/corne-battery/scripts/uninstall-monitor.sh
```

The monitor is intentionally direct-BLE-only. USB/dongle mode, Linux support,
Apple's built-in battery widget, and genuine fuel-gauge health telemetry are
follow-up work. The stock macOS widget may collapse or omit the auxiliary BAS
instance; the CLI is the reliable per-half view.
