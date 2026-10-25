# SwiftSHT40

Pure-Swift driver for the SHT40 temperature/humidity sensor, built on top of [SwiftI2C](../esp-swift-i2c). Swift module name: **`SHT40`**.

Depends on: `SwiftPlatform`, `SwiftI2C`, `SwiftSupport`.

## Adding it to a project

This is a [SwiftPM](https://www.swift.org/package-manager/) package, built for ESP-IDF by
`swift_package()` from [esp-swift-support](https://github.com/nixit22/esp-swift-support). In your
app's `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/nixit22/esp-swift-sht40.git", from: "0.1.0"),
],
targets: [
    .target(name: "App", dependencies: [.product(name: "SHT40", package: "esp-swift-sht40")]),
]
```

See esp-swift-support's README for the project setup (top-level `CMakeLists.txt`, `main`
component, Swift toolchain).

## Usage

```swift
import SHT40

let bus = I2CMasterBus(i2cPort: I2C_NUM_0, sdaIoNum: GPIO_NUM_6, sclIoNum: GPIO_NUM_7)
let sensor = SHT40(i2cMasterBus: bus)
try sensor.setup()
let (temperature, humidity) = try sensor.read()
// No explicit cleanup — deinit handles it.
// Declare bus before sensor so Swift destroys them in reverse order (sensor first) — required IDF order.
```

See [`CLAUDE.md`](CLAUDE.md) for full API details and non-obvious patterns.

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.
