# Corne battery documentation

This directory documents the firmware, host CLI, notification service, battery
wiring, and recovery procedures for this Corne configuration.

## Choose a task

| Task | Document |
| --- | --- |
| Understand left/master and right/peripheral roles | [Firmware](firmware.md) |
| Flash production or debug firmware | [Firmware](firmware.md) |
| Understand the two-parallel-cell battery topology | [Battery model](battery.md) |
| Read status from the terminal | [CLI](cli.md) |
| Run notifications without an open terminal | [Monitor](monitor.md) |
| Fix BLE, wake, UF2, or notification problems | [Troubleshooting](troubleshooting.md) |
| Run tests or inspect CI | [Development](development.md) |

## Current architecture

```text
right peripheral --BLE split link--> left central/master --BLE GATT--> macOS
       right pack                         left pack
          BAS proxy value                  main BAS value
```

The macOS host pairs with the **left central only**. The right side is not a
standalone keyboard over USB or host Bluetooth; USB on the right is used for
power, flashing, and diagnostics.

## Scope

Supported:

- macOS CoreBluetooth discovery and Battery Service reads;
- left/master and right/auxiliary percentage values;
- JSON output;
- 15% low-battery notifications;
- macOS LaunchAgent background monitoring.

Not currently supported:

- four independent values for two parallel cells per half;
- cycle count, temperature, designed capacity, or degradation health;
- Linux, Windows, USB-dongle, or Apple widget integration guarantees.
