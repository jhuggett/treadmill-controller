// The Swift Programming Language
// https://docs.swift.org/swift-book

import CoreBluetooth
import Foundation

let commandQueue = DispatchQueue(label: "commandQueue")

public protocol TreadmillControllerDelegate {
  func treadmillController(
    _ treadmillController: TreadmillController, readyToScanForTreadmills ready: Bool)
  func treadmillController(
    _ treadmillController: TreadmillController, didUpdateStats stats: TreadmillStats)
  func treadmillController(
    _ treadmillController: TreadmillController, didDiscoverTreadmill peripheral: CBPeripheral)
  func treadmillController(
    _ treadmillController: TreadmillController, didConnectToTreadmill peripheral: CBPeripheral)
  func treadmillController(
    _ treadmillController: TreadmillController,
    didFailToConnectToTreadmill peripheral: CBPeripheral, error: Error)
  func treadmillController(
    _ treadmillController: TreadmillController, didDisconnectFromTreadmill peripheral: CBPeripheral,
    error: Error)
}

public class TreadmillController: NSObject {
  var centralManager: CBCentralManager!
  var discoveredPeripherals = [CBPeripheral]()
  var treadmillPeripheral: CBPeripheral?

  var treadmillCommandCharacteristic: CBCharacteristic?
  var treadmillStatsCharacteristic: CBCharacteristic?

  public var delegate: TreadmillControllerDelegate?

  public override init() {
    print("TreadmillManager is being initialized")
    super.init()
    centralManager = CBCentralManager(delegate: self, queue: DispatchQueue.global())
  }

  deinit {
    print("TreadmillManager is being deallocated")
  }

  private func applyChecksum(_ bytes: [UInt8]) -> [UInt8] {
    print("Cleaning bytes", bytes)

    var cmd = bytes
    cmd[cmd.count - 2] = UInt8(UInt16(cmd[1..<cmd.count - 2].reduce(0, +)) % 256)
    print("Cleaned bytes", cmd)

    return cmd
  }

  func sendCommand(_ command: [UInt8]) {
    guard let peripheral = self.treadmillPeripheral else {
      print("No peripheral found")
      return
    }

    guard let treadmillCommandCharacteristic = self.treadmillCommandCharacteristic
    else {
      print("No command characteristic found")
      return
    }

    commandQueue.sync {
      peripheral.writeValue(
        Data(applyChecksum(command)),
        for: treadmillCommandCharacteristic,
        type: .withoutResponse)

      usleep(700)
    }
  }

  public func startBelt() {
    print("STARTING BELT")
    sendCommand([247, 162, 4, 1, 0xff, 253])
  }

  public func stopBelt() {
    print("STOPPING BELT")
    sendCommand([247, 162, 1, 0, 0xff, 253])
  }

  public func selectManualMode() {
    print("SET MODE MANUAL")
    sendCommand([247, 162, 2, 1, 0xff, 253])
  }

  public func selectStandbyMode() {
    print("SET MODE STANDBY")
    sendCommand([247, 162, 2, 2, 0xff, 253])
  }

  public func requestStats() {
    print("REQUESTING STATS")
    sendCommand([247, 162, 0, 0, 162, 253])
  }

  public func setSpeed(_ speed: Int) {
    print("SETTING SPEED", speed)

    sendCommand([247, 162, 1, UInt8(speed), 0xff, 253])
  }

  public func startScanning() {
    print("Starting scanning")
    centralManager.scanForPeripherals(withServices: [
      CBUUID(string: "00001800-0000-1000-8000-00805f9b34fb"),
      CBUUID(string: "0000180a-0000-1000-8000-00805f9b34fb"),
      CBUUID(string: "00010203-0405-0607-0809-0a0b0c0d1912"),
      CBUUID(string: "0000fe00-0000-1000-8000-00805f9b34fb"),
      CBUUID(string: "00002902-0000-1000-8000-00805f9b34fb"),
      CBUUID(string: "00010203-0405-0607-0809-0a0b0c0d1912"),
      CBUUID(string: "00002901-0000-1000-8000-00805f9b34fb"),
      CBUUID(string: "00002a00-0000-1000-8000-00805f9b34fb"),
      CBUUID(string: "00002a01-0000-1000-8000-00805f9b34fb"),
      CBUUID(string: "00002a04-0000-1000-8000-00805f9b34fb"),
      CBUUID(string: "00002a25-0000-1000-8000-00805f9b34fb"),
      CBUUID(string: "00002a26-0000-1000-8000-00805f9b34fb"),
      CBUUID(string: "00002a28-0000-1000-8000-00805f9b34fb"),
      CBUUID(string: "00002a24-0000-1000-8000-00805f9b34fb"),
      CBUUID(string: "00002a29-0000-1000-8000-00805f9b34fb"),
      CBUUID(string: "0000fe01-0000-1000-8000-00805f9b34fb"),
      CBUUID(string: "0000fe02-0000-1000-8000-00805f9b34fb"),
      CBUUID(string: "00010203-0405-0607-0809-0a0b0c0d2b12"),
    ])
  }

  public func stopScanning() {
    print("Stopping scanning")
    centralManager.stopScan()
  }

  public func connectToTreadmill(_ peripheral: CBPeripheral) {
    print("Connecting to peripheral", peripheral)
    centralManager.connect(peripheral, options: nil)
  }
}

extension TreadmillController: CBCentralManagerDelegate {
  public func centralManagerDidUpdateState(_ central: CBCentralManager) {
    print("Central Manager did update state", central.state.rawValue)
    if central.state == .poweredOn {
      delegate?.treadmillController(self, readyToScanForTreadmills: true)
    } else {
      delegate?.treadmillController(self, readyToScanForTreadmills: false)
    }
  }

  public func centralManager(
    _ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?
  ) {
    print("Disconnected from peripheral", peripheral, error!)
  }

  public func centralManager(
    _ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
    advertisementData: [String: Any], rssi RSSI: NSNumber
  ) {
    print("Peripheral Discovered: \(peripheral)")
    print("Peripheral name: \(String(describing: peripheral.name))")
    print("Advertisement Data : \(advertisementData)")
    if peripheral.name == "KS-ST-A1P" {
      print("Found Treadmill")
      self.discoveredPeripherals.append(peripheral)
      print("Connecting to peripheral Treadmill")

      delegate?.treadmillController(self, didDiscoverTreadmill: peripheral)

      //central.connect(peripheral, options: nil)
    }
  }

  public func centralManager(
    _ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?
  ) {
    print("Failed to connect to peripheral", peripheral, error!)
  }

  public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
    self.treadmillPeripheral = peripheral
    print("Connected to peripheral", peripheral, treadmillPeripheral!)

    peripheral.delegate = self
    peripheral.discoverServices(nil)
  }
}

extension TreadmillController: CBPeripheralDelegate {
  public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
    print("Discovered services", peripheral.services ?? "")
    for service in peripheral.services! {
      print("service", service.uuid.uuidString)
      peripheral.discoverCharacteristics(nil, for: service)
    }
  }

  public func peripheral(
    _ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?
  ) {
    print("Discovered characteristics", service.characteristics ?? "")
    for characteristic in service.characteristics! {
      print("characteristic", characteristic.uuid.uuidString)
      if characteristic.uuid.uuidString == "FE01" {
        treadmillStatsCharacteristic = characteristic

        print("Found stats characteristic", characteristic)

        treadmillPeripheral?.setNotifyValue(true, for: characteristic)
      }

      if characteristic.uuid.uuidString == "FE02" {
        treadmillCommandCharacteristic = characteristic
        print("Found command characteristic", characteristic)
      }

      if treadmillStatsCharacteristic != nil && treadmillCommandCharacteristic != nil {
        delegate?.treadmillController(self, didConnectToTreadmill: peripheral)
      }
    }
  }

  private func threeBigEndianBytesToInt(_ bytes: [UInt8]) -> Int {
    return Int(bytes[0]) * 256 * 256 + Int(bytes[1]) * 256 + Int(bytes[2])
  }

  public func peripheral(
    _ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?
  ) {
    print("Updated value for characteristic", characteristic)
    if characteristic.uuid.uuidString == "FE01" {
      guard let value = characteristic.value else {
        print("No value found")
        return
      }

      let stats = [UInt8](value)
      print("Stats", stats)

      let beltState = stats[2]
      let beltSpeed = stats[3]
      let beltMode = stats[4]
      let currentRunningTime = threeBigEndianBytesToInt(Array(stats[5...7]))
      let currentDistance = threeBigEndianBytesToInt(Array(stats[8...10]))
      let currentSteps = threeBigEndianBytesToInt(Array(stats[11...13]))

      let treadmillStats = TreadmillStats(
        beltState: beltState,
        beltSpeed: beltSpeed,
        beltMode: beltMode,
        currentRunningTime: currentRunningTime,
        currentDistance: currentDistance,
        currentSteps: currentSteps)

      delegate?.treadmillController(self, didUpdateStats: treadmillStats)
    }
  }
}

public struct TreadmillStats: Encodable {
  public let beltState: UInt8
  public let beltSpeed: UInt8
  public let beltMode: UInt8
  public let currentRunningTime: Int
  public let currentDistance: Int
  public let currentSteps: Int
}
