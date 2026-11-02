import Foundation
import MWDATCore
import MWDATCamera
import MWDATInputs

enum TutorMode: String {
    case check = "check"
    case solve = "solve"
}

/// Owns the glasses session: camera + standalone photo capability + capture button.
///
/// Sequence copied from Meta's BirdSpotter sample:
///   session.start → .started → addCamera → stream.start (wakes the sensor)
///   → stream .streaming → photo.start + addInputs
///   → photo .started → stream.stop (shutter alone on the sensor)
///   → capture button → photo.capturePhoto → bytes on photoDataPublisher
@MainActor
final class GlassesController: ObservableObject {
    @Published var registration = "unknown"
    @Published var sessionState = "idle"
    @Published var shutterReady = false
    /// Photo settings; `.large` gave 1920x1080, `.full` should be the sensor's native size.
    var photoResolution: PhotoResolution = .full
    var photoQuality: PhotoQuality = .medium
    private var captureStarted: Date?
    @Published var buttonReady = false
    @Published var lines: [String] = []
    @Published var deviceInfo = "no glasses seen yet"

    /// Called the moment the button is pressed (before the photo arrives).
    var onCapture: (@MainActor (TutorMode) -> Void)?
    /// Tap on the temple touchpad.
    var onTap: (@MainActor () -> Void)?
    /// Called with JPEG/HEIC bytes once the photo crossed the Bluetooth link.
    var onPhoto: (@MainActor (Data) -> Void)?

    private var session: DeviceSession?
    private var camera: Camera?
    private var inputs: Inputs?
    private let tokens = ListenerTokenBag()
    private var tasks: [Task<Void, Never>] = []
    private var photoStartRequested = false
    private var streamReleased = false
    private var watchedDevices: Set<UUID> = []
    /// Identifier of the glasses that are currently linked and compatible.
    private var readyDevice: DeviceIdentifier?

    func log(_ s: String) {
        let stamp = Self.clock.string(from: Date())
        lines.append("\(stamp) \(s)")
        if lines.count > 200 { lines.removeFirst(lines.count - 200) }
        print("[GlassesTutor] \(s)")
    }

    private static let clock: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    // MARK: - Registration & permissions

    func observeRegistration() {
        tasks.append(Task { [weak self] in
            for await state in Wearables.shared.registrationStateStream() {
                await MainActor.run { self?.registration = String(describing: state) }
            }
        })
        tasks.append(Task { [weak self] in
            for await ids in Wearables.shared.devicesStream() {
                await MainActor.run {
                    guard let self else { return }
                    self.log("devices: \(ids.count)")
                    for id in ids { self.watch(id) }
                }
            }
        })
    }

    // MARK: - Device diagnostics

    private func describe(_ d: Device, _ state: DeviceState) -> String {
        "\(d.nameOrId()) \(d.deviceType()) link=\(state.linkState) compat=\(state.compatibility) "
            + "worn=\(state.donState) battery=\(state.batteryLevel.map(String.init) ?? "?")"
    }

    private func watch(_ id: DeviceIdentifier) {
        guard let device = Wearables.shared.deviceForIdentifier(id) else {
            log("device \(id): no Device object")
            return
        }
        guard !watchedDevices.contains(device.deviceUUID) else { return }
        watchedDevices.insert(device.deviceUUID)
        device.addDeviceStateListener { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                let line = self.describe(device, state)
                self.deviceInfo = line
                self.log("device: \(line)")
                if state.linkState == .connected, state.compatibility == .compatible {
                    self.readyDevice = device.identifier
                    if self.session == nil {
                        self.log("glasses connected and compatible, starting session")
                        self.connect()
                    }
                } else if state.linkState == .disconnected {
                    self.readyDevice = nil
                }
            }
        }.store(in: tokens)
    }

    func openFirmwareUpdate() async {
        do { try await Wearables.shared.openFirmwareUpdate() } catch { log("firmware update: \(error)") }
    }

    func openGlassesAppUpdate() async {
        do { try await Wearables.shared.openDATGlassesAppUpdate() } catch { log("glasses app update: \(error)") }
    }

    func register() async {
        do {
            try await Wearables.shared.startRegistration()
            log("registration started (Meta AI opens)")
        } catch {
            log("registration: \(error)")
        }
    }

    func requestCameraPermission() async {
        do {
            let status = try await Wearables.shared.requestPermission(.camera)
            log("camera permission: \(String(describing: status))")
        } catch {
            log("camera permission: \(error)")
        }
    }

    // MARK: - Session

    func connect() {
        guard session == nil else { return }
        let wearables = Wearables.shared
        // AutoDeviceSelector picks a device asynchronously; used right after creation it has
        // nothing selected and createSession throws noEligibleDevice. Meta's samples name the
        // device explicitly, so do the same with the glasses we have already seen.
        guard let id = readyDevice ?? wearables.devices.first else {
            log("no glasses in the device list yet, will start when they appear")
            return
        }
        do {
            let s = try wearables.createSession(deviceSelector: SpecificDeviceSelector(device: id))
            session = s
            tasks.append(Task { [weak self] in
                for await state in s.stateStream() {
                    await MainActor.run {
                        guard let self else { return }
                        self.sessionState = String(describing: state)
                        self.log("session: \(state)")
                        switch state {
                        case .started: self.attachCamera(s)
                        case .stopped: self.teardown()
                        default: break
                        }
                    }
                }
            })
            tasks.append(Task { [weak self] in
                for await error in s.errorStream() {
                    await MainActor.run { self?.log("session error: \(error.description)") }
                }
            })
            try s.start()
            log("session start requested")
        } catch {
            log("session: \(error)")
            session = nil
        }
    }

    func reconnect() {
        teardown()
        connect()
    }

    private func teardown() {
        camera?.stop()
        session?.stop()
        camera = nil
        inputs = nil
        session = nil
        shutterReady = false
        buttonReady = false
        photoStartRequested = false
        streamReleased = false
    }

    // MARK: - Camera + photo

    private func attachCamera(_ s: DeviceSession) {
        guard camera == nil else { return }
        Task { [weak self] in
            let status = try? await Wearables.shared.checkPermissionStatus(.camera)
            await MainActor.run { self?.log("camera permission status: \(status.map { String(describing: $0) } ?? "unreadable")") }
        }
        // Smallest stream the SDK sells: its only job is to wake the sensor.
        let config = StreamConfiguration(videoCodec: .hvc1, resolution: .low, frameRate: 7)
        guard let cam = try? s.addCamera(config: config) else {
            log("camera would not attach (is the camera permission granted in Meta AI?)")
            return
        }
        camera = cam

        let photo = cam.photo
        photo.statePublisher.listen { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                self.log("photo: \(state)")
                switch state {
                case .started:
                    self.shutterReady = true
                    self.releaseStream()
                case .stopped, .stopping:
                    self.shutterReady = false
                    self.photoStartRequested = false
                default:
                    break
                }
            }
        }.store(in: tokens)

        photo.photoDataPublisher.listen { [weak self] data in
            Task { @MainActor in
                guard let self else { return }
                let took = self.captureStarted.map { String(format: " in %.1f s", Date().timeIntervalSince($0)) } ?? ""
                self.log("photo arrived: \(data.imageData.count) bytes\(took)")
                self.onPhoto?(data.imageData)
            }
        }.store(in: tokens)

        photo.transferProgressPublisher.listen { [weak self] progress in
            Task { @MainActor in
                guard let self else { return }
                let pct = Int(progress.fraction * 100)
                if pct == 0 || pct == 50 { self.log("photo transfer: \(progress.bytesReceived / 1024)/\(progress.totalBytes / 1024) KB") }
            }
        }.store(in: tokens)

        photo.errorPublisher.listen { [weak self] error in
            Task { @MainActor in self?.log("photo error: \(error)") }
        }.store(in: tokens)

        cam.statePublisher.listen { [weak self] state in
            Task { @MainActor in self?.log("camera: \(state)") }
        }.store(in: tokens)

        cam.stream.statePublisher.listen { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                self.log("stream: \(state)")
                switch state {
                case .streaming:
                    // Sensor is provably awake: start the shutter and listen to the button.
                    self.startPhotoIfNeeded()
                    self.attachInputs(s)
                default:
                    break
                }
            }
        }.store(in: tokens)

        cam.stream.start()
    }

    private func startPhotoIfNeeded() {
        guard !photoStartRequested, let camera else { return }
        photoStartRequested = true
        camera.photo.start()
    }

    /// Frames and stills compete for the sensor; a running stream makes capture fail.
    private func releaseStream() {
        guard !streamReleased, let camera else { return }
        streamReleased = true
        camera.stream.stop()
        log("stream put down, shutter owns the sensor")
    }

    // MARK: - Capture button

    private func attachInputs(_ s: DeviceSession) {
        guard inputs == nil else { return }
        let configuration = InputsConfiguration(sources: [.captureButton, .captouch])
        do {
            guard let attached = try s.addInputs(configuration: configuration) else {
                log("this pair reports no inputs")
                return
            }
            inputs = attached
            buttonReady = true
            tasks.append(Task { [weak self] in
                for await event in attached.events {
                    await MainActor.run { self?.handle(event) }
                }
                await MainActor.run {
                    self?.buttonReady = false
                    self?.log("inputs stream ended")
                }
            })
            log("capture button attached")
        } catch {
            log("inputs: \(error)  (Inputs is experimental; may need the capability enabled in Wearables Developer Center)")
        }
    }

    private func handle(_ event: InputEvent) {
        switch event {
        case let .capture(pressType, source, _):
            guard source == .captureButton else { return }
            switch pressType {
            case .shortPress: capture(mode: .check)
            case .doublePress: capture(mode: .solve)
            default: break
            }
        case let .select(source, _) where source == .captouch:
            log("touchpad tap")
            onTap?()
        case let .nav(direction, source, _) where source == .captouch:
            log("touchpad swipe \(direction)")
        default:
            break
        }
    }

    func capture(mode: TutorMode) {
        guard let camera, shutterReady else {
            log("capture asked, but the shutter is not ready")
            return
        }
        log("capture (\(mode.rawValue)), \(photoResolution.rawValue)/\(photoQuality.rawValue)")
        onCapture?(mode)
        captureStarted = Date()
        camera.photo.capturePhoto(resolution: photoResolution, quality: photoQuality)
    }
}
