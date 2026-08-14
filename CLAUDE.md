# SwiftSHT40

Swift driver for the SHT40 temperature/humidity sensor. Swift module name: **`SHT40`**.

Depends on: `SwiftPlatform`, `SwiftI2C`, `SwiftSupport`

## Files

| File | Role |
|---|---|
| `src/SHT40.swift` | Public `SHT40` struct — sensor driver |

## Public API

```swift
let bus = I2CMasterBus(i2cPort: I2C_NUM_0, sdaIoNum: GPIO_NUM_6, sclIoNum: GPIO_NUM_7)
let sensor = SHT40(i2cMasterBus: bus)
try sensor.setup()
let (temperature, humidity) = try sensor.read()
// No explicit cleanup — deinit handles it.
// Declare bus before sensor so Swift destroys them in reverse order (sensor first) — required IDF order.
```

## Non-obvious patterns

**Pure-Swift component** — no C wrapper, no `module.modulemap`. The driver only calls into the `I2C` and `Platform` Swift modules, so no Clang module bridge is needed.

**Caller owns the bus** — `SHT40.init(i2cMasterBus:)` registers a `Device` on the caller-supplied `I2CMasterBus` but does not own the bus. `SHT40` is `~Copyable`; its `deinit` removes only the device (via the wrapped `Device`'s own `deinit`) — the bus is cleaned up separately by the caller's `I2CMasterBus` going out of scope.

**I2C address fixed at 0x44** — this is the default SHT40 address (SHT40-AD1B variant). Other Sensirion SHT4x variants use 0x44/0x45/0x46; only the default is wired up here.

**No calibration step, unlike AHT20** — SHT40 has no on-chip calibration register to poll. `setup()` instead reads the sensor's serial number (command `0x89`) purely to confirm the device is present and CRCs check out before first use.

**No busy bit, unlike AHT20** — SHT40's measurement command has no status bit to poll for conversion-done. `read()` triggers a high-repeatability measurement (`0xFD`), waits past the datasheet's 8.3ms max conversion time, then retries the follow-up read a few times on failure — the sensor NACKs a read issued while still busy, so an early read is recoverable rather than fatal.

**Delays are rounded up to a full FreeRTOS tick** — this project's `test-app` runs `CONFIG_FREERTOS_HZ=100` (10ms tick), and `TickType_t(ms:)` truncates via integer division. A `vTaskDelay(.init(ms: 1))` therefore resolves to 0 ticks (no wait at all), not 1ms. All delays in this driver are sized in multiples of 10ms to guarantee real wait time rather than rounding to zero.
