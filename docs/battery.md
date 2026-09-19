# Battery model and calibration

## Physical topology

Each half has two identical 1-cell 3.7 V LiPo batteries in parallel. Parallel
cells share voltage and increase capacity; they do not create two measurable
battery channels.

The current hardware therefore provides two pack readings:

```text
left  = left cell pair, one combined 1S voltage
right = right cell pair, one combined 1S voltage
```

Do not add or average two percentages on one half. Four independent readings
would require separate sensing hardware and firmware channels.

## What ZMK reports

The nice!nano v2 uses the `zmk,battery-nrf-vddh` sensor. ZMK v0.3's default
lithium voltage mapping is approximately linear:

- 3450 mV → 0%
- 4200 mV → 100%

This is an estimate of state of charge. It is not battery health. The current
setup does not expose:

- cycle count;
- designed or full-charge capacity;
- remaining capacity in mAh;
- temperature;
- internal resistance;
- degradation percentage.

The CLI reports `health: null` for this reason.

## Correct calibration order

If a percentage looks wrong, isolate the layers in this order:

1. measure the pack voltage at the battery/controller with a multimeter;
2. compare it with the millivolts in the debug log;
3. fix sensor/wiring/scaling if the sensed millivolts are wrong;
4. only then evaluate the voltage-to-percentage mapping;
5. repeat separately for left and right.

Do not calibrate using a voltage measured during a transient load or while the
pack is being charged. Parallel packs have the same nominal 1S voltage range,
but capacity and cell matching still affect discharge behavior.

## Host interpretation

The left main BAS value is the central's local battery. The right auxiliary BAS
value is fetched by the central from the peripheral and proxied through a
second Battery Service.

The CLI identifies the auxiliary service using ZMK's Characteristic
Presentation Format descriptor (`0x2904`, description `0x0108`). It does not
assume that CoreBluetooth returns the main service first.

Battery Service values do not include a sensor timestamp. The CLI's `observedAt`
means when the host read the value; a proxy value may still be stale if the
right half is asleep, disconnected, or has not updated recently.
