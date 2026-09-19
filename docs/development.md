# Development and validation

## Repository layout

```text
config/corne.conf                 ZMK production configuration
config/corne.keymap               keymap and Bluetooth controls
config/snippets/battery-debug/    opt-in diagnostic snippet
build.yaml                        left/right/settings-reset matrix
tools/corne-battery/              Swift package and CLI
tools/corne-battery/Tests/        pure battery and alert tests
docs/                             operational documentation
```

## Swift checks

Run from `tools/corne-battery`:

```sh
swift test
swift build --configuration release
```

The tests cover:

- Battery Level decoding and invalid values;
- main/auxiliary CPF classification;
- left/right mapping;
- normal/low/critical thresholds;
- notification crossing and re-arm behavior;
- JSON output and explicit unavailable health.

## CLI smoke tests

With the physical keyboard paired:

```sh
.build/release/corne-battery devices --timeout 8
.build/release/corne-battery status --name Corne --json --timeout 15
```

A successful split smoke test should expose one `main` and one `auxiliary`
battery. Values depend on the actual packs and may change while charging.

## Firmware CI

The existing ZMK workflow builds:

- `nice_nano_v2` + `corne_left`;
- `nice_nano_v2` + `corne_right`;
- `nice_nano_v2` + `settings_reset`.

The separate Swift workflow runs on macOS and executes tests plus a release
build. Hardware behavior still requires physical validation after flashing.

## Safe change process

1. make a small configuration or host change;
2. run `git diff --check`;
3. run Swift tests/build when changing `tools/corne-battery`;
4. verify both firmware matrix artifacts in GitHub Actions when changing ZMK
   configuration;
5. test status, wake/reconnect, and both battery values on hardware;
6. document any hardware-only limitation separately from CI results.
