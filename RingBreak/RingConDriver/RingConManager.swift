//
//  RingConManager.swift
//  RingBreak
//
//  High-level manager for Ring-Con connection and state
//

import Foundation
import Combine
import IOBluetooth
import CoreBluetooth

enum CalibrationPhase: Equatable {
    case idle
    case neutral
    case pull
    case squeeze
    case complete
    case failed(CalibrationFailureReason)
}

enum CalibrationFailureReason: Equatable {
    case noPull
    case noSqueeze
}

/// Bluetooth and device status
enum BluetoothStatus: Equatable {
    case unknown
    case off
    case on
    case unauthorized
}

enum PairedDeviceStatus: Equatable {
    case noPairedDevice
    case pairedNotConnected
    case pairedAndConnected
}

/// High-level manager for Joy-Con and Ring-Con connectivity
@MainActor
class RingConManager: NSObject, ObservableObject {
    // MARK: - Published Properties

    /// Current connection state
    @Published private(set) var connectionState: ConnectionState = .disconnected

    /// Whether a Ring-Con is attached to the Joy-Con
    @Published private(set) var ringConAttached: Bool = false

    /// Current flex sensor value (0.0 = full pull, 0.5 = neutral, 1.0 = full squeeze)
    @Published private(set) var flexValue: Double = 0.5

    /// Current Joy-Con state including buttons, stick, and battery
    @Published private(set) var joyConState: JoyConState = JoyConState()

    /// Last error message
    @Published private(set) var lastError: String?

    /// Bluetooth power status
    @Published private(set) var bluetoothStatus: BluetoothStatus = .unknown

    /// Whether a Joy-Con is paired in system Bluetooth
    @Published private(set) var pairedDeviceStatus: PairedDeviceStatus = .noPairedDevice

    /// Last IMU reading (averaged across 3 frames)
    @Published private(set) var imuReading: IMUReading = IMUReading(acceleration: .zero, angularVelocity: .zero)

    /// Orientation estimate derived from IMU data
    @Published private(set) var orientation: Orientation = .zero

    /// Angular velocity magnitude (deg/s)
    @Published private(set) var angularVelocityMagnitude: Double = 0

    // MARK: - Computed Properties

    /// Whether a Joy-Con is connected
    var isConnected: Bool {
        connectionState == .connected
    }

    // MARK: - Private Properties

    private let hid = JoyConHID()
    private var mcuInitialized = false
    private var calibrationInProgress = false
    @Published private(set) var isCalibrating = false
    @Published private(set) var calibrationSecondsRemaining = 0
    @Published private(set) var calibrationPhase: CalibrationPhase = .idle
    private var hasCalibration = false
    private var neutralFlexByte: UInt8?
    private var calibrationTask: Task<Void, Never>?
    private var calibrationBackup: CalibrationBackup?

    // Calibration values
    private var neutralFlexValue: UInt16 = 0x0A
    private var minFlexValue: UInt16 = 0x00
    private var maxFlexValue: UInt16 = 0x14
    private var calibrationHoldDuration: Int { Constants.calibrationHoldDuration }
    private var calibrationActionDuration: Int { Constants.calibrationActionDuration }

    private struct CalibrationBackup {
        let neutralFlexValue: UInt16
        let minFlexValue: UInt16
        let maxFlexValue: UInt16
        let neutralFlexByte: UInt8?
        let hasCalibration: Bool
    }

    // Persistence keys
    private enum CalibrationKeys {
        static let hasCalibration = "ringCon.hasCalibration"
        static let neutralFlexValue = "ringCon.neutralFlexValue"
        static let minFlexValue = "ringCon.minFlexValue"
        static let maxFlexValue = "ringCon.maxFlexValue"
        static let neutralFlexByte = "ringCon.neutralFlexByte"
    }

    // Bluetooth connection observer (nonisolated for deinit access)
    nonisolated(unsafe) private var bluetoothConnectionObserver: Any?

    // CBCentralManager to trigger Bluetooth permission prompt
    private var centralManager: CBCentralManager?
    private var centralManagerDelegate: BluetoothPermissionDelegate?

    // MARK: - Initialization

    override init() {
        super.init()
        hid.delegate = self
        loadCalibration()
        requestBluetoothPermissionIfNeeded()
        checkBluetoothAndDeviceStatus()
        startBluetoothConnectionListener()
    }

    /// Set up Bluetooth monitoring (permission prompt if needed, state monitoring always)
    private func requestBluetoothPermissionIfNeeded() {
        // Always create a CBCentralManager to monitor Bluetooth state changes
        // This also triggers the permission prompt if not yet determined
        centralManagerDelegate = BluetoothPermissionDelegate { [weak self] in
            Task { @MainActor in
                self?.handleBluetoothStateChange()
            }
        }
        centralManager = CBCentralManager(delegate: centralManagerDelegate, queue: .main)
    }

    /// Handle Bluetooth state changes (on/off, permission changes)
    private func handleBluetoothStateChange() {
        let previousStatus = bluetoothStatus
        checkBluetoothAndDeviceStatus()

        // If Bluetooth was turned off while connected, disconnect
        if bluetoothStatus == .off && previousStatus != .off && isConnected {
            disconnect()
        }
    }

    deinit {
        // Capture the observer before accessing it from nonisolated deinit
        let observer = bluetoothConnectionObserver
        DispatchQueue.main.async {
            (observer as? IOBluetoothUserNotification)?.unregister()
        }
    }

    /// Listen for Bluetooth device connections
    private func startBluetoothConnectionListener() {
        // Register for device connection notifications
        bluetoothConnectionObserver = IOBluetoothDevice.register(forConnectNotifications: self, selector: #selector(bluetoothDeviceConnected(_:device:)))
    }

    @objc nonisolated private func bluetoothDeviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        // Check if this is a Joy-Con
        guard let deviceName = device.name, deviceName.contains("Joy-Con") else { return }

        // Update status and auto-connect on main thread
        Task { @MainActor [weak self] in
            DebugLogger.shared.log("Bluetooth device connected: \(deviceName)", category: .hid)
            self?.checkBluetoothAndDeviceStatus()

            // If not already connected, try to connect with retries
            // The Bluetooth stack needs time to fully establish the HID connection
            if self?.connectionState == .disconnected {
                await self?.autoConnectWithRetry()
            }
        }
    }

    /// Try to connect with retries, giving the Bluetooth stack time to settle
    private func autoConnectWithRetry() async {
        let maxAttempts = Constants.autoConnectMaxAttempts
        let delays: [UInt64] = [1_000_000_000, 1_500_000_000, 2_000_000_000]  // 1s, 1.5s, 2s

        for attempt in 0..<maxAttempts {
            // Wait before attempting
            try? await Task.sleep(nanoseconds: delays[attempt])

            // Check if still disconnected (user might have manually connected or cancelled)
            guard connectionState == .disconnected else { return }

            DebugLogger.shared.log("Auto-connect attempt \(attempt + 1)/\(maxAttempts)", category: .connection)
            startScanning()

            // Wait a bit to see if connection succeeds
            try? await Task.sleep(nanoseconds: 2_000_000_000)  // 2s to let initialization complete

            // If connected, we're done
            if connectionState == .connected {
                return
            }

            // If still trying (scanning/connecting), wait for it to finish
            if connectionState == .scanning || connectionState == .connecting {
                // Wait up to 5 more seconds for it to complete
                for _ in 0..<10 {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    if connectionState == .connected || connectionState == .disconnected {
                        break
                    }
                }
            }

            // If connected now, we're done
            if connectionState == .connected {
                return
            }
        }

        DebugLogger.shared.log("Auto-connect failed after \(maxAttempts) attempts", category: .connection)
    }

    // MARK: - Calibration Persistence

    private func loadCalibration() {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: CalibrationKeys.hasCalibration) {
            hasCalibration = true
            neutralFlexValue = UInt16(defaults.integer(forKey: CalibrationKeys.neutralFlexValue))
            minFlexValue = UInt16(defaults.integer(forKey: CalibrationKeys.minFlexValue))
            maxFlexValue = UInt16(defaults.integer(forKey: CalibrationKeys.maxFlexValue))
            let storedNeutralByte = defaults.integer(forKey: CalibrationKeys.neutralFlexByte)
            neutralFlexByte = storedNeutralByte > 0 ? UInt8(storedNeutralByte) : nil
            #if DEBUG
            print("Loaded calibration: neutral=\(neutralFlexValue), min=\(minFlexValue), max=\(maxFlexValue)")
            #endif
        }
    }

    private func saveCalibration() {
        let defaults = UserDefaults.standard
        defaults.set(hasCalibration, forKey: CalibrationKeys.hasCalibration)
        defaults.set(Int(neutralFlexValue), forKey: CalibrationKeys.neutralFlexValue)
        defaults.set(Int(minFlexValue), forKey: CalibrationKeys.minFlexValue)
        defaults.set(Int(maxFlexValue), forKey: CalibrationKeys.maxFlexValue)
        if let neutralByte = neutralFlexByte {
            defaults.set(Int(neutralByte), forKey: CalibrationKeys.neutralFlexByte)
        }
        #if DEBUG
        print("Saved calibration: neutral=\(neutralFlexValue), min=\(minFlexValue), max=\(maxFlexValue)")
        #endif
    }

    /// Check Bluetooth authorization, power state and paired devices
    func checkBluetoothAndDeviceStatus() {
        // Check Bluetooth authorization first
        let authorization = CBCentralManager.authorization
        switch authorization {
        case .denied, .restricted:
            bluetoothStatus = .unauthorized
            return
        case .notDetermined:
            // Will be determined when we try to use Bluetooth
            break
        case .allowedAlways:
            break
        @unknown default:
            break
        }

        // Check Bluetooth power state using IOBluetooth
        // IOBluetoothHostController gives us the system Bluetooth status
        if let controller = IOBluetoothHostController.default() {
            let powerState = controller.powerState
            switch powerState {
            case kBluetoothHCIPowerStateON:
                bluetoothStatus = .on
            case kBluetoothHCIPowerStateOFF:
                bluetoothStatus = .off
            default:
                bluetoothStatus = .unknown
            }
        } else {
            bluetoothStatus = .unknown
        }

        // Check for paired/connected Joy-Con devices
        let connectedDevices = JoyConHID.listConnectedDevices()
        let hasJoyCon = connectedDevices.contains { $0.productID == NintendoHID.productIDJoyConR }

        if hasJoyCon {
            pairedDeviceStatus = .pairedAndConnected
        } else {
            // Check paired devices (even if not currently connected)
            // This requires checking the Bluetooth paired devices list
            // Note: Only check devices that have a valid address to avoid "No name or address" warnings
            let pairedDevices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
            let hasPairedJoyCon = pairedDevices.contains { device in
                guard device.addressString != nil else { return false }
                return device.name?.contains("Joy-Con") == true
            }
            pairedDeviceStatus = hasPairedJoyCon ? .pairedNotConnected : .noPairedDevice
        }
    }

    /// Automatically connect if Joy-Con is already connected
    func autoConnectIfAvailable() {
        guard connectionState == .disconnected else { return }
        checkBluetoothAndDeviceStatus()

        if pairedDeviceStatus == .pairedAndConnected {
            // Joy-Con is already connected via Bluetooth, start scanning to open HID
            startScanning()
        }
    }

    // MARK: - Public Methods

    /// Start scanning for Joy-Con devices
    func startScanning() {
        guard connectionState == .disconnected else { return }

        connectionState = .scanning
        lastError = nil

        hid.startScanning { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self = self else { return }

                switch result {
                case .success(let deviceType):
                    self.connectionState = .connecting
                    self.joyConState.type = deviceType

                    if deviceType.supportsRingCon {
                        await self.initializeRingCon()
                    } else {
                        self.connectionState = .connected
                        self.lastError = "Connected to \(deviceType.name), but Ring-Con requires Joy-Con (R)"
                    }

                case .failure(let error):
                    self.connectionState = .disconnected
                    self.lastError = error.localizedDescription
                }
            }
        }
    }

    /// Disconnect from the Joy-Con
    func disconnect() {
        hid.disconnect()
        connectionState = .disconnected
        ringConAttached = false
        mcuInitialized = false
        ringConMissedCount = 0
        ringConPresentCount = 0
        ringConRecoveryTask?.cancel()
        ringConRecoveryTask = nil
        cancelCalibration()
        hasCalibration = false
        isCalibrating = false
        calibrationSecondsRemaining = 0
        calibrationPhase = .idle
        neutralFlexByte = nil
        flexValue = 0.5
        imuReading = IMUReading(acceleration: .zero, angularVelocity: .zero)
        orientation = .zero
        angularVelocityMagnitude = 0
        lastIMUTimestamp = Date()
        filteredAcceleration = .zero
        filteredGyro = .zero
        gyroBias = .zero
        gyroBiasAccum = .zero
        gyroBiasSamples = 0
        lastStableGyro = .zero
        stableGyroSamples = 0
        imuLogCounter = 0
        yawRestSamples = 0
    }

    /// Re-initialize Ring-Con MCU configuration
    /// Call this after the user clips in the Ring-Con to re-detect it
    func reinitializeRingCon() {
        guard isConnected else { return }
        DebugLogger.shared.log("Re-initializing Ring-Con MCU (post-onboarding)", category: .mcu)

        // Reset Ring-Con state
        ringConAttached = false
        mcuInitialized = false
        ringConMissedCount = 0
        ringConPresentCount = 0
        ringConRecoveryTask?.cancel()
        ringConRecoveryTask = nil
        mcuReportCount = 0
        neutralFlexByte = nil
        flexValue = 0.5
        lastFlexByte = 0x0A

        // Re-run MCU initialization
        Task {
            await initializeRingCon()
        }
    }

    /// Periodically re-initialize MCU to detect Ring-Con re-attachment.
    /// The MCU stops reporting Ring-Con data after physical detachment and won't
    /// recover on its own — a full MCU re-init is required to detect re-attachment.
    private func scheduleRingConRecovery() {
        ringConRecoveryTask?.cancel()
        ringConRecoveryTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(Constants.ringConRecoveryInterval * 1_000_000_000))
                guard let self = self, self.isConnected, !self.ringConAttached else { return }
                DebugLogger.shared.log("Attempting Ring-Con recovery (re-initializing MCU)...", category: .ringcon)
                self.reinitializeRingCon()
                // Wait for MCU init to complete before next attempt
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    /// Start calibration process
    func calibrate() {
        startGuidedCalibration()
    }

    func startGuidedCalibration() {
        guard isConnected && ringConAttached else { return }
        guard !isCalibrating else { return }

        calibrationTask?.cancel()
        calibrationBackup = CalibrationBackup(
            neutralFlexValue: neutralFlexValue,
            minFlexValue: minFlexValue,
            maxFlexValue: maxFlexValue,
            neutralFlexByte: neutralFlexByte,
            hasCalibration: hasCalibration
        )

        calibrationInProgress = true
        isCalibrating = true
        calibrationPhase = .neutral
        calibrationSecondsRemaining = calibrationHoldDuration
        hasCalibration = false

        neutralFlexValue = joyConState.flexState.rawValue
        neutralFlexByte = UInt8(clamping: neutralFlexValue)
        minFlexValue = neutralFlexValue
        maxFlexValue = neutralFlexValue

        calibrationTask = Task { [weak self] in
            await self?.runGuidedCalibration()
        }
    }

    func cancelCalibration() {
        calibrationTask?.cancel()
        calibrationTask = nil
        calibrationInProgress = false
        isCalibrating = false
        calibrationSecondsRemaining = 0
        calibrationPhase = .idle

        if let backup = calibrationBackup {
            neutralFlexValue = backup.neutralFlexValue
            minFlexValue = backup.minFlexValue
            maxFlexValue = backup.maxFlexValue
            neutralFlexByte = backup.neutralFlexByte
            hasCalibration = backup.hasCalibration
        }
        calibrationBackup = nil
    }

    // MARK: - Private Methods

    private func initializeRingCon() async {
        do {
            try await loadIMUCalibration()

            // Step 1: Enable IMU first (required for MCU mode to work)
            DebugLogger.shared.logMCUStep("Enable IMU (0x40)", success: true)
            try await hid.enableIMU()
            try await Task.sleep(nanoseconds: 50_000_000)

            // Step 1.5: Set IMU sensitivity (match RingConInput Unity lib defaults)
            DebugLogger.shared.logMCUStep("Set IMU sensitivity (0x41)", success: true)
            try await hid.setIMUSensitivity(gyro: 0x03, accel: 0x00, gyroPerformance: 0x01, accelFilter: 0x01)
            try await Task.sleep(nanoseconds: 50_000_000)

            // Step 2: Set input report mode to standard full mode first
            DebugLogger.shared.logMCUStep("Set input mode to full (0x30)", success: true)
            try await hid.setInputReportMode(.fullWithIMU)
            try await Task.sleep(nanoseconds: 50_000_000)

            // Step 3: Enable MCU
            DebugLogger.shared.logMCUStep("Enable MCU (0x22, arg=0x01)", success: true)
            try await hid.enableMCU()
            try await Task.sleep(nanoseconds: 200_000_000)  // MCU needs time to initialize

            // Step 4: Keep input report mode at full (0x30) for Ring-Con flex byte
            DebugLogger.shared.logMCUStep("Set input mode to full (0x30)", success: true)
            try await hid.setInputReportMode(.fullWithIMU)
            try await Task.sleep(nanoseconds: 100_000_000)

            // Step 5: Configure MCU for Ring-Con mode
            DebugLogger.shared.logMCUStep("Configure MCU for Ring-Con (0x21)", success: true)
            try await hid.configureRingConMode()
            try await Task.sleep(nanoseconds: 100_000_000)

            // Step 6: Start Ring-Con data polling
            DebugLogger.shared.logMCUStep("Start Ring-Con polling", success: true)
            try await hid.startRingConPolling()

            mcuInitialized = true
            mcuReportCount = 0  // Reset so we get fresh logging after init
            connectionState = .connected
            lastError = nil  // Clear any previous error on successful MCU init
            DebugLogger.shared.logMCUStep("MCU initialization complete", success: true)

            // Ring-Con attachment will be detected via input reports

        } catch {
            DebugLogger.shared.logMCUStep("MCU init failed: \(error.localizedDescription)", success: false)
            connectionState = .disconnected
            lastError = "Failed to initialize Ring-Con: \(error.localizedDescription)"
        }
    }

    private func finishCalibration() async {
        calibrationInProgress = false
        isCalibrating = false
        calibrationSecondsRemaining = 0
        calibrationPhase = .complete

        // Store calibration values
        joyConState.flexState.neutralOffset = neutralFlexValue
        joyConState.flexState.maxPull = minFlexValue
        joyConState.flexState.maxSqueeze = maxFlexValue
        hasCalibration = minFlexValue < maxFlexValue

        // Persist calibration for next app run
        saveCalibration()
        calibrationBackup = nil

        #if DEBUG
        print("Calibration complete:")
        print("  Neutral: \(neutralFlexValue)")
        print("  Min (pull): \(minFlexValue)")
        print("  Max (squeeze): \(maxFlexValue)")
        #endif
    }

    private func runGuidedCalibration() async {
        await runPhase(.neutral, duration: calibrationHoldDuration)
        guard !Task.isCancelled else { return }

        neutralFlexValue = joyConState.flexState.rawValue
        neutralFlexByte = UInt8(clamping: neutralFlexValue)
        minFlexValue = neutralFlexValue
        maxFlexValue = neutralFlexValue

        await runPhase(.pull, duration: calibrationActionDuration)
        guard !Task.isCancelled else { return }

        // Check if pull was detected
        let pullRange = Int(neutralFlexValue) - Int(minFlexValue)
        guard pullRange >= Constants.calibrationMinRange else {
            await failCalibration(reason: .noPull)
            return
        }

        await runPhase(.squeeze, duration: calibrationActionDuration)
        guard !Task.isCancelled else { return }

        // Check if squeeze was detected
        let squeezeRange = Int(maxFlexValue) - Int(neutralFlexValue)
        guard squeezeRange >= Constants.calibrationMinRange else {
            await failCalibration(reason: .noSqueeze)
            return
        }

        await finishCalibration()
        calibrationTask = nil
    }

    private func failCalibration(reason: CalibrationFailureReason) async {
        calibrationInProgress = false
        isCalibrating = false
        calibrationSecondsRemaining = 0
        calibrationPhase = .failed(reason)
        calibrationTask = nil

        // Restore backup so previous calibration (if any) is preserved
        if let backup = calibrationBackup {
            neutralFlexValue = backup.neutralFlexValue
            minFlexValue = backup.minFlexValue
            maxFlexValue = backup.maxFlexValue
            neutralFlexByte = backup.neutralFlexByte
            hasCalibration = backup.hasCalibration
        }
        calibrationBackup = nil

        #if DEBUG
        print("Calibration failed: no meaningful input detected")
        #endif
    }

    private func runPhase(_ phase: CalibrationPhase, duration: Int) async {
        calibrationPhase = phase
        // Play sound at start of each phase
        SoundHelper.play("Ping")
        for remaining in stride(from: duration, through: 1, by: -1) {
            calibrationSecondsRemaining = remaining
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if Task.isCancelled {
                return
            }
            // Tick sound for countdown
            if remaining > 1 {
                SoundHelper.play("Tink")
            }
        }
        calibrationSecondsRemaining = 0
    }

    private func processInputReport(_ data: [UInt8]) {
        guard !data.isEmpty else { return }

        let reportID = data[0]

        switch reportID {
        case HIDReportID.standardInput.rawValue:
            processStandardInput(data)
            processMCUInput(data)  // Ring-Con flex byte is present in 0x30 reports

        case HIDReportID.mcuInput.rawValue:
            processStandardInput(data)  // First part is same as standard
            processMCUInput(data)

        case 0x21:  // Subcommand reply
            processSubcommandReply(data)

        default:
            break
        }
    }

    private func processSubcommandReply(_ data: [UInt8]) {
        guard data.count >= 15 else { return }

        // Report 0x21 format:
        // [0] = 0x21 (report ID)
        // [1] = Timer
        // [2] = Battery/connection
        // [3-5] = Buttons
        // [6-11] = Stick data
        // [12] = Vibrator
        // [13] = ACK byte (0x80 = success, others = specific response)
        // [14] = Subcommand ID being replied to
        // [15+] = Reply data

        let ack = data[13]
        let subcmdID = data[14]
        let replyData = data.count > 15 ? Array(data[15..<min(25, data.count)]) : []
        let replyHex = replyData.map { String(format: "%02X", $0) }.joined(separator: " ")

        let ackStr = (ack & 0x80) != 0 ? "ACK" : "NAK"
        DebugLogger.shared.log("RX: \(ackStr) subcmd=0x\(String(format: "%02X", subcmdID)) reply=[\(replyHex)]", category: .hid)

        if let pendingID = pendingSubcommandID, subcmdID == pendingID {
            pendingSubcommandID = nil
            let continuation = pendingSubcommandContinuation
            pendingSubcommandContinuation = nil
            pendingSubcommandTimeoutTask?.cancel()
            pendingSubcommandTimeoutTask = nil
            continuation?.resume(returning: data)
        }
    }

    private func processStandardInput(_ data: [UInt8]) {
        guard data.count >= 12 else { return }

        // Parse battery
        let (level, charging) = InputReportParser.parseBattery(from: data)
        joyConState.batteryLevel = level
        joyConState.isCharging = charging

        // Parse buttons (offset 3)
        joyConState.buttons = InputReportParser.parseButtons(from: data, offset: 3)

        // Parse stick (offset 6 for Joy-Con R)
        let (stickX, stickY) = InputReportParser.parseStick(from: data, offset: 6)
        joyConState.stickX = stickX
        joyConState.stickY = stickY
    }

    private var mcuReportCount = 0
    private var lastFlexByte: UInt8 = 0x0A  // Neutral position
    private var ringConMissedCount = 0
    private var ringConMissedThreshold: Int { Constants.ringConMissedThreshold }
    private var ringConPresentCount = 0
    private var ringConPresentThreshold: Int { Constants.ringConPresentThreshold }
    private var ringConRecoveryTask: Task<Void, Never>?
    private var lastIMUTimestamp = Date()
    private var filteredAcceleration = Vector3.zero
    private var filteredGyro = Vector3.zero
    private let accelFilterFactor = 0.12
    private let gyroFilterFactor = 0.2
    private let gyroDeadband = 0.6
    private let yawDeadband = 12.0
    private let yawRestAccelTolerance = 1.5
    private var yawRestSamples = 0
    private let yawRestSampleTarget = 30
    private var pitchRestOffset = 0.0
    private var rollRestOffset = 0.0
    private var pitchRollRestSamples = 0
    private let pitchRollRestSampleTarget = 15
    private var sensorCalAccel = Vector3.zero
    private var sensorCalGyro = Vector3.zero
    private var accCalCoeff = Vector3(x: 4.0 * 9.8 / 16384.0, y: 4.0 * 9.8 / 16384.0, z: 4.0 * 9.8 / 16384.0)
    private var gyroCalCoeff = Vector3(x: (.pi / 180.0) / 16.4, y: (.pi / 180.0) / 16.4, z: (.pi / 180.0) / 16.4)
    private let gyroOutputScale = 0.1
    private var gyroBias = Vector3.zero
    private var gyroBiasAccum = Vector3.zero
    private var gyroBiasSamples = 0
    private let gyroBiasSampleTarget = 80
    private let gyroBiasUpdateThreshold = 2.5
    private let gyroBiasUpdateAlpha = 0.2
    private var lastStableGyro = Vector3.zero
    private var stableGyroSamples = 0
    private var stableGyroSampleTarget: Int { Constants.stableGyroSampleTarget }
    private var stableGyroThreshold: Double { Constants.stableGyroThreshold }
    private var imuLogCounter = 0
    private var pendingSubcommandID: UInt8?
    private var pendingSubcommandContinuation: CheckedContinuation<[UInt8], Error>?
    private var pendingSubcommandTimeoutTask: Task<Void, Never>?

    private func processMCUInput(_ data: [UInt8]) {
        mcuReportCount += 1

        // IMPORTANT: Only look for Ring-Con data AFTER MCU is fully initialized
        // Before init, byte 40 contains IMU data which sometimes falls in 0x00-0x14 range
        guard mcuInitialized else {
            if mcuReportCount <= 5 {
                DebugLogger.shared.log("Ignoring MCU report - MCU not yet initialized", category: .mcu)
            }
            return
        }

        // RING-CON DATA LAYOUT (in 0x30 reports after MCU Ring-Con init):
        // Byte 40: flex sensor value (0x00 = full pull, 0x0A = neutral, 0x14 = full squeeze)
        // Byte 42: Ring-Con presence indicator (0x20 = attached, 0x00 = not attached)
        // NOTE: Byte 40 = 0x00 both when fully pulled AND when Ring-Con is absent,
        //       so byte 42 is the only reliable way to detect physical presence.
        guard data.count >= 43 else {
            if mcuReportCount <= 10 {
                DebugLogger.shared.log("MCU report too short: \(data.count) bytes", category: .mcu)
            }
            return
        }

        updateIMU(from: data)

        // Log first few reports after init for debugging
        if mcuReportCount <= 5 {
            let relevantBytes = Array(data[35..<min(50, data.count)])
            let hex = relevantBytes.map { String(format: "%02X", $0) }.joined(separator: " ")
            DebugLogger.shared.log("Bytes [35-49]: \(hex) | byte40=0x\(String(format: "%02X", data[40])) byte42=0x\(String(format: "%02X", data[42]))", category: .mcu)
        }

        let ringConByte = data[40]
        let ringConPresent = data[42] == 0x20

        if ringConPresent {
            ringConMissedCount = 0

            if !ringConAttached {
                ringConPresentCount += 1
                if ringConPresentCount >= ringConPresentThreshold {
                    ringConAttached = true
                    ringConPresentCount = 0
                    ringConRecoveryTask?.cancel()
                    ringConRecoveryTask = nil
                    lastError = nil
                    joyConState.mcuState = .ringConMode
                    DebugLogger.shared.log("Ring-Con DETECTED! flex=0x\(String(format: "%02X", ringConByte)) (\(ringConByte)) presence=0x\(String(format: "%02X", data[42]))", category: .ringcon)
                }
            }

            updateFlexByte(ringConByte)
        } else {
            ringConPresentCount = 0

            if ringConAttached {
                ringConMissedCount += 1
                if ringConMissedCount >= ringConMissedThreshold {
                    ringConAttached = false
                    DebugLogger.shared.log("Ring-Con DETACHED (byte 42 != 0x20 for \(ringConMissedThreshold) consecutive reports)", category: .ringcon)
                    ringConMissedCount = 0
                    scheduleRingConRecovery()
                }
            }
            // Log periodically when Ring-Con not detected
            if mcuReportCount % 500 == 0 {
                DebugLogger.shared.log("Ring-Con absent: byte40=0x\(String(format: "%02X", ringConByte)) byte42=0x\(String(format: "%02X", data[42]))", category: .mcu)
            }
        }
    }

    private func updateFlexByte(_ flexByte: UInt8) {
        let oldByte = lastFlexByte
        lastFlexByte = flexByte

        if neutralFlexByte == nil {
            neutralFlexByte = flexByte
            DebugLogger.shared.log("Ring-Con neutral set to 0x\(String(format: "%02X", flexByte)) (\(flexByte))", category: .ringcon)
        }

        // Convert to UInt16 for compatibility with existing state
        let rawFlex = UInt16(flexByte)
        joyConState.flexState.rawValue = rawFlex
        DebugLogger.shared.lastRawFlexValue = rawFlex

        // During calibration, track min/max based on current phase
        if calibrationInProgress {
            switch calibrationPhase {
            case .pull:
                minFlexValue = min(minFlexValue, rawFlex)
            case .squeeze:
                maxFlexValue = max(maxFlexValue, rawFlex)
            default:
                break
            }
        }

        // Normalize using calibration (if available) to better match per-device range
        let neutral = Double(hasCalibration ? neutralFlexValue : UInt16(neutralFlexByte ?? 0x0A))
        let minRange = Double(hasCalibration ? minFlexValue : 0x00)
        let maxRange = Double(hasCalibration ? maxFlexValue : 0x14)
        let raw = Double(flexByte)
        let normalized: Double
        if raw >= neutral {
            let range = maxRange - neutral
            normalized = range > 0 ? 0.5 + ((raw - neutral) / range) * 0.5 : 0.5
        } else {
            let range = neutral - minRange
            normalized = range > 0 ? 0.5 - ((neutral - raw) / range) * 0.5 : 0.5
        }
        flexValue = min(max(normalized, 0.0), 1.0)

        // Log changes (but not every single one - only significant changes)
        if oldByte != flexByte {
            DebugLogger.shared.log("Flex: 0x\(String(format: "%02X", flexByte)) (\(flexByte)) -> \(String(format: "%.1f%%", flexValue * 100))", category: .ringcon)
        }
    }

    private func updateIMU(from data: [UInt8]) {
        guard data.count >= 49 else { return }

        func rawVector(start: Int) -> Vector3 {
            Vector3(
                x: Double(Int16(bitPattern: UInt16(data[start]) | (UInt16(data[start + 1]) << 8))),
                y: Double(Int16(bitPattern: UInt16(data[start + 2]) | (UInt16(data[start + 3]) << 8))),
                z: Double(Int16(bitPattern: UInt16(data[start + 4]) | (UInt16(data[start + 5]) << 8)))
            )
        }

        let accelRaw = averageVectors([rawVector(start: 13), rawVector(start: 25)])
        let yawRaw = Double(Int16(bitPattern: UInt16(data[33]) | (UInt16(data[34]) << 8)))
        let gyroRaw = Vector3(x: 0, y: 0, z: yawRaw)
        let calibrated = IMUReading(acceleration: calibrateAccel(accelRaw), angularVelocity: calibrateGyro(gyroRaw))
        imuReading = calibrated

        let unbiasedGyro = applyGyroBias(calibrated.angularVelocity)
        filteredAcceleration = blend(filteredAcceleration, calibrated.acceleration, alpha: accelFilterFactor)
        filteredGyro = blend(filteredGyro, unbiasedGyro, alpha: gyroFilterFactor)

        let smoothedAccel = filteredAcceleration
        let smoothedGyro = filteredGyro

        imuReading = IMUReading(acceleration: smoothedAccel, angularVelocity: smoothedGyro)
        angularVelocityMagnitude = smoothedGyro.magnitude
        DebugLogger.shared.lastAngularVelocityMagnitude = angularVelocityMagnitude

        let pitch = atan2(smoothedAccel.y, sqrt(smoothedAccel.x * smoothedAccel.x + smoothedAccel.z * smoothedAccel.z)) * 180.0 / .pi + 90.0
        let roll = atan2(-smoothedAccel.x, smoothedAccel.z) * 180.0 / .pi + 180.0

        let now = Date()
        var deltaTime = now.timeIntervalSince(lastIMUTimestamp)
        if deltaTime > 0.5 {
            deltaTime = 0
        }
        lastIMUTimestamp = now
        let isResting = smoothedGyro.magnitude < yawDeadband
            && abs(smoothedGyro.z) < yawDeadband
            && abs(smoothedAccel.magnitude - 9.8) < yawRestAccelTolerance
        if isResting {
            yawRestSamples += 1
        } else {
            yawRestSamples = 0
        }

        if yawRestSamples >= yawRestSampleTarget {
            orientation = Orientation(pitch: pitch - pitchRestOffset, roll: normalizeAngle(roll - rollRestOffset), yaw: 0)
        } else {
            let gyroZ = abs(smoothedGyro.z) < yawDeadband ? 0 : smoothedGyro.z
            let yaw = normalizeAngle(orientation.yaw + gyroZ * deltaTime)
            orientation = Orientation(pitch: pitch - pitchRestOffset, roll: normalizeAngle(roll - rollRestOffset), yaw: yaw)
        }

        if isResting {
            pitchRollRestSamples += 1
            if pitchRollRestSamples >= pitchRollRestSampleTarget {
                pitchRestOffset = pitch
                rollRestOffset = roll
            }
        } else {
            pitchRollRestSamples = 0
        }

        imuLogCounter += 1
        if imuLogCounter % 200 == 0 {
            DebugLogger.shared.log("IMU gyro mag \(String(format: "%.1f", angularVelocityMagnitude))", category: .mcu)
        }
    }

    private func calibrateIMU(accel: Vector3, gyro: Vector3) -> IMUReading {
        IMUReading(acceleration: calibrateAccel(accel), angularVelocity: calibrateGyro(gyro))
    }

    private func calibrateAccel(_ accel: Vector3) -> Vector3 {
        Vector3(
            x: (accel.x - sensorCalAccel.x) * accCalCoeff.x,
            y: (accel.y - sensorCalAccel.y) * accCalCoeff.y,
            z: (accel.z - sensorCalAccel.z) * accCalCoeff.z
        )
    }

    private func calibrateGyro(_ gyro: Vector3) -> Vector3 {
        let gyroRadians = Vector3(
            x: (gyro.x - sensorCalGyro.x) * gyroCalCoeff.x,
            y: (gyro.y - sensorCalGyro.y) * gyroCalCoeff.y,
            z: (gyro.z - sensorCalGyro.z) * gyroCalCoeff.z
        )
        return Vector3(
            x: gyroRadians.x * 180.0 / .pi * gyroOutputScale,
            y: gyroRadians.y * 180.0 / .pi * gyroOutputScale,
            z: gyroRadians.z * 180.0 / .pi * gyroOutputScale
        )
    }

    private func averageVectors(_ vectors: [Vector3]) -> Vector3 {
        guard !vectors.isEmpty else { return .zero }
        let count = Double(vectors.count)
        let sums = vectors.reduce(Vector3.zero) { result, vector in
            Vector3(x: result.x + vector.x, y: result.y + vector.y, z: result.z + vector.z)
        }
        return Vector3(x: sums.x / count, y: sums.y / count, z: sums.z / count)
    }

    private func applyGyroBias(_ rawGyro: Vector3) -> Vector3 {
        if gyroBiasSamples < gyroBiasSampleTarget {
            gyroBiasAccum = Vector3(
                x: gyroBiasAccum.x + rawGyro.x,
                y: gyroBiasAccum.y + rawGyro.y,
                z: gyroBiasAccum.z + rawGyro.z
            )
            gyroBiasSamples += 1
            let samples = Double(gyroBiasSamples)
            gyroBias = Vector3(
                x: gyroBiasAccum.x / samples,
                y: gyroBiasAccum.y / samples,
                z: gyroBiasAccum.z / samples
            )
        }

        if lastStableGyro == .zero {
            lastStableGyro = rawGyro
            stableGyroSamples = 0
        }

        let delta = Vector3(
            x: rawGyro.x - lastStableGyro.x,
            y: rawGyro.y - lastStableGyro.y,
            z: rawGyro.z - lastStableGyro.z
        )

        if delta.magnitude < stableGyroThreshold {
            stableGyroSamples += 1
        } else {
            stableGyroSamples = 0
            lastStableGyro = rawGyro
        }

        if stableGyroSamples >= stableGyroSampleTarget || rawGyro.magnitude < gyroBiasUpdateThreshold {
            gyroBias = blend(gyroBias, rawGyro, alpha: gyroBiasUpdateAlpha)
        }

        return Vector3(
            x: rawGyro.x - gyroBias.x,
            y: rawGyro.y - gyroBias.y,
            z: rawGyro.z - gyroBias.z
        )
    }

    private func blend(_ current: Vector3, _ target: Vector3, alpha: Double) -> Vector3 {
        Vector3(
            x: current.x + (target.x - current.x) * alpha,
            y: current.y + (target.y - current.y) * alpha,
            z: current.z + (target.z - current.z) * alpha
        )
    }

    private func normalizeAngle(_ angle: Double) -> Double {
        var value = angle
        while value > 180 { value -= 360 }
        while value < -180 { value += 360 }
        return value
    }

    private func loadIMUCalibration() async throws {
        if let user = try await readSensorCalibration(offset: 0x8026, length: 0x1A),
           (UInt16(user[0]) | (UInt16(user[1]) << 8)) == 0xA1B2 {
            applySensorCalibration(from: user, isUser: true)
            return
        }

        if let factory = try await readSensorCalibration(offset: 0x6020, length: 0x18) {
            applySensorCalibration(from: factory, isUser: false)
        }
    }

    private func applySensorCalibration(from data: [UInt8], isUser: Bool) {
        func int16(at index: Int) -> Int16 {
            let value = UInt16(data[index]) | (UInt16(data[index + 1]) << 8)
            return Int16(bitPattern: value)
        }

        let accelIndex = isUser ? 2 : 0
        let gyroIndex = isUser ? 0x0E : 0x0C

        guard data.count > gyroIndex + 5 else { return }

        sensorCalAccel = Vector3(
            x: Double(int16(at: accelIndex)),
            y: Double(int16(at: accelIndex + 2)),
            z: Double(int16(at: accelIndex + 4))
        )
        sensorCalGyro = Vector3(
            x: Double(int16(at: gyroIndex)),
            y: Double(int16(at: gyroIndex + 2)),
            z: Double(int16(at: gyroIndex + 4))
        )

        let denomX = 13371.0 - Double(int16(at: gyroIndex))
        let denomY = 13371.0 - Double(int16(at: gyroIndex + 2))
        let denomZ = 13371.0 - Double(int16(at: gyroIndex + 4))
        gyroCalCoeff = Vector3(
            x: (936.0 / denomX) * (.pi / 180.0),
            y: (936.0 / denomY) * (.pi / 180.0),
            z: (936.0 / denomZ) * (.pi / 180.0)
        )

        let accDenomX = 16384.0 - Double(int16(at: accelIndex))
        let accDenomY = 16384.0 - Double(int16(at: accelIndex + 2))
        let accDenomZ = 16384.0 - Double(int16(at: accelIndex + 4))
        accCalCoeff = Vector3(
            x: (1.0 / accDenomX) * 4.0 * 9.8,
            y: (1.0 / accDenomY) * 4.0 * 9.8,
            z: (1.0 / accDenomZ) * 4.0 * 9.8
        )
    }

    private func readSensorCalibration(offset: UInt32, length: Int) async throws -> [UInt8]? {
        guard let response = try await sendSubcommandAndWait(.spiFlashRead, argument: spiReadArgument(offset: offset, length: length), expected: .spiFlashRead) else {
            return nil
        }
        guard response.count >= 0x14 + length else { return nil }
        return Array(response[0x14..<(0x14 + length)])
    }

    private func spiReadArgument(offset: UInt32, length: Int) -> [UInt8] {
        [
            UInt8(offset & 0xFF),
            UInt8((offset >> 8) & 0xFF),
            UInt8((offset >> 16) & 0xFF),
            UInt8((offset >> 24) & 0xFF),
            UInt8(length & 0xFF)
        ]
    }

    private func sendSubcommandAndWait(_ subcommand: Subcommand, argument: [UInt8], expected: Subcommand) async throws -> [UInt8]? {
        guard pendingSubcommandID == nil else { return nil }
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[UInt8], Error>) in
            pendingSubcommandID = expected.rawValue
            pendingSubcommandContinuation = continuation
            pendingSubcommandTimeoutTask?.cancel()
            pendingSubcommandTimeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 200_000_000)
                guard let self = self, self.pendingSubcommandID == expected.rawValue else { return }
                self.pendingSubcommandID = nil
                let pending = self.pendingSubcommandContinuation
                self.pendingSubcommandContinuation = nil
                pending?.resume(throwing: JoyConHIDError.timeout)
            }

            Task { @MainActor in
                _ = try? await self.hid.sendSubcommand(subcommand, argument: argument)
            }
        }
    }
}

// MARK: - JoyConHIDDelegate

extension RingConManager: JoyConHIDDelegate {
    nonisolated func joyConHID(_ hid: JoyConHID, didReceiveInputReport data: [UInt8]) {
        Task { @MainActor [weak self] in
            self?.processInputReport(data)
        }
    }

    nonisolated func joyConHID(_ hid: JoyConHID, didDisconnect error: Error?) {
        Task { @MainActor [weak self] in
            self?.cancelCalibration()
            self?.connectionState = .disconnected
            self?.ringConAttached = false
            self?.mcuInitialized = false

            if let error = error {
                self?.lastError = error.localizedDescription
            }
        }
    }
}

// MARK: - Bluetooth State Delegate

/// Delegate to monitor Bluetooth state changes (permission, power on/off)
class BluetoothPermissionDelegate: NSObject, CBCentralManagerDelegate {
    private let onStateChange: () -> Void

    init(onStateChange: @escaping () -> Void) {
        self.onStateChange = onStateChange
        super.init()
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        // Called when Bluetooth state changes (power on/off, permission granted/denied)
        // States: .poweredOn, .poweredOff, .unauthorized, .unsupported, .resetting, .unknown
        self.onStateChange()
    }
}
