# macOS CLI

The package lives at `tools/corne-battery` and uses CoreBluetooth to connect to
the left central and enumerate every Battery Service instance.

## Build and test

```sh
cd ~/www/personal/corne-wireless-zmk-config/tools/corne-battery
swift test
swift build --configuration release
```

The shell alias configured in the dotfiles repository is:

```sh
corne-battery
```

It runs the package through `swift run`. Until the fix PR is merged locally,
make sure the checkout contains the CLI branch.

## Commands

List candidate Bluetooth devices:

```sh
corne-battery devices
```

Read both halves in human-readable form:

```sh
corne-battery status --name Corne
```

Use the CoreBluetooth UUID when names are ambiguous:

```sh
corne-battery status \
  --device 09DFC75A-873C-462C-3DF3-96EDC8C5DC1F
```

Produce machine-readable JSON:

```sh
corne-battery status --name Corne --json
```

The `--timeout SECONDS` option controls discovery and GATT operations.

## Output

Example:

```text
Corne (A1B2C3D4-...)
  left: 83% [normal]
  right: 76% [normal]
  observed: 2026-01-01T12:00:00Z
  health: unavailable (not reported by ZMK firmware)
```

Statuses are:

- `normal`: above 15%;
- `low`: 6–15%;
- `critical`: 0–5%;
- `unavailable`: missing, unreadable, or reported as unavailable by BAS.

JSON includes two logical batteries where possible:

```json
{
  "batteries": [
    {"label":"left","percentage":83,"role":"main","status":"normal"},
    {"label":"right","percentage":76,"role":"auxiliary","status":"normal"}
  ],
  "health": null
}
```

## Limitations

The CLI does not make the right peripheral a separate macOS keyboard. It reads
the right value from the auxiliary BAS exposed by the left central. It also
cannot infer true battery health from a percentage.
