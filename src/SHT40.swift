// Copyright (c) 2026 Nicolas Christe
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import I2C
import Platform

private let log = Logger(tag: "SHT40")

private enum Registers: UInt8 {
    case measureHighPrecision = 0xFD
    case softReset = 0x94
    case readSerial = 0x89
}

public struct SHT40: ~Copyable {

    private let device: I2CMasterBus.Device

    /// Aborts on failure — intended for boot-time static allocation.
    public init(i2cMasterBus: borrowing I2CMasterBus) {
        do {
            self.device = try i2cMasterBus.addDevice(deviceAddress: 0x44, sclSpeedHz: 100_000)
        } catch {
            log.e("SHT40 init failed: \(error.name)")
            fatalError()
        }
    }

    public func setup() throws(Error) {
        log.d("Setting up SHT40")
        // Datasheet power-up time (tPU) is 1ms max, measured from VDD crossing
        // VPOR — IDF boot and bus init already take far longer than that before
        // this runs, so no explicit wait is needed here.

        // SHT40 has no calibration step. Read the serial number to confirm the
        // sensor is present and responding with valid CRCs.
        try device.transmit(data: [Registers.readSerial.rawValue], timeoutMs: 100)
        // FreeRTOS tick granularity (10ms in this project) means a 1ms delay
        // can round down to 0 — round up to a full tick's worth of margin.
        vTaskDelay(.init(ms: 20))
        let data = try device.receive(length: 6, timeoutMs: 100)
        guard crc8(data[0...1]) == data[2], crc8(data[3...4]) == data[5] else {
            log.w("SHT40 serial number CRC mismatch")
            throw Error.espError(ESP_ERR_INVALID_CRC)
        }
        log.d("SHT40 ready")
    }

    public func reset() throws(Error) {
        log.d("Resetting SHT40")
        try device.transmit(data: [Registers.softReset.rawValue], timeoutMs: 100)
        // Datasheet tSR (soft reset to idle) is 1ms max; round up to a full
        // tick (see setup()) rather than relying on bus overhead alone.
        vTaskDelay(.init(ms: 20))
        try setup()
    }

    public func read() throws(Error) -> (temperature: Float, humidity: Float) {
        log.d("Reading SHT40 sensor data")

        // Trigger a high-repeatability measurement.
        try device.transmit(data: [Registers.measureHighPrecision.rawValue], timeoutMs: 100)

        // Datasheet: typical 6.9ms, max 8.3ms conversion time. No busy bit to
        // poll on this sensor — instead wait past the max (rounded up to a full
        // tick, see setup()), then retry the read a few times. SHT40 NACKs a
        // read header issued while still busy (datasheet §4.1), so a read that
        // lands slightly early is recoverable rather than fatal.
        vTaskDelay(.init(ms: 20))

        // Read 6 bytes: temp MSB, temp LSB, temp CRC, humidity MSB, humidity LSB, humidity CRC.
        var data: [UInt8]
        var attempts = 0
        while true {
            do {
                data = try device.receive(length: 6, timeoutMs: 100)
                break
            } catch {
                attempts += 1
                if attempts == 5 {
                    log.w("SHT40 read failed after retries: \(error.name)")
                    throw error
                }
                vTaskDelay(.init(ms: 5))
            }
        }
        guard crc8(data[0...1]) == data[2], crc8(data[3...4]) == data[5] else {
            log.w("SHT40 CRC mismatch")
            throw Error.espError(ESP_ERR_INVALID_CRC)
        }

        let tRaw = (UInt32(data[0]) << 8) | UInt32(data[1])
        let temperature = -45.0 + 175.0 * Float(tRaw) / 65535.0

        let hRaw = (UInt32(data[3]) << 8) | UInt32(data[4])
        let humidity = min(max(-6.0 + 125.0 * Float(hRaw) / 65535.0, 0.0), 100.0)

        return (temperature: temperature, humidity: humidity)
    }
}

// CRC8 with polynomial 0x31, initial value 0xFF (per Sensirion datasheet).
private func crc8(_ bytes: some Sequence<UInt8>) -> UInt8 {
    var crc: UInt8 = 0xFF
    for byte in bytes {
        crc ^= byte
        for _ in 0..<8 {
            if (crc & 0x80) != 0 {
                crc = (crc << 1) ^ 0x31
            } else {
                crc <<= 1
            }
        }
    }
    return crc
}
