import Combine
import CoreBluetooth
import Foundation
import IOBluetooth

// MARK: - 模型

enum LinkTransport: String {
    case rfcomm        // 经典蓝牙 RFCOMM/SPP（Ceramics MK2 走的这条）
    case ble           // BLE GATT

    var title: String {
        switch self {
        case .rfcomm: return "经典蓝牙"
        case .ble: return "低功耗蓝牙"
        }
    }
}

struct DiscoveredDevice: Identifiable, Hashable {
    let id: String
    let name: String
    let rssi: Int?
    let family: ProtocolFamily?
    let transport: LinkTransport

    var displayName: String { name.isEmpty ? "未命名设备" : name }
}

struct FrameLogEntry: Identifiable, Hashable {
    enum Direction { case outbound, inbound }

    let id = UUID()
    let date = Date()
    let direction: Direction
    let bytes: [UInt8]
    let note: String?

    var hex: String {
        bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}

struct DeviceState {
    /// 电量：`0x0C` 回包依次是左耳、右耳、充电仓（实测 MK2 为 55 / 53 / 0）。
    var batteryLeft: Int?
    var batteryRight: Int?
    /// 耳机仓电量。耳机出仓后设备不再上报（字节为 0），这里保留上一次的有效值，
    /// 配合 `batteryCaseUpdatedAt` 标明数据新鲜度——官方 App 也是这个做法。
    var batteryCase: Int?
    var batteryCaseUpdatedAt: Date?

    var noiseMode: NoiseMode?
    var ancLevel: Int?
    var transparencyLevel: Int?
    var eq: EQPreset?
    var gameMode: Bool?
    var dualDevice: Bool?
    var earDetection: Bool?
    var touchControl: Bool?
    var spatialMediaMode: SpatialMediaMode?
    var codec: AudioCodec?
    var interfaceLanguage: InterfaceLanguage?
    var dingLevel: Int?
    var firmware: String?

    /// 主显示电量取左右耳中较高的那个。
    var battery: Int? {
        [batteryLeft, batteryRight].compactMap { $0 }.max()
    }

    /// 按用户选择的来源取电量；缺失时返回 nil，由调用方决定怎么展示。
    func battery(for source: BatterySource) -> Int? {
        let ears = [batteryLeft, batteryRight].compactMap { $0 }
        switch source {
        case .left:
            return batteryLeft
        case .right:
            return batteryRight
        case .chargingCase:
            return batteryCase
        case .highest:
            return ears.max()
        case .lowest:
            return ears.min()
        case .average:
            guard !ears.isEmpty else { return nil }
            return Int((Double(ears.reduce(0, +)) / Double(ears.count)).rounded())
        }
    }
}

enum ConnectionPhase: Equatable {
    case poweredOff
    case unauthorized
    case idle
    case scanning
    case connecting(String)
    case discovering(String)
    case ready(String)
    case failed(String)

    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    var summary: String {
        switch self {
        case .poweredOff: return "蓝牙已关闭"
        case .unauthorized: return "未授权访问蓝牙"
        case .idle: return "未连接"
        case .scanning: return "正在搜索附近的耳机…"
        case .connecting(let name): return "正在连接 \(name)…"
        case .discovering(let name): return "正在打开 \(name) 的控制通道…"
        case .ready(let name): return "已连接 \(name)"
        case .failed(let reason): return reason
        }
    }

    var deviceName: String? {
        switch self {
        case .ready(let name), .connecting(let name), .discovering(let name): return name
        default: return nil
        }
    }
}

// MARK: - 引擎

/// 同时支持经典 RFCOMM（SPP）与 BLE GATT 两种承载。
///
/// Ceramics MK2 实测走经典蓝牙的 RFCOMM 服务通道 6——APK 里的
/// `connector/spp_client.dart` 正是这条路径，BLE 只是备选。
final class BluetoothEngine: NSObject, ObservableObject {

    static let candidateServices: [CBUUID] = [
        CBUUID(string: "0CF12D31-FAC3-4553-BD80-D6832E7B3931"),
        CBUUID(string: "0CF12D32-FAC3-4553-BD80-D6832E7B3931"),
        CBUUID(string: "0000AE00-0000-1000-8000-00805F9B34FB"),
        CBUUID(string: "00007034-0000-1000-8000-00805F9B34FB"),
        CBUUID(string: "66666666-6666-6666-6666-666666666666"),
    ]

    @Published private(set) var devices: [DiscoveredDevice] = []
    @Published private(set) var phase: ConnectionPhase = .idle
    @Published private(set) var state = DeviceState()
    @Published private(set) var log: [FrameLogEntry] = []
    @Published private(set) var activeFamily: ProtocolFamily = .rsCommonV2
    @Published private(set) var activeTransport: LinkTransport = .rfcomm

    var preferredFamily: ProtocolFamily = .auto {
        didSet { if preferredFamily != .auto { activeFamily = preferredFamily } }
    }

    // BLE
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var txCharacteristic: CBCharacteristic?
    private var rxCharacteristic: CBCharacteristic?
    private var knownPeripherals: [String: CBPeripheral] = [:]

    // 经典蓝牙
    private var classicDevice: IOBluetoothDevice?
    private var rfcommChannel: IOBluetoothRFCOMMChannel?
    private var classicDevices: [String: IOBluetoothDevice] = [:]
    /// IOBluetooth 的若干 API 是同步阻塞的，统一丢到这个队列。
    private let classicQueue = DispatchQueue(label: "ai.roselink.classic", qos: .userInitiated)
    /// 控制通道打开的重试计数（耳机侧释放会话需要一点时间）。
    private var channelOpenAttempts = 0
    /// 当前设备标识，用来把仓电量缓存按设备分开存。
    private var currentDeviceKey: String?

    private var stream = FrameStream(family: .rsCommonV2)
    private var sequence: UInt8 = 0
    private var pendingScan = false
    private var didRestore = false
    private let maxLogEntries = 400

    private enum Keys {
        static let lastDeviceID = "lastDeviceID"
        static let lastDeviceName = "lastDeviceName"
        static let autoConnect = "autoConnectOnLaunch"
    }

    override init() {
        super.init()
        UserDefaults.standard.register(defaults: [Keys.autoConnect: true])
        central = CBCentralManager(delegate: self, queue: .main)
    }

    var isPoweredOn: Bool { central?.state == .poweredOn }

    // MARK: 搜索

    func startScan() {
        refreshPairedDevices()

        guard central.state == .poweredOn else {
            pendingScan = true
            return
        }
        guard !phase.isReady else { return }
        central.stopScan()
        knownPeripherals.removeAll()
        phase = .scanning
        central.scanForPeripherals(withServices: nil, options: nil)
    }

    /// 经典蓝牙不需要扫描：已配对设备直接可用（控制通道要配对后才存在）。
    /// 启动时调用一次即可填满列表，不必触发 BLE 扫描。
    func refreshPairedDevices() {
        classicDevices.removeAll()
        let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []

        var result = devices.filter { $0.transport == .ble }
        for device in paired {
            guard let name = device.name, DeviceRegistry.looksLikeRoseDevice(name) else { continue }
            let id = device.addressString ?? name
            classicDevices[id] = device
            result.append(
                DiscoveredDevice(
                    id: id,
                    name: name,
                    rssi: nil,
                    family: DeviceRegistry.family(for: name),
                    transport: .rfcomm
                )
            )
        }
        devices = result
    }

    // MARK: 连接

    func connect(_ device: DiscoveredDevice) {
        remember(device)
        currentDeviceKey = device.id
        switch device.transport {
        case .rfcomm:
            connectClassic(device)
        case .ble:
            connectBLE(device)
        }
    }

    /// 启动时恢复上一次的连接。
    func restoreLastConnection() {
        guard !didRestore else { return }
        didRestore = true

        refreshPairedDevices()

        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: Keys.autoConnect) else { return }
        let savedID = defaults.string(forKey: Keys.lastDeviceID)
        let savedName = defaults.string(forKey: Keys.lastDeviceName)
        let target = devices.first { $0.id == savedID }
            ?? devices.first { $0.name == savedName && !$0.name.isEmpty }
        guard let target else { return }
        connect(target)
    }

    private func remember(_ device: DiscoveredDevice) {
        let defaults = UserDefaults.standard
        defaults.set(device.id, forKey: Keys.lastDeviceID)
        defaults.set(device.name, forKey: Keys.lastDeviceName)
    }

    private func connectClassic(_ device: DiscoveredDevice) {
        guard let target = classicDevices[device.id] else {
            phase = .failed("设备未配对，请先在「系统设置 › 蓝牙」中配对")
            return
        }
        central.stopScan()
        teardown()

        classicDevice = target
        channelOpenAttempts = 0
        activeTransport = .rfcomm
        activeFamily = preferredFamily == .auto ? (device.family ?? .rsCommonV2) : preferredFamily
        phase = .connecting(device.displayName)
        openClassicChannel()
    }

    /// 建立经典蓝牙连接并打开控制通道。
    ///
    /// `IOBluetoothDevice.openConnection()` 是**同步阻塞**的（内部靠信号量等待
    /// 底座链路建立），一旦放在主线程上，整个 App 会被冻住——窗口和菜单栏都
    /// 来不及创建，用户看到的就是「卡死」。设备已连接时它立即返回，所以只有
    /// 换路径 / 蓝牙授权变更导致需要重新寻呼时才会暴露。
    ///
    /// 处理方式：只有这一步丢到 `classicQueue`；SDP 查询和 RFCOMM 打开仍留在
    /// 主线程——SDP 的回包要靠主 runloop 处理，挪到没有 runloop 的后台线程会
    /// 永久挂住（已实测）。
    private func openClassicChannel() {
        guard let device = classicDevice else { return }
        let name = device.name ?? "耳机"

        if device.isConnected() {
            finishOpeningChannel(on: device)
            return
        }

        phase = .connecting(name)
        let deviceRef = device
        classicQueue.async { [weak self] in
            _ = deviceRef.openConnection()   // 阻塞，但不在主线程

            var waited = 0.0
            while !deviceRef.isConnected() && waited < 6.0 {
                Thread.sleep(forTimeInterval: 0.25)
                waited += 0.25
            }
            let connected = deviceRef.isConnected()

            DispatchQueue.main.async {
                guard let self else { return }
                if connected {
                    self.finishOpeningChannel(on: deviceRef)
                } else {
                    self.phase = .failed("无法建立经典蓝牙连接，请确认耳机已开机并与本机配对")
                }
            }
        }
    }

    private func finishOpeningChannel(on device: IOBluetoothDevice) {
        phase = .discovering(device.name ?? "耳机")
        let channelID = Self.controlChannelID(for: device)

        var channel: IOBluetoothRFCOMMChannel?
        let result = device.openRFCOMMChannelSync(&channel, withChannelID: channelID, delegate: self)
        guard result == kIOReturnSuccess, let channel else {
            // 上一次会话可能还没被耳机侧释放（退出后立刻重开会命中），稍等重试。
            channelOpenAttempts += 1
            if channelOpenAttempts < 3 {
                phase = .discovering(device.name ?? "耳机")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                    guard let self, self.classicDevice === device else { return }
                    self.finishOpeningChannel(on: device)
                }
            } else {
                channelOpenAttempts = 0
                phase = .failed("打开控制通道失败（0x\(String(result, radix: 16))）")
            }
            return
        }

        channelOpenAttempts = 0
        rfcommChannel = channel
        stream = FrameStream(family: activeFamily)
        sequence = 0
        phase = .ready(device.name ?? "耳机")
        restoreCachedCaseBattery()
        if let poll = CommandSet.profile(for: activeFamily).pollAll() {
            send(poll, note: "查询设备状态")
        }
    }

    // MARK: 仓电量缓存

    /// 耳机出仓后设备不再上报仓电量，缓存最近一次有效值以便下次连接直接展示。
    private func cacheCaseBattery(_ level: Int) {
        guard let key = currentDeviceKey else { return }
        let defaults = UserDefaults.standard
        defaults.set(level, forKey: "caseBatteryValue.\(key)")
        defaults.set(Date().timeIntervalSince1970, forKey: "caseBatteryTime.\(key)")
    }

    private func restoreCachedCaseBattery() {
        guard let key = currentDeviceKey else { return }
        let defaults = UserDefaults.standard
        let level = defaults.integer(forKey: "caseBatteryValue.\(key)")
        let stamp = defaults.double(forKey: "caseBatteryTime.\(key)")
        guard (1...100).contains(level), stamp > 0 else { return }
        state.batteryCase = level
        state.batteryCaseUpdatedAt = Date(timeIntervalSince1970: stamp)
    }

    /// APK 里 SPP 控制通道的 DLCI 是 12，对应 RFCOMM 服务通道 6。
    private static func controlChannelID(for device: IOBluetoothDevice) -> BluetoothRFCOMMChannelID {
        let records = device.services as? [IOBluetoothSDPServiceRecord] ?? []
        var candidates: [BluetoothRFCOMMChannelID] = []
        for record in records {
            var channel: BluetoothRFCOMMChannelID = 0
            if record.getRFCOMMChannelID(&channel) == kIOReturnSuccess {
                candidates.append(channel)
            }
        }
        if candidates.contains(6) { return 6 }
        // 退回到「不是 HFP(2) / 也不是标准 SPP(1)」的那条，再不行就试 6。
        return candidates.first { $0 != 1 && $0 != 2 } ?? 6
    }

    private func connectBLE(_ device: DiscoveredDevice) {
        guard let target = knownPeripherals[device.id] else {
            phase = .failed("设备已离开范围，请重新搜索")
            return
        }
        central.stopScan()
        teardown()
        activeTransport = .ble
        activeFamily = preferredFamily == .auto ? (device.family ?? .rsCommonV2) : preferredFamily
        peripheral = target
        target.delegate = self
        phase = .connecting(device.displayName)
        central.connect(target, options: nil)
    }

    func disconnect() {
        if let peripheral, peripheral.state != .disconnected {
            central.cancelPeripheralConnection(peripheral)
        }
        teardown()
        if case .ready = phase { phase = .idle }
    }

    // MARK: 发送

    func send(_ payload: [UInt8], note: String? = nil) {
        let family = activeFamily == .auto ? .rsCommonV2 : activeFamily
        let frame = FrameCodec.encode(payload: payload, family: family, sequence: sequence)
        sequence = sequence &+ 1

        appendLog(.outbound, Array(frame), note: note)

        switch activeTransport {
        case .rfcomm:
            guard let channel = rfcommChannel else {
                appendLog(.outbound, [], note: "控制通道未打开")
                return
            }
            frame.withUnsafeBytes { raw in
                guard let base = raw.baseAddress else { return }
                _ = channel.writeSync(
                    UnsafeMutableRawPointer(mutating: base),
                    length: UInt16(raw.count)
                )
            }

        case .ble:
            guard let peripheral, let tx = txCharacteristic else { return }
            let type: CBCharacteristicWriteType =
                tx.properties.contains(.write) ? .withResponse : .withoutResponse
            peripheral.writeValue(frame, for: tx, type: type)
        }
    }

    func send(_ payload: [UInt8]?, note: String? = nil) {
        guard let payload else { return }
        send(payload, note: note)
    }

    func clearLog() {
        log.removeAll()
    }

    // MARK: 内部

    private func teardown() {
        if let channel = rfcommChannel {
            channel.close()
        }
        rfcommChannel = nil
        classicDevice = nil

        if let peripheral {
            if let rx = rxCharacteristic, rx.isNotifying {
                peripheral.setNotifyValue(false, for: rx)
            }
            peripheral.delegate = nil
        }
        peripheral = nil
        txCharacteristic = nil
        rxCharacteristic = nil

        stream.reset()
        sequence = 0
        channelOpenAttempts = 0
        state = DeviceState()
    }

    private func appendLog(_ direction: FrameLogEntry.Direction, _ bytes: [UInt8], note: String?) {
        log.append(FrameLogEntry(direction: direction, bytes: bytes, note: note))
        if log.count > maxLogEntries {
            log.removeFirst(log.count - maxLogEntries)
        }
    }

    private func handleIncoming(_ data: [UInt8]) {
        for items in stream.append(Data(data)) {
            ingest(items)
        }
    }

    /// 解析入站 LTV 串：`len | type | value(len-1) …`
    private func ingest(_ items: [UInt8]) {
        var index = 0
        while index < items.count {
            let length = Int(items[index])
            guard length > 0, index + 1 + length <= items.count else { break }
            let type = items[index + 1]
            let value = Array(items[(index + 2)..<(index + 1 + length)])
            apply(type: type, value: value)
            index += 1 + length
        }
    }

    private func apply(type: UInt8, value: [UInt8]) {
        switch type {
        case 0x0C:
            // 左耳 / 右耳 / 充电仓
            if value.count >= 2 {
                if (1...100).contains(Int(value[0])) { state.batteryLeft = Int(value[0]) }
                if (1...100).contains(Int(value[1])) { state.batteryRight = Int(value[1]) }
            }
            // 只有拿到有效值才刷新仓电量与时间戳；上报 0 说明耳机出仓，保留上次结果。
            if value.count >= 3, (1...100).contains(Int(value[2])) {
                let caseLevel = Int(value[2])
                state.batteryCase = caseLevel
                state.batteryCaseUpdatedAt = Date()
                cacheCaseBattery(caseLevel)
            }
        case 0x09:
            state.noiseMode = [
                0x01: .anc, 0x02: .normal, 0x03: .transparency,
                0x04: .wind, 0x05: .adaptive, 0x06: .deepANC,
                0x07: .adaptiveDynamic,
            ][value.first ?? 0]
        case 0x2C:
            if let first = value.first { state.ancLevel = Int(first) }
        case 0x2D:
            if let first = value.first { state.transparencyLevel = Int(first) }
        case 0x2A:
            state.eq = [
                0x00: .hifi, 0x01: .pop, 0x02: .rock, 0x03: .light,
                0x04: .custom, 0x05: .bassBoost, 0x06: .eap,
                0xA0: .game1, 0xA1: .game2, 0xA2: .game3,
                0xA3: .game4, 0xA4: .game5,
            ][value.first ?? 0]
        case 0x0E:
            if let first = value.first { state.gameMode = first != 0 }
        case 0x32:
            if let first = value.first { state.dualDevice = first != 0 }
        case 0x08:
            if let first = value.first { state.earDetection = first == 0 }
        case 0x07:
            if let first = value.first { state.touchControl = first == 0 }
        case 0x31:
            if let first = value.first { state.interfaceLanguage = first == 1 ? .english : .chinese }
        case 0x2E:
            if let first = value.first { state.dingLevel = Int(first) }
        case 0x3D:
            if let first = value.first {
                state.spatialMediaMode = [0x00: .tv, 0x01: .music, 0x02: .movie, 0x03: .game][first]
            }
        case 0x2B:
            state.codec = [
                0x00: .sbcAac, 0x01: .ldac, 0x02: .lhdc, 0x03: .lc3,
                0x04: .aptx, 0x05: .aptxHD, 0x06: .aptxAdaptive,
            ][value.first ?? 0]
        case 0x0D:
            // 实测值为 01 06 00，按语义化版本展示。
            if value.count >= 3 {
                state.firmware = value.prefix(3).map(String.init).joined(separator: ".")
            }
        default:
            break
        }
    }
}

// MARK: - RFCOMM 回调

extension BluetoothEngine: IOBluetoothRFCOMMChannelDelegate {

    func rfcommChannelOpenComplete(_ channel: IOBluetoothRFCOMMChannel!, status error: IOReturn) {
        guard error == kIOReturnSuccess else {
            // 同步打开时这里通常已经有结果了，仅在还没就绪时上报。
            if !phase.isReady {
                phase = .failed("控制通道打开失败（0x\(String(error, radix: 16))）")
            }
            return
        }
        if rfcommChannel == nil { rfcommChannel = channel }
        // 就绪状态与首帧轮询由 finishOpeningChannel 负责，这里不重复发。
    }

    func rfcommChannelData(
        _ channel: IOBluetoothRFCOMMChannel!,
        data dataPointer: UnsafeMutableRawPointer!,
        length dataLength: Int
    ) {
        guard let dataPointer, dataLength > 0 else { return }
        let buffer = UnsafeRawBufferPointer(start: dataPointer, count: dataLength)
        let bytes = [UInt8](buffer)
        appendLog(.inbound, bytes, note: nil)
        handleIncoming(bytes)
    }

    func rfcommChannelClosed(_ channel: IOBluetoothRFCOMMChannel!) {
        rfcommChannel = nil
        if phase.isReady {
            teardown()
            phase = .failed("控制通道已关闭，请重新连接")
        }
    }
}

// MARK: - BLE 回调

extension BluetoothEngine: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            if pendingScan {
                pendingScan = false
                startScan()
            }
        case .poweredOff:
            phase = .poweredOff
        case .unauthorized:
            phase = .unauthorized
        default:
            break
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let advertised = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let name = advertised ?? peripheral.name ?? ""
        let family = DeviceRegistry.family(for: name) ?? DeviceRegistry.family(for: peripheral.name)

        let advertisedServices = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        let matchesService = advertisedServices.contains { uuid in
            Self.candidateServices.contains {
                $0.uuidString.caseInsensitiveCompare(uuid.uuidString) == .orderedSame
            }
        }
        guard DeviceRegistry.looksLikeRoseDevice(name) || family != nil || matchesService else { return }

        let id = peripheral.identifier.uuidString
        knownPeripherals[id] = peripheral

        let device = DiscoveredDevice(
            id: id,
            name: name.isEmpty ? (peripheral.name ?? "") : name,
            rssi: RSSI.intValue,
            family: family,
            transport: .ble
        )
        if let index = devices.firstIndex(where: { $0.id == id }) {
            devices[index] = device
        } else {
            devices.append(device)
            devices.sort { ($0.rssi ?? -999) > ($1.rssi ?? -999) }
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        phase = .discovering(peripheral.name ?? "耳机")
        peripheral.discoverServices(nil)
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        teardown()
        phase = .failed("连接失败：\(error?.localizedDescription ?? "未知原因")")
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        let wasReady = phase.isReady
        teardown()
        if let error {
            phase = .failed("连接已断开：\(error.localizedDescription)")
        } else if wasReady {
            phase = .idle
        }
    }
}

extension BluetoothEngine: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil, let services = peripheral.services, !services.isEmpty else {
            phase = .failed("未找到可用的 BLE 服务")
            return
        }
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        guard error == nil, let characteristics = service.characteristics else { return }
        guard txCharacteristic == nil else { return }

        let writable = characteristics.filter {
            $0.properties.contains(.write) || $0.properties.contains(.writeWithoutResponse)
        }
        let notifiable = characteristics.filter {
            $0.properties.contains(.notify) || $0.properties.contains(.indicate)
        }
        guard !writable.isEmpty, !notifiable.isEmpty else { return }

        let tx = writable.first { $0.properties.contains(.write) } ?? writable[0]
        let rx = notifiable.first { $0.properties.contains(.notify) } ?? notifiable[0]
        txCharacteristic = tx
        rxCharacteristic = rx
        peripheral.setNotifyValue(true, for: rx)
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard error == nil, characteristic.isNotifying else { return }
        stream = FrameStream(family: activeFamily)
        phase = .ready(peripheral.name ?? "耳机")
        restoreCachedCaseBattery()
        if let poll = CommandSet.profile(for: activeFamily).pollAll() {
            send(poll, note: "查询设备状态")
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard error == nil, let data = characteristic.value else { return }
        appendLog(.inbound, Array(data), note: nil)
        handleIncoming(Array(data))
    }
}
