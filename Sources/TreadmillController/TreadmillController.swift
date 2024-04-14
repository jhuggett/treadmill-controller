// The Swift Programming Language
// https://docs.swift.org/swift-book

import CoreBluetooth
import Foundation

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

  func treadmillController(
    _ treadmillController: TreadmillController, beltStarted stats: TreadmillStats)
  func treadmillController(
    _ treadmillController: TreadmillController, beltStopped stats: TreadmillStats)
  func treadmillController(
    _ treadmillController: TreadmillController, beltSpeedChanged stats: TreadmillStats)
  func treadmillController(
    _ treadmillController: TreadmillController, modeChanged stats: TreadmillStats)
}

protocol ModelTranslator {
  func speedToMilesPerHour(speed: UInt8) -> Double
  func speedFromMilesPerHour(speed: Double) -> UInt8
}

// for the KS-ST-A1P
class KSSTA1PModelTranslator: ModelTranslator {
  func speedToMilesPerHour(speed: UInt8) -> Double {
    return Double(speed) / 16
  }

  func speedFromMilesPerHour(speed: Double) -> UInt8 {
    return UInt8(speed * 16)
  }
}

// <- Add your's here Chris

let supportedModels: [String: ModelTranslator] = ["KS-ST-A1P": KSSTA1PModelTranslator()]

public class TreadmillController: NSObject {
  var centralManager: CBCentralManager!
  var discoveredPeripherals = [CBPeripheral]()
  var treadmillPeripheral: CBPeripheral?
  var treadmillModelTranslator: ModelTranslator?

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

  var commandQueue: [[UInt8]] = []

  var isProcessingCommandQueue = false

  func processCommandQueue() {
    self.isProcessingCommandQueue = true

    if commandQueue.count == 0 {
      self.isProcessingCommandQueue = false
      return
    }

    let command = commandQueue.removeFirst()

    guard let peripheral = self.treadmillPeripheral else {
      print("No peripheral found")
      return
    }

    guard let treadmillCommandCharacteristic = self.treadmillCommandCharacteristic
    else {
      print("No command characteristic found")
      return
    }

    peripheral.writeValue(
      Data(applyChecksum(command)),
      for: treadmillCommandCharacteristic,
      type: .withoutResponse)

    print("--><-- Sent command", command, "to treadmill", "going to sleep, current time:", Date())

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
      print("--><-- Woke up from sleep, current time:", Date())
      self.processCommandQueue()
    }
  }

  func sendCommand(_ command: [UInt8]) {
    commandQueue.append(command)
    if !isProcessingCommandQueue {
      processCommandQueue()
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

  public func setSpeed(_ speed: Double) {
    print("SETTING SPEED", speed)

    // pass this through a converter

    let speedInt =
      self.treadmillModelTranslator?.speedFromMilesPerHour(speed: min(max(0.5, speed), 6.0))

    guard let speedInt = speedInt else {
      print("Could not compute speed, ignoring command")
      return
    }

    sendCommand([247, 162, 1, speedInt, 0xff, 253])
  }

  var timeBetweenStatsRequests = 5.0

  public func stopRequestingStats() {
    print("STOPPING REQUESTING STATS")

    setStatsRequestInterval(0)
  }

  public func setStatsRequestInterval(_ interval: Double) {
    print("SETTING STATS REQUEST INTERVAL", interval)

    timeBetweenStatsRequests = interval
  }

  public func startRequestingStats() {
    print("STARTING REQUESTING STATS")

    self.requestStats()

    if self.timeBetweenStatsRequests > 0 {
      DispatchQueue.main.asyncAfter(deadline: .now() + self.timeBetweenStatsRequests) {
        self.startRequestingStats()
      }
    }

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

  var lastStats: TreadmillStats? = nil

  func receivedStats(_ stats: [UInt8]) {
    print("Received stats", stats)
    let beltState = stats[2]
    let beltSpeed = treadmillModelTranslator?.speedToMilesPerHour(speed: stats[3]) ?? 0
    let beltMode = stats[4]
    let currentRunningTime = threeBigEndianBytesToInt(Array(stats[5...7]))
    let currentDistance = threeBigEndianBytesToInt(Array(stats[8...10]))
    let currentSteps = threeBigEndianBytesToInt(Array(stats[11...13]))

    let treadmillStats = TreadmillStats(
      beltState: beltState,
      beltSpeed: beltSpeed,
      beltMode: BeltMode(rawValue: Int(beltMode))!,
      currentRunningTime: currentRunningTime,
      currentDistance: currentDistance,
      currentSteps: currentSteps)

    delegate?.treadmillController(self, didUpdateStats: treadmillStats)

    if lastStats == nil || lastStats?.beltSpeed != treadmillStats.beltSpeed {
      delegate?.treadmillController(self, beltSpeedChanged: treadmillStats)
    }

    if (lastStats == nil || lastStats?.beltSpeed == 0) && treadmillStats.beltSpeed > 0 {
      delegate?.treadmillController(self, beltStarted: treadmillStats)
    }

    if lastStats != nil && lastStats!.beltSpeed > 0 && treadmillStats.beltSpeed == 0 {
      delegate?.treadmillController(self, beltStopped: treadmillStats)
    }

    if lastStats == nil || lastStats?.beltMode != treadmillStats.beltMode {
      delegate?.treadmillController(self, modeChanged: treadmillStats)
    }

    lastStats = treadmillStats
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
    if supportedModels.keys.contains(peripheral.name ?? "") {
      print("Found Treadmill", peripheral.name ?? "")
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

    self.treadmillModelTranslator = supportedModels[peripheral.name ?? ""]

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
      receivedStats(stats)
    }
  }

}

public enum BeltMode: Int, Encodable {
  case Auto = 0
  case Manual = 1
  case Standby = 2
}

public struct TreadmillStats: Encodable {
  public let beltState: UInt8
  public let beltSpeed: Double
  public let beltMode: BeltMode
  public let currentRunningTime: Int
  public let currentDistance: Int
  public let currentSteps: Int
}
