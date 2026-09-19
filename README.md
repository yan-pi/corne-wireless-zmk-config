# Corne wireless ZMK battery tools

ZMK configuration and a macOS battery utility for a wireless Corne using two
nice!nano v2 controllers.

## Quick start

```sh
# Build and query the keyboard
cd tools/corne-battery
swift run --configuration release corne-battery status --name Corne

# Run the low-battery monitor in the foreground
swift run --configuration release corne-battery monitor --name Corne
```

For normal use, install the monitor as a macOS LaunchAgent so no terminal stays
open:

```sh
CORNE_DEVICE_NAME=Corne bash tools/corne-battery/scripts/install-monitor.sh
```

## Documentation

- [Documentation index](docs/README.md)
- [Firmware, roles, build and flashing](docs/firmware.md)
- [Battery model and calibration](docs/battery.md)
- [CLI usage](docs/cli.md)
- [Background monitor and notifications](docs/monitor.md)
- [Troubleshooting](docs/troubleshooting.md)
- [Development and validation](docs/development.md)

## Important hardware limitation

Each half has two identical 1-cell LiPo batteries wired in parallel. ZMK sees
one combined 1S pack per half, so the maximum supported resolution is:

- `left`: combined left-half pack;
- `right`: combined right-half pack.

Four independent battery values require a separate ADC or fuel-gauge channel
for every cell. The current firmware reports estimated state of charge, not
true health metrics such as cycle count, capacity degradation, temperature, or
internal resistance.
