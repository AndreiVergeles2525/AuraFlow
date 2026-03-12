import SwiftUI
import AVKit
import AppKit
import CoreImage
import QuartzCore

struct ContentView: View {
    @StateObject var viewModel: AppViewModel
    @State private var isAdjustingSpeed: Bool = false
    @State private var controlsVisible: Bool = true
    @State private var hideWorkItem: DispatchWorkItem?
    @State private var localMonitor: Any?
    @State private var globalMonitor: Any?

    private var aspectRatio: CGFloat { mainScreenAspectRatio() }
    private let hideDelay: TimeInterval = 4.0

    var body: some View {
        GeometryReader { proxy in
            let horizontalPadding: CGFloat = 24
            let availableWidth = max(proxy.size.width - (horizontalPadding * 2), 0)
            let availableHeight = max(proxy.size.height - 48, 0)
            let controlPanelMaxWidth: CGFloat = 1440
            let controlPanelWidth = min(availableWidth, controlPanelMaxWidth)
            let catalogMaxWidth: CGFloat = 1040
            let overlayWidth = viewModel.isCatalogOpen ? min(availableWidth, catalogMaxWidth) : controlPanelWidth
            let isCompactBySize = controlPanelWidth < 1080 || availableHeight < 620
            let isVeryCompactByHeight = availableHeight < 560

            ZStack {
                Color.clear
                PreviewLayer(
                    player: viewModel.previewPlayer,
                    aspectRatio: aspectRatio,
                    scaleMode: viewModel.scaleMode
                )
                    .ignoresSafeArea()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
            .overlay(alignment: .top) {
                if !viewModel.isCatalogOpen {
                    SpeedOverlay(
                        viewModel: viewModel,
                        isAdjustingSpeed: $isAdjustingSpeed,
                        availableWidth: availableWidth
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, horizontalPadding)
                    .padding(.top, 18)
                    .opacity(controlsVisible ? 1 : 0)
                    .animation(.easeInOut(duration: 0.3), value: controlsVisible)
                }
            }
            .overlay(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 12) {
                    if let alert = viewModel.alertMessage {
                        ErrorBanner(text: alert)
                    }

                    if viewModel.isCatalogOpen {
                        WallpaperCatalogView(viewModel: viewModel)
                    } else {
                        ControlPanel(
                            viewModel: viewModel,
                            isAdjustingSpeed: $isAdjustingSpeed,
                            panelWidth: controlPanelWidth,
                            isCompactBySize: isCompactBySize,
                            isVeryCompactByHeight: isVeryCompactByHeight
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
                }
                .frame(width: overlayWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, horizontalPadding)
                .padding(.bottom, 24)
                .opacity(controlsVisible ? 1 : 0)
                .animation(.easeInOut(duration: 0.3), value: controlsVisible)
            }
            .overlay {
                if viewModel.isSettingsOpen {
                    SettingsPopupOverlay(viewModel: viewModel)
                }
            }
            .overlay {
                if viewModel.isMonitoringOpen {
                    MonitoringPopupOverlay(viewModel: viewModel)
                }
            }
            .overlay {
                if viewModel.isDownloadedWallpapersOpen {
                    DownloadedWallpapersOverlay(viewModel: viewModel)
                }
            }
        }
        .frame(minWidth: 760, minHeight: 480)
        .background(Color.clear)
        .overlay(WindowAccessor().allowsHitTesting(false))
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
    let scaleMode: WallpaperScaleMode

    var body: some View {
        VideoPreview(player: player, videoGravity: scaleMode.previewGravity)
            .aspectRatio(aspectRatio, contentMode: .fill)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
    }
}

struct ControlPanel: View {
    @ObservedObject var viewModel: AppViewModel
    @Binding var isAdjustingSpeed: Bool
    let panelWidth: CGFloat
    let isCompactBySize: Bool
    let isVeryCompactByHeight: Bool
    @Environment(\.colorScheme) private var colorScheme

    private var widthScale: CGFloat {
        max(0.76, min(1.0, panelWidth / 1180))
    }

    private var panelHorizontalInset: CGFloat {
        isCompactBySize ? 18 : 22
    }

    private var panelVerticalInset: CGFloat {
        isCompactBySize ? 12 : 14
    }

    private var rowSpacing: CGFloat {
        isCompactBySize ? 10 : 12
    }

    private var primarySpacing: CGFloat {
        isCompactBySize ? 8 : 12
    }

    private var secondarySpacing: CGFloat {
        isCompactBySize ? 8 : 12
    }

    private var controlSize: ControlSize {
        isCompactBySize ? .small : .regular
    }

    private var primaryButtonWidth: CGFloat {
        scaledWidth(84, min: 70)
    }

    private var removeButtonWidth: CGFloat {
        scaledWidth(146, min: 110)
    }

    private var catalogButtonWidth: CGFloat {
        scaledWidth(156, min: 118)
    }

    private var downloadedButtonWidth: CGFloat {
        scaledWidth(194, min: 144)
    }

    private var changeWallpaperButtonWidth: CGFloat {
        scaledWidth(188, min: 148)
    }

    private var settingsButtonWidth: CGFloat {
        scaledWidth(108, min: 84)
    }

    private var monitoringButtonWidth: CGFloat {
        scaledWidth(138, min: 108)
    }

    private var rowContentWidth: CGFloat {
        max(panelWidth - (panelHorizontalInset * 2), 0)
    }

    private var controlButtonsRowWidth: CGFloat {
        (primaryButtonWidth * 2) + removeButtonWidth + (primarySpacing * 2)
    }

    private var actionButtonsRowWidth: CGFloat {
        controlButtonsRowWidth + changeWallpaperButtonWidth
    }

    private var libraryButtonsRowWidth: CGFloat {
        catalogButtonWidth + downloadedButtonWidth + primarySpacing
    }

    private var secondaryButtonsRowWidth: CGFloat {
        settingsButtonWidth + monitoringButtonWidth + secondarySpacing
    }

    private var actionRowGap: CGFloat {
        max(primarySpacing, rowContentWidth - actionButtonsRowWidth)
    }

    private var bottomRowGap: CGFloat {
        max(secondarySpacing, rowContentWidth - secondaryButtonsRowWidth - libraryButtonsRowWidth)
    }

    private var showsStatusMessage: Bool {
        !isVeryCompactByHeight && panelWidth >= 860
    }

    private var showsOptimizationProgress: Bool {
        !isVeryCompactByHeight && panelWidth >= 820
    }

    var body: some View {
        VStack(alignment: .leading, spacing: rowSpacing) {
            HStack(alignment: .top, spacing: 0) {
                videoInfo
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(alignment: .center, spacing: 0) {
                ControlButtons(
                    viewModel: viewModel,
                    spacing: primarySpacing,
                    primaryButtonWidth: primaryButtonWidth,
                    removeButtonWidth: removeButtonWidth
                )
                .frame(width: controlButtonsRowWidth, alignment: .leading)

                Color.clear
                    .frame(width: actionRowGap, height: 1)

                changeWallpaperButton
                    .frame(width: changeWallpaperButtonWidth)
                    .layoutPriority(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(alignment: .center, spacing: 0) {
                HStack(alignment: .center, spacing: secondarySpacing) {
                    settingsButton
                        .frame(width: settingsButtonWidth)

                    monitoringButton
                        .frame(width: monitoringButtonWidth)
                }
                .frame(width: secondaryButtonsRowWidth, alignment: .leading)

                Color.clear
                    .frame(width: bottomRowGap, height: 1)

                HStack(alignment: .center, spacing: primarySpacing) {
                    catalogButton
                        .frame(width: catalogButtonWidth)
                        .layoutPriority(2)

                    downloadedWallpapersButton
                        .frame(width: downloadedButtonWidth)
                        .layoutPriority(2)
                }
                .frame(width: libraryButtonsRowWidth, alignment: .trailing)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if showsStatusMessage, let message = viewModel.statusMessage {
                Text(message)
                    .foregroundColor(.secondary)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if viewModel.optimizationInProgress && showsOptimizationProgress {
                VStack(alignment: .leading, spacing: 6) {
                    if let label = viewModel.optimizationLabel {
                        Text(label)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    ProgressView(value: viewModel.optimizationProgress)
                        .progressViewStyle(.linear)
                }
            }
        }
        .controlSize(controlSize)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, panelVerticalInset)
        .padding(.horizontal, panelHorizontalInset)
        .frame(maxWidth: .infinity, alignment: .leading)
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

    private var catalogButton: some View {
        Button {
            viewModel.openCatalog()
        } label: {
            Text("Wallpaper Catalog")
                .lineLimit(1)
                .truncationMode(.tail)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .disabled(!viewModel.canClearWallpaper)
    }

    private var downloadedWallpapersButton: some View {
        Button {
            viewModel.openDownloadedWallpapers()
        } label: {
            Text("Downloaded Wallpapers")
                .lineLimit(1)
                .truncationMode(.tail)
                .minimumScaleFactor(0.78)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .disabled(!viewModel.canClearWallpaper)
    }

    private var changeWallpaperButton: some View {
        Button {
            viewModel.chooseVideo()
        } label: {
            Text("Change Wallpaper…")
                .lineLimit(1)
                .truncationMode(.tail)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!viewModel.canClearWallpaper)
    }

    private var settingsButton: some View {
        Button {
            viewModel.openSettings()
        } label: {
            Label("Settings", systemImage: "slider.horizontal.3.circle.fill")
                .lineLimit(1)
                .truncationMode(.tail)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .disabled(viewModel.isBusy)
    }

    private var monitoringButton: some View {
        Button {
            viewModel.openMonitoring()
        } label: {
            Label("Monitoring", systemImage: "gauge.with.dots.needle.67percent")
                .lineLimit(1)
                .truncationMode(.tail)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .disabled(!viewModel.canOpenMonitoring)
    }

    private func scaledWidth(_ base: CGFloat, min minWidth: CGFloat) -> CGFloat {
        max(minWidth, base * widthScale)
    }

    private var videoInfo: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Video")
                .font(.headline.weight(.semibold))
            Text(viewModel.selectedVideoName)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .layoutPriority(0)
    }
}

struct SettingsPopupOverlay: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Color.black.opacity(colorScheme == .dark ? 0.42 : 0.28)
                .ignoresSafeArea()
                .onTapGesture {
                    viewModel.closeSettings()
                }

            SettingsPopupCard(viewModel: viewModel)
                .frame(maxWidth: 620)
                .padding(.horizontal, 24)
                .transition(.asymmetric(insertion: .scale(scale: 0.94).combined(with: .opacity), removal: .opacity))
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.86), value: viewModel.isSettingsOpen)
        .zIndex(50)
    }
}

struct SettingsPopupCard: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Playback Settings", systemImage: "gearshape.2.fill")
                    .font(.headline.weight(.semibold))
                Spacer()
                Button {
                    viewModel.closeSettings()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }

            Divider()

            Toggle(isOn: Binding(
                get: { viewModel.autostartEnabled },
                set: { newValue in viewModel.toggleAutostart(newValue) }
            )) {
                Label("Launch at Login", systemImage: "power")
            }
            .toggleStyle(.switch)
            .disabled(!viewModel.canToggleAutostart)

            Toggle(isOn: Binding(
                get: { viewModel.pauseOnFullscreenEnabled },
                set: { newValue in viewModel.togglePauseOnFullscreen(newValue) }
            )) {
                Label("Auto-Pause on Fullscreen Apps", systemImage: "display")
            }
            .toggleStyle(.switch)
            .disabled(!viewModel.canTogglePauseOnFullscreen)

            Toggle(isOn: Binding(
                get: { viewModel.blendInterpolationEnabled },
                set: { newValue in viewModel.toggleBlendInterpolation(newValue) }
            )) {
                Label("Blend Interpolation", systemImage: "sparkles.tv")
            }
            .toggleStyle(.switch)
            .disabled(!viewModel.canToggleBlendInterpolation)

            Picker(
                "Scale Algorithm",
                selection: Binding(
                    get: { viewModel.scaleMode },
                    set: { viewModel.setScaleMode($0) }
                )
            ) {
                ForEach(WallpaperScaleMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .disabled(!viewModel.canToggleScaleMode)

            Divider().padding(.vertical, 4)

            Text("Video Optimization")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)

            Toggle(isOn: Binding(
                get: { viewModel.optimizationEnabled },
                set: { viewModel.setOptimizationEnabled($0) }
            )) {
                Text("Enable Auto Optimization")
            }
            .toggleStyle(.switch)
            .disabled(!viewModel.canChangeOptimizationSettings)

            HStack(spacing: 12) {
                Toggle(isOn: Binding(
                    get: { viewModel.optimizationTranscodeH264ToHEVC },
                    set: { viewModel.setOptimizationTranscodeH264ToHEVC($0) }
                )) {
                    Text("H.264 → HEVC")
                }
                .toggleStyle(.checkbox)
                .disabled(!viewModel.optimizationEnabled || !viewModel.canChangeOptimizationSettings)

                Toggle(isOn: Binding(
                    get: { viewModel.optimizationAllowAV1Passthrough },
                    set: { viewModel.setOptimizationAllowAV1Passthrough($0) }
                )) {
                    Text("Keep AV1 (HW Decode)")
                }
                .toggleStyle(.checkbox)
                .disabled(!viewModel.optimizationEnabled || !viewModel.canChangeOptimizationSettings)
            }

            Toggle(isOn: Binding(
                get: { viewModel.optimizationForceSoftwareAV1Encode },
                set: { viewModel.setOptimizationForceSoftwareAV1Encode($0) }
            )) {
                Text("Force AV1 Encode (Software)")
            }
            .toggleStyle(.checkbox)
            .disabled(
                !viewModel.optimizationEnabled
                    || !viewModel.canChangeOptimizationSettings
                    || !viewModel.optimizationHardwareAV1DecodeAvailable
            )

            Picker(
                "Optimization Profile",
                selection: Binding(
                    get: { viewModel.optimizationProfile },
                    set: { viewModel.setOptimizationProfile($0) }
                )
            ) {
                ForEach(OptimizationProfile.allCases) { profile in
                    Text(profile.title).tag(profile)
                }
            }
            .pickerStyle(.segmented)
            .disabled(!viewModel.optimizationEnabled || !viewModel.canChangeOptimizationSettings)

            if viewModel.optimizationHardwareAV1DecodeAvailable {
                Text("AV1 hardware encode is unavailable on Mac. Force AV1 uses software ffmpeg and can be CPU intensive.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else {
                Text("Force AV1 encode is disabled because this Mac has no hardware AV1 decode.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if viewModel.optimizationInProgress {
                VStack(alignment: .leading, spacing: 6) {
                    if let label = viewModel.optimizationLabel {
                        Text(label)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    ProgressView(value: viewModel.optimizationProgress)
                        .progressViewStyle(.linear)
                }
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 20)
        .background(
            LiquidGlassView()
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(colorScheme == .dark ? 0.14 : 0.2), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.45 : 0.28), radius: 24, x: 0, y: 16)
    }
}

struct MonitoringPopupOverlay: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Color.black.opacity(colorScheme == .dark ? 0.42 : 0.28)
                .ignoresSafeArea()
                .onTapGesture {
                    viewModel.closeMonitoring()
                }

            MonitoringPopupCard(viewModel: viewModel)
                .frame(maxWidth: 620)
                .padding(.horizontal, 24)
                .transition(.asymmetric(insertion: .scale(scale: 0.94).combined(with: .opacity), removal: .opacity))
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.86), value: viewModel.isMonitoringOpen)
        .zIndex(60)
    }
}

struct MonitoringPopupCard: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Wallpaper Monitoring", systemImage: "chart.bar.xaxis")
                    .font(.headline.weight(.semibold))
                Spacer()
                Button {
                    viewModel.closeMonitoring()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }

            Divider()

            if let metrics = viewModel.monitoringSnapshot {
                let cpu = metrics.cpu_percent ?? 0
                let memory = metrics.memory_mb ?? 0
                let threads = metrics.thread_count ?? 0
                let processCount = metrics.process_count ?? metrics.daemon_pids?.count ?? (metrics.pid == nil ? 0 : 1)
                let screens = metrics.health?.screens ?? 0
                let windows = metrics.health?.windows ?? 0
                let rate = metrics.health?.player_rate ?? 0

                MonitoringRow(label: "Daemon PID", value: metrics.pid.map(String.init) ?? "n/a")
                MonitoringRow(label: "Daemon Processes", value: "\(processCount)")
                MonitoringRow(label: "Running", value: metrics.running ? "Yes" : "No")
                MonitoringRow(label: "CPU", value: String(format: "%.1f%%", cpu))
                MonitoringRow(label: "Memory", value: String(format: "%.1f MB", memory))
                MonitoringRow(label: "Threads", value: "\(threads)")
                MonitoringRow(label: "Screens/Windows", value: "\(screens)/\(windows)")
                MonitoringRow(label: "Player Rate", value: String(format: "%.2fx", rate))

                if let pids = metrics.daemon_pids, !pids.isEmpty {
                    let rendered = pids.prefix(4).map(String.init).joined(separator: ", ")
                    let suffix = pids.count > 4 ? ", ..." : ""
                    Text("PIDs: \(rendered)\(suffix)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                if let reason = metrics.health?.reason, !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Health: \(reason)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }
            } else {
                Text("Collecting daemon metrics...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let error = viewModel.monitoringErrorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            HStack {
                Button {
                    viewModel.refreshMonitoring()
                } label: {
                    if viewModel.isMonitoringRefreshing {
                        Label("Refreshing…", systemImage: "arrow.clockwise")
                    } else {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isMonitoringRefreshing)
                Spacer()
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 20)
        .background(
            LiquidGlassView()
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(colorScheme == .dark ? 0.14 : 0.2), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.45 : 0.28), radius: 24, x: 0, y: 16)
    }
}

struct MonitoringRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
        }
    }
}

struct DownloadedWallpapersOverlay: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Color.black.opacity(colorScheme == .dark ? 0.42 : 0.28)
                .ignoresSafeArea()
                .onTapGesture {
                    viewModel.closeDownloadedWallpapers()
                }

            DownloadedWallpapersCard(viewModel: viewModel)
                .frame(maxWidth: 760)
                .padding(.horizontal, 24)
                .transition(
                    .asymmetric(
                        insertion: .scale(scale: 0.94).combined(with: .opacity),
                        removal: .opacity
                    )
                )
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.86), value: viewModel.isDownloadedWallpapersOpen)
        .zIndex(70)
    }
}

struct DownloadedWallpapersCard: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Downloaded Wallpapers", systemImage: "arrow.down.circle.fill")
                    .font(.headline.weight(.semibold))
                Spacer()
                Text("\(viewModel.downloadedCatalogWallpapers.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Button {
                    viewModel.closeDownloadedWallpapers()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }

            Divider()

            if viewModel.downloadedCatalogWallpapers.isEmpty {
                Text("No downloaded wallpapers yet. Use Download & Apply in the catalog.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(viewModel.downloadedCatalogWallpapers) { wallpaper in
                            HStack(spacing: 12) {
                                CatalogPreviewImage(
                                    url: wallpaper.previewImageURL,
                                    title: wallpaper.title,
                                    referer: wallpaper.sourcePageURL
                                )
                                .frame(width: 140, height: 80)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(wallpaper.title)
                                        .font(.subheadline.weight(.semibold))
                                        .lineLimit(1)
                                    Text("\(wallpaper.category) • \(wallpaper.attribution)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(wallpaper.localURL.lastPathComponent)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }

                                Spacer(minLength: 10)

                                Button {
                                    viewModel.applyDownloadedCatalogWallpaper(wallpaper)
                                } label: {
                                    Label("Apply", systemImage: "checkmark.circle")
                                }
                                .buttonStyle(.borderedProminent)
                            }
                            .padding(8)
                            .background(Color.black.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                }
                .frame(maxHeight: 360)
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 20)
        .background(
            LiquidGlassView()
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(colorScheme == .dark ? 0.14 : 0.2), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.45 : 0.28), radius: 24, x: 0, y: 16)
    }
}

struct ControlButtons: View {
    @ObservedObject var viewModel: AppViewModel
    let spacing: CGFloat
    let primaryButtonWidth: CGFloat
    let removeButtonWidth: CGFloat

    var body: some View {
        HStack(spacing: spacing) {
            startButton
                .frame(width: primaryButtonWidth)
            stopButton
                .frame(width: primaryButtonWidth)
            clearButton
                .frame(width: removeButtonWidth)
        }
    }

    private var startButton: some View {
        Button {
            viewModel.start()
        } label: {
            Label("Start", systemImage: "desktopcomputer")
                .lineLimit(1)
                .truncationMode(.tail)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!viewModel.canStart)
    }

    private var stopButton: some View {
        Button(role: .destructive) {
            viewModel.stop()
        } label: {
            Label("Stop", systemImage: "stop.circle")
                .lineLimit(1)
                .truncationMode(.tail)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .disabled(!viewModel.canStop)
    }

    private var clearButton: some View {
        Button(role: .destructive) {
            viewModel.clearWallpaper()
        } label: {
            Label("Remove Wallpaper", systemImage: "photo.slash")
                .lineLimit(1)
                .truncationMode(.tail)
                .minimumScaleFactor(0.78)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .disabled(!viewModel.canClearWallpaper)
    }
}

struct WallpaperCatalogView: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.colorScheme) private var colorScheme

    private var isDetailOpened: Bool {
        viewModel.selectedCatalogWallpaper != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Button {
                    viewModel.navigateBackFromCatalog()
                } label: {
                    Label(
                        isDetailOpened ? "Back" : "Close",
                        systemImage: isDetailOpened ? "chevron.left" : "xmark"
                    )
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.escape, modifiers: [])

                Text(viewModel.selectedCatalogWallpaper?.title ?? "Wallpaper Catalog")
                    .font(.headline.weight(.semibold))

                Spacer()

                if viewModel.selectedCatalogWallpaper == nil {
                    if viewModel.catalogIsRefreshing {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text("\(viewModel.catalogWallpapers.count)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    TextField("Search catalog", text: $viewModel.catalogSearchText)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 260)
                }
            }
            .zIndex(10)

            if let wallpaper = viewModel.selectedCatalogWallpaper {
                WallpaperCatalogDetailView(viewModel: viewModel, wallpaper: wallpaper)
                    .zIndex(0)
            } else {
                WallpaperCatalogGridView(viewModel: viewModel)
                    .zIndex(0)
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, maxHeight: 320, alignment: .topLeading)
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

struct WallpaperCatalogGridView: View {
    @ObservedObject var viewModel: AppViewModel

    private let columns = [GridItem(.adaptive(minimum: 220), spacing: 12)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(viewModel.filteredCatalogWallpapers) { wallpaper in
                    Button {
                        viewModel.openCatalogWallpaper(wallpaper)
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            CatalogPreviewImage(
                                url: wallpaper.previewImageURL,
                                title: wallpaper.title,
                                referer: wallpaper.sourcePageURL
                            )
                                .frame(height: 96)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                            Text(wallpaper.title)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Text(wallpaper.category)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color.black.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }
}

struct WallpaperCatalogDetailView: View {
    @ObservedObject var viewModel: AppViewModel
    let wallpaper: CatalogWallpaper

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CatalogPreviewImage(
                url: wallpaper.previewImageURL,
                title: wallpaper.title,
                referer: wallpaper.sourcePageURL
            )
                .frame(height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Text(wallpaper.title)
                .font(.headline)

            Text("Category: \(wallpaper.category) • Source: \(wallpaper.attribution)")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(spacing: 10) {
                Button {
                    viewModel.applyCatalogWallpaper(wallpaper)
                } label: {
                    if viewModel.isDownloading(wallpaper) {
                        Label("Downloading…", systemImage: "arrow.down.circle")
                    } else {
                        Label("Download & Apply", systemImage: "arrow.down.circle")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canApplyCatalogWallpaper)

                if let sourceURL = wallpaper.sourcePageURL {
                    Button {
                        NSWorkspace.shared.open(sourceURL)
                    } label: {
                        Label("Open Source", systemImage: "link")
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()
            }
        }
    }
}

struct CatalogPreviewImage: View {
    let url: URL?
    let title: String
    let referer: URL?
    @StateObject private var loader = CatalogPreviewImageLoader()

    var body: some View {
        Group {
            if let image = loader.image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                previewFallback
            }
        }
        .task(id: cacheKey) {
            loader.load(url: url, referer: referer)
        }
        .onDisappear {
            loader.cancel()
        }
    }

    private var cacheKey: String {
        [
            url?.absoluteString ?? "nil",
            referer?.absoluteString ?? "nil",
        ].joined(separator: "|")
    }

    private var previewFallback: some View {
        ZStack {
            LinearGradient(
                colors: [Color.blue.opacity(0.55), Color.cyan.opacity(0.35), Color.indigo.opacity(0.45)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(.white)
                .padding(8)
                .lineLimit(2)
        }
    }
}

final class CatalogPreviewImageLoader: ObservableObject {
    @Published private(set) var image: NSImage?

    private static let cache = NSCache<NSURL, NSImage>()
    private var task: Task<Void, Never>?

    func load(url: URL?, referer: URL?) {
        task?.cancel()
        task = nil
        image = nil

        guard let url else {
            return
        }
        if let cached = Self.cache.object(forKey: url as NSURL) {
            image = cached
            return
        }

        task = Task {
            var request = URLRequest(url: url)
            request.timeoutInterval = 20
            request.setValue("AuraFlow/1.1", forHTTPHeaderField: "User-Agent")
            request.setValue("image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
            if let referer {
                request.setValue(referer.absoluteString, forHTTPHeaderField: "Referer")
            }

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard !Task.isCancelled else { return }
                if let httpResponse = response as? HTTPURLResponse,
                   !(200...299).contains(httpResponse.statusCode) {
                    return
                }
                await MainActor.run {
                    guard let decoded = NSImage(data: data) else { return }
                    Self.cache.setObject(decoded, forKey: url as NSURL)
                    self.image = decoded
                }
            } catch {
                // Keep fallback preview on failures.
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}

struct SpeedOverlay: View {
    @ObservedObject var viewModel: AppViewModel
    @Binding var isAdjustingSpeed: Bool
    let availableWidth: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    private var pillWidth: CGFloat {
        min(max(availableWidth * 0.46, 420), 720)
    }

    private var compactControlSize: ControlSize {
        availableWidth < 900 ? .small : .regular
    }

    var body: some View {
        HStack(spacing: 14) {
            Label("Speed", systemImage: "speedometer")
                .labelStyle(.titleAndIcon)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            Slider(
                value: Binding(
                    get: { viewModel.playbackSpeed },
                    set: { newValue in viewModel.setPreviewPlaybackSpeed(newValue) }
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
            .frame(maxWidth: .infinity)

            Text(String(format: "%.2fx", viewModel.playbackSpeed))
                .monospacedDigit()
                .foregroundColor(.secondary)
                .lineLimit(1)
                .frame(minWidth: 64, alignment: .trailing)
        }
        .controlSize(compactControlSize)
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
        .frame(width: pillWidth)
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
    let videoGravity: AVLayerVideoGravity

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .none
        view.videoGravity = videoGravity
        view.allowsPictureInPicturePlayback = false
        view.updatesNowPlayingInfoCenter = false
        view.showsFullScreenToggleButton = false
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        nsView.player = player
        nsView.videoGravity = videoGravity
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

struct DisabledOverlay: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(Color.black.opacity(0.5))
            .overlay(
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title3.weight(.semibold))
                    Text("Python bridge unavailable")
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
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let currentWindow = view.window {
                configureWindowForClientDecorations(currentWindow)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let currentWindow = nsView.window {
                configureWindowForClientDecorations(currentWindow)
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
        if viewModel.isCatalogOpen {
            hideWorkItem?.cancel()
            hideWorkItem = nil
            withAnimation(.easeInOut(duration: 0.2)) {
                controlsVisible = true
            }
            return
        }

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
        let fallback = LiquidGlassFallbackView()
        fallback.glassStyle = material
        return fallback
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let fallback = nsView as? LiquidGlassFallbackView else { return }
        fallback.glassStyle = material
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
