import Foundation

/// Minimal MQTT 5 client for the Urban Company wake-up channel.
/// It only subscribes to the per-user refresh topic and reports each publish.
final class UrbanMQTT {
    var onWake: (() -> Void)?
    var onState: ((String) -> Void)?

    private let token: String
    private let userId: String
    private let url = URL(string: "wss://emqx-listen.urbancompany.com:8084/mqtt")!
    private let clientId: String
    private let session: URLSession

    private var running: Task<Void, Never>?
    private var pingTask: Task<Void, Never>?
    private var task: URLSessionWebSocketTask?
    private var buffer = Data()

    init(token: String, userId: String) {
        self.token = token
        self.userId = userId
        self.clientId = "socket-client-\(userId)-" + String(format: "%08x", UInt32.random(in: 0...UInt32.max))
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15
        configuration.waitsForConnectivity = true
        self.session = URLSession(configuration: configuration)
    }

    func start() {
        guard running == nil else { return }
        running = Task { [weak self] in await self?.runLoop() }
    }

    func stop() {
        running?.cancel()
        pingTask?.cancel()
        task?.cancel(with: .goingAway, reason: nil)
        running = nil
    }

    private func log(_ text: String) { onState?(text) }

    private func runLoop() async {
        var backoff: UInt64 = 1
        while !Task.isCancelled {
            do {
                try await connectAndListen()
                backoff = 1
            } catch {
                log("error \(error.localizedDescription)")
            }
            if Task.isCancelled { break }
            try? await Task.sleep(nanoseconds: backoff * 1_000_000_000)
            backoff = min(backoff * 2, 60)
        }
    }

    private func connectAndListen() async throws {
        buffer.removeAll()
        var request = URLRequest(url: url)
        request.setValue("mqtt", forHTTPHeaderField: "Sec-WebSocket-Protocol")
        let websocket = session.webSocketTask(with: request)
        task = websocket
        websocket.resume()
        log("connecting")
        defer {
            pingTask?.cancel()
            pingTask = nil
            websocket.cancel(with: .goingAway, reason: nil)
            task = nil
        }
        try await send(websocket, connectPacket())
        while !Task.isCancelled {
            let message = try await websocket.receive()
            switch message {
            case .data(let data):
                buffer.append(data)
            case .string(let text):
                buffer.append(Data(text.utf8))
            @unknown default:
                continue
            }
            try processBuffer(websocket)
        }
    }

    private func send(_ websocket: URLSessionWebSocketTask, _ packet: Data) async throws {
        try await websocket.send(.data(packet))
    }

    private func connectPacket() -> Data {
        var payload = Data()
        payload.appendMQTTString(clientId)
        payload.appendMQTTString("{\"id\":\"\(userId)\",\"role\":\"customer\"}")
        payload.appendMQTTString(token)

        var body = Data()
        body.appendMQTTString("MQTT")
        body.append(5)          // protocol level
        body.append(0xC2)       // username + password + clean start
        body.append(0x00); body.append(0x3C) // keepalive 60 s
        body.append(5)          // properties length
        body.append(0x27)       // maximum packet size
        body.append(contentsOf: [0x00, 0x00, 0x10, 0x00])
        body.append(payload)

        var packet = Data([0x10])
        packet.appendMQTTVarint(body.count)
        packet.append(body)
        return packet
    }

    private func subscribePacket() -> Data {
        var body = Data()
        body.append(0x00); body.append(0x01) // packet id 1
        body.append(0)                       // properties length
        body.appendMQTTString("REFRESH_REQUEST_STATE_WIDGET/\(userId)")
        body.append(1)                       // QoS 1
        var packet = Data([0x82])
        packet.appendMQTTVarint(body.count)
        packet.append(body)
        return packet
    }

    private func processBuffer(_ websocket: URLSessionWebSocketTask) throws {
        while buffer.count >= 2 {
            var multiplier = 1
            var remaining = 0
            var index = 1
            var lengthBytes = 0
            var complete = false
            while index < buffer.count {
                let byte = buffer[buffer.startIndex + index]
                remaining += Int(byte & 0x7F) * multiplier
                multiplier *= 128
                index += 1
                lengthBytes += 1
                if byte & 0x80 == 0 { complete = true; break }
                if lengthBytes > 3 { break }
            }
            guard complete else { return }
            let total = 1 + lengthBytes + remaining
            guard buffer.count >= total else { return }
            let packet = Data(buffer.prefix(total))
            buffer.removeFirst(total)
            let type = packet[packet.startIndex] >> 4
            let bodyStart = 1 + lengthBytes
            switch type {
            case 2: // CONNACK
                if packet.count > bodyStart + 1, packet[packet.startIndex + bodyStart + 1] == 0 {
                    log("connected")
                    let subscription = subscribePacket()
                    Task { [weak self] in
                        guard let self, let ws = self.task else { return }
                        do { try await self.send(ws, subscription) }
                        catch { self.log("subscribe error \(error.localizedDescription)") }
                    }
                } else {
                    log("connack rejected")
                }
            case 9: // SUBACK
                log("subscribed")
                startPing(websocket)
            case 3: // PUBLISH
                handlePublish(packet, bodyStart: bodyStart, websocket: websocket)
            case 13: // PINGRESP
                break
            case 14: // DISCONNECT
                log("broker disconnect")
                throw MQTTError.disconnected
            default:
                break
            }
        }
    }

    private func handlePublish(_ packet: Data, bodyStart: Int, websocket: URLSessionWebSocketTask) {
        var offset = bodyStart
        guard packet.count >= offset + 2 else { return }
        let topicLength = Int(packet[packet.startIndex + offset]) << 8 | Int(packet[packet.startIndex + offset + 1])
        offset += 2 + topicLength
        guard packet.count >= offset else { return }
        let qos = (packet[packet.startIndex] >> 1) & 0x03
        var packetId: UInt16 = 0
        if qos > 0 {
            guard packet.count >= offset + 2 else { return }
            packetId = UInt16(packet[packet.startIndex + offset]) << 8 | UInt16(packet[packet.startIndex + offset + 1])
            offset += 2
        }
        if let propertiesLength = readVarint(packet, offset: &offset) {
            offset += propertiesLength
        }
        onWake?()
        if qos == 1, packetId > 0 {
            var ack = Data([0x40, 0x02])
            ack.append(UInt8(packetId >> 8)); ack.append(UInt8(packetId & 0xFF))
            Task { [weak self] in
                guard let self, let ws = self.task else { return }
                try? await self.send(ws, ack)
            }
        }
    }

    private func readVarint(_ packet: Data, offset: inout Int) -> Int? {
        var multiplier = 1
        var value = 0
        while offset < packet.count {
            let byte = packet[packet.startIndex + offset]
            offset += 1
            value += Int(byte & 0x7F) * multiplier
            multiplier *= 128
            if byte & 0x80 == 0 { return value }
            if multiplier > 128 * 128 * 128 { return nil }
        }
        return nil
    }

    private func startPing(_ websocket: URLSessionWebSocketTask) {
        guard pingTask == nil else { return }
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 45 * 1_000_000_000)
                guard let self, let ws = self.task else { return }
                try? await ws.send(.data(Data([0xC0, 0x00])))
            }
        }
    }
}

enum MQTTError: Error { case disconnected }

private extension Data {
    mutating func appendMQTTString(_ string: String) {
        let bytes = Array(string.utf8)
        append(UInt8(bytes.count >> 8))
        append(UInt8(bytes.count & 0xFF))
        append(contentsOf: bytes)
    }

    mutating func appendMQTTVarint(_ value: Int) {
        var remaining = value
        repeat {
            var byte = UInt8(remaining % 128)
            remaining /= 128
            if remaining > 0 { byte |= 0x80 }
            append(byte)
        } while remaining > 0
    }
}
