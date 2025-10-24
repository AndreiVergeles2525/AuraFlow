import SwiftUI
import AVKit
import AppKit
import CoreImage
import QuartzCore

struct ContentView: View {
    @StateObject var viewModel: AppViewModel
    @State private var isAdjustingSpeed: Bool = false
    @State private var window: NSWindow?
    @State private var controlsVisible: Bool = true
    @State private var hideWorkItem: DispatchWorkItem?
    @State private var localMonitor: Any?
    @State private var globalMonitor: Any?
    @Environment(\.colorScheme) private var colorScheme

    private var aspectRatio: CGFloat { mainScreenAspectRatio() }
    private let hideDelay: TimeInterval = 4.0

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            PreviewLayer(player: viewModel.previewPlayer, aspectRatio: aspectRatio)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 12) {
                if let alert = viewModel.alertMessage {
                    ErrorBanner(text: alert)
                        .padding(.leading, 20)
                        .padding(.bottom, 12)
                }

                ControlPanel(
                    viewModel: viewModel,
                    isAdjustingSpeed: $isAdjustingSpeed
                )
                .disabled(!viewModel.isControllerAvailable)
                .overlay(
                    Group {
                        if !viewModel.isControllerAvailable {
                            DisabledOverlay()
                        }
                    }
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .opacity(controlsVisible ? 1 : 0)
            .animation(.easeInOut(duration: 0.3), value: controlsVisible)

            WindowControls(window: $window)
                .padding(.top, 18)
                .padding(.leading, 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .opacity(controlsVisible ? 1 : 0)
                .animation(.easeInOut(duration: 0.3), value: controlsVisible)

            SpeedOverlay(viewModel: viewModel, isAdjustingSpeed: $isAdjustingSpeed)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, 18)
                .opacity(controlsVisible ? 1 : 0)
                .animation(.easeInOut(duration: 0.3), value: controlsVisible)
        }
        .frame(minWidth: 760, minHeight: 480)
        .background(Color.clear)
        .overlay(WindowAccessor(window: $window).allowsHitTesting(false))
        .task {
            await viewModel.loadStatus()
        }
        .onAppear {
            handleUserActivity()
            setupActivityMonitoring()
        }
        .onDisappear {
            teardownActivityMonitoring()
        }
    }
}

struct PreviewLayer: View {
    let player: AVPlayer?
    let aspectRatio: CGFloat

    var body: some View {
        VideoPreview(player: player)
            .aspectRatio(aspectRatio, contentMode: .fill)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
    }
}

struct ControlPanel: View {
    @ObservedObject var viewModel: AppViewModel
    @Binding var isAdjustingSpeed: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Видео")
                        .font(.headline.weight(.semibold))
                    Text(viewModel.videoURL?.lastPathComponent ?? "Не выбрано")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Button("Выбрать…") {
                    viewModel.chooseVideo()
                }
                .buttonStyle(.borderedProminent)
            }

            ControlButtons(viewModel: viewModel)

            HStack(alignment: .center, spacing: 12) {
                Toggle(isOn: Binding(
                    get: { viewModel.autostartEnabled },
                    set: { newValue in viewModel.toggleAutostart(newValue) }
                )) {
                    Label("Автозапуск", systemImage: "power")
                        .labelStyle(.titleAndIcon)
                }
                .toggleStyle(.switch)

                Spacer()

                if let message = viewModel.statusMessage {
                    Text(message)
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 22)
        .frame(maxWidth: .infinity)
        .background(
            LiquidGlassView()
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(colorScheme == .dark ? 0.12 : 0.16), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.25), radius: 16, x: 0, y: 10)
    }
}

struct ControlButtons: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        HStack(spacing: 18) {
            Spacer()

            Button {
                viewModel.preview()
            } label: {
                Label("Предпросмотр", systemImage: "play.rectangle")
                    .frame(minWidth: 130)
            }
            .buttonStyle(.bordered)

            Button {
                viewModel.start()
            } label: {
                Label("Старт", systemImage: "desktopcomputer")
                    .frame(minWidth: 96)
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isRunning)

            Button(role: .destructive) {
                viewModel.stop()
            } label: {
                Label("Стоп", systemImage: "stop.circle")
                    .frame(minWidth: 96)
            }
            .buttonStyle(.bordered)
            .disabled(!viewModel.isRunning)

            Spacer()
        }
    }
}

struct SpeedOverlay: View {
    @ObservedObject var viewModel: AppViewModel
    @Binding var isAdjustingSpeed: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 14) {
            Label("Скорость", systemImage: "speedometer")
                .labelStyle(.titleAndIcon)
                .foregroundStyle(.primary)

            Slider(
                value: Binding(
                    get: { viewModel.playbackSpeed },
                    set: { newValue in viewModel.playbackSpeed = newValue }
                ),
                in: 0.25...2.0,
                step: 0.05,
                onEditingChanged: { editing in
                    isAdjustingSpeed = editing
                    if !editing {
                        viewModel.updateSpeed(viewModel.playbackSpeed)
                    }
                }
            )
            .frame(width: 220)

            Text(String(format: "%.2fx", viewModel.playbackSpeed))
                .monospacedDigit()
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
        .background(
            LiquidGlassView()
                .clipShape(Capsule())
        )
        .overlay(
            Capsule().stroke(Color.white.opacity(colorScheme == .dark ? 0.15 : 0.2), lineWidth: 0.8)
        )
        .shadow(color: Color.black.opacity(0.25), radius: 10, x: 0, y: 6)
    }
}

struct VideoPreview: NSViewRepresentable {
    let player: AVPlayer?

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .none
        view.videoGravity = .resizeAspectFill
        view.allowsPictureInPicturePlayback = false
        view.updatesNowPlayingInfoCenter = false
        view.showsFullScreenToggleButton = false
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        nsView.player = player
    }
}

struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode
    var state: NSVisualEffectView.State

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
    }
}

struct WindowControls: View {
    @Binding var window: NSWindow?

    var body: some View {
        HStack(spacing: 9) {
            WindowControlButton(color: Color(red: 1, green: 0.33, blue: 0.31)) {
                window?.performClose(nil)
            }
            WindowControlButton(color: Color(red: 1, green: 0.80, blue: 0.25)) {
                window?.miniaturize(nil)
            }
            WindowControlButton(color: Color(red: 0.26, green: 0.86, blue: 0.39)) {
                window?.zoom(nil)
            }
        }
    }
}

struct WindowControlButton: View {
    let color: Color
    let action: () -> Void

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 13, height: 13)
            .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 0.6))
            .onTapGesture { action() }
    }
}

struct DisabledOverlay: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(Color.black.opacity(0.5))
            .overlay(
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title3.weight(.semibold))
                    Text("Python bridge недоступен")
                        .font(.callout)
                        .foregroundColor(.white.opacity(0.92))
                }
                .padding(14)
            )
    }
}

struct ErrorBanner: View {
    let text: String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.yellow)
            Text(text)
                .font(.callout)
                .foregroundColor(.white.opacity(0.95))
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.6))
        )
    }
}

struct WindowAccessor: NSViewRepresentable {
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let currentWindow = view.window {
                configureWindowForClientDecorations(currentWindow)
                window = currentWindow
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let currentWindow = nsView.window {
                configureWindowForClientDecorations(currentWindow)
                if window !== currentWindow {
                    window = currentWindow
                }
            }
        }
    }
}

private extension ContentView {
    func setupActivityMonitoring() {
        teardownActivityMonitoring()
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .rightMouseDown, .keyDown]) { event in
            handleUserActivity()
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .rightMouseDown, .keyDown]) { _ in
            handleUserActivity()
        }
    }

    func teardownActivityMonitoring() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        hideWorkItem?.cancel()
        hideWorkItem = nil
    }

    func handleUserActivity() {
        hideWorkItem?.cancel()
        withAnimation(.easeInOut(duration: 0.25)) {
            controlsVisible = true
        }
        let workItem = DispatchWorkItem {
            withAnimation(.easeInOut(duration: 0.4)) {
                controlsVisible = false
            }
        }
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + hideDelay, execute: workItem)
    }
}

// MARK: - Liquid Glass Components

struct LiquidGlassView: NSViewRepresentable {
    enum MaterialStyle {
        case regular
        case clear
    }

    var material: MaterialStyle = .regular

    func makeNSView(context: Context) -> NSView {
        if let glass = createGlassView() {
            return glass
        }
        let fallback = LiquidGlassFallbackView()
        fallback.glassStyle = material
        return fallback
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let fallback = nsView as? LiquidGlassFallbackView {
            fallback.glassStyle = material
        } else {
            configureGlassLayer(for: nsView)
        }
    }

    private func createGlassView() -> NSView? {
        guard let glassClass = NSClassFromString("NSGlassEffectView") as? NSObject.Type else {
            return nil
        }
        let instance = glassClass.init()
        guard let view = instance as? NSView else {
            return nil
        }
        configureGlassLayer(for: view)
        return view
    }

    private func configureGlassLayer(for view: NSView) {
        view.wantsLayer = true
        if view.layer == nil {
            view.layer = CALayer()
        }
        view.layer?.cornerRadius = 14
        view.layer?.masksToBounds = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(material == .clear ? 0.18 : 0.28).cgColor
        let materialSelector = NSSelectorFromString("setMaterial:")
        if view.responds(to: materialSelector) {
            let value = material == .regular ? 0 : 1
            view.perform(materialSelector, with: NSNumber(value: value))
        }
        let blendingSelector = NSSelectorFromString("setBlendingMode:")
        if view.responds(to: blendingSelector) {
            // 1 == behindWindow on most modern macOS versions
            view.perform(blendingSelector, with: NSNumber(value: 1))
        }
        LiquidGlassFallbackView.applyOverlays(to: view.layer!, style: material)
    }
}

private final class LiquidGlassFallbackView: NSVisualEffectView {
    var glassStyle: LiquidGlassView.MaterialStyle = .regular {
        didSet { updateAppearance() }
    }

    private var noiseLayer: CALayer?
    private var highlightLayer: CAGradientLayer?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        blendingMode = .behindWindow
        material = .underWindowBackground
        state = .active
        wantsLayer = true
        layer = CALayer()
        layer?.cornerRadius = 14
        layer?.masksToBounds = true
        updateAppearance()
    }

    override func layout() {
        super.layout()
        noiseLayer?.frame = bounds
        highlightLayer?.frame = bounds
    }

    func updateAppearance() {
        guard let layer = self.layer else { return }
        layer.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(glassStyle == .clear ? 0.18 : 0.28).cgColor
        layer.backgroundFilters = LiquidGlassFallbackView.backgroundFilters
        Self.applyOverlays(to: layer, style: glassStyle, noiseLayer: &noiseLayer, highlightLayer: &highlightLayer)
    }

    static func applyOverlays(to layer: CALayer, style: LiquidGlassView.MaterialStyle) {
        var noise: CALayer?
        var highlight: CAGradientLayer?
        applyOverlays(to: layer, style: style, noiseLayer: &noise, highlightLayer: &highlight)
    }

    static func applyOverlays(to layer: CALayer, style: LiquidGlassView.MaterialStyle, noiseLayer: inout CALayer?, highlightLayer: inout CAGradientLayer?) {
        if noiseLayer == nil {
            let noise = CALayer()
            noise.contents = noiseImage
            noise.opacity = style == .clear ? 0.02 : 0.04
            noise.compositingFilter = "overlayBlendMode"
            noise.contentsGravity = .resizeAspectFill
            noise.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
            layer.addSublayer(noise)
            noiseLayer = noise
        }
        noiseLayer?.frame = layer.bounds

        if highlightLayer == nil {
            let gradient = CAGradientLayer()
            gradient.type = .radial
            gradient.colors = [
                NSColor.white.withAlphaComponent(0.06).cgColor,
                NSColor.white.withAlphaComponent(0.0).cgColor,
            ]
            gradient.locations = [0, 1]
            gradient.startPoint = CGPoint(x: 0.5, y: 0.0)
            gradient.endPoint = CGPoint(x: 0.5, y: 0.9)
            gradient.compositingFilter = "screenBlendMode"
            gradient.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
            layer.addSublayer(gradient)
            highlightLayer = gradient
        }
        highlightLayer?.frame = layer.bounds
    }

    private static let backgroundFilters: [CIFilter] = {
        var filters: [CIFilter] = []
        if let clamp = CIFilter(name: "CIAffineClamp") {
            clamp.setDefaults()
            clamp.setValue(CGAffineTransform.identity, forKey: "inputTransform")
            filters.append(clamp)
        }
        if let blur = CIFilter(name: "CIGaussianBlur") {
            blur.setValue(25.0, forKey: kCIInputRadiusKey)
            filters.append(blur)
        }
        if let color = CIFilter(name: "CIColorControls") {
            color.setValue(1.6, forKey: kCIInputSaturationKey)
            color.setValue(0.02, forKey: kCIInputBrightnessKey)
            color.setValue(1.05, forKey: kCIInputContrastKey)
            filters.append(color)
        }
        return filters
    }()

    private static let noiseImage: CGImage = {
        let size = CGSize(width: 128, height: 128)
        let random = CIFilter(name: "CIRandomGenerator")!.outputImage!
        let transform = CGAffineTransform(scaleX: size.width, y: size.height)
        let scaled = random.transformed(by: transform).cropped(to: CGRect(origin: .zero, size: size))
        let saturation = CIFilter(name: "CIColorControls")!
        saturation.setValue(scaled, forKey: kCIInputImageKey)
        saturation.setValue(0.0, forKey: kCIInputSaturationKey)
        saturation.setValue(0.0, forKey: kCIInputBrightnessKey)
        saturation.setValue(1.2, forKey: kCIInputContrastKey)
        let context = CIContext(options: [.workingColorSpace: NSNull()])
        return context.createCGImage(saturation.outputImage!, from: CGRect(origin: .zero, size: size))!
    }()
}
