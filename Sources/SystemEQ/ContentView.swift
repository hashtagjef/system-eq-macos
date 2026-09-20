import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var controller: AudioController
    @State private var isShowingSavePreset = false
    @State private var isShowingDeleteConfirmation = false
    @State private var presetName = ""

    var body: some View {
        ZStack {
            TranslucentWindowBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                equalizer
                footer
            }
        }
        .frame(
            minWidth: 560,
            idealWidth: 960,
            minHeight: controller.isLevelMeterVisible ? 614 : 590,
            idealHeight: controller.isLevelMeterVisible ? 684 : 660
        )
        .background(WindowMaterialConfigurator())
        .animation(.snappy(duration: 0.22), value: controller.isLevelMeterVisible)
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                brand
                    .frame(width: 250, alignment: .leading)

                Spacer(minLength: 8)
                presetControls
                powerButton
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    brand
                    Spacer(minLength: 8)
                    powerButton
                }

                presetControls
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.45)
        }
    }

    private var brand: some View {
        HStack(spacing: 14) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 38, height: 38)
                .liquidGlass(.clear, interactive: false, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text("System EQ")
                    .font(.system(size: 22, weight: .semibold))
                statusLabel
                    .font(.caption)
                    .lineLimit(1)
            }
        }
    }

    private var presetControls: some View {
        HStack(spacing: 8) {
            Picker("Preset", selection: presetSelection) {
                Section("Built-in") {
                    ForEach(EQPreset.builtIn) { preset in
                        Text(preset.name).tag(preset.id)
                    }
                }
                if !controller.userPresets.isEmpty {
                    Section("Saved") {
                        ForEach(controller.userPresets) { preset in
                            Text(preset.name).tag(preset.id)
                        }
                    }
                }
                if controller.selectedPresetID == "custom" {
                    Text("Custom").tag("custom")
                }
            }
            .labelsHidden()
            .frame(minWidth: 140, idealWidth: 170, maxWidth: 210)

            Button {
                presetName = controller.preset(withID: controller.selectedPresetID)?.name ?? ""
                isShowingSavePreset = true
            } label: {
                Image(systemName: "square.and.arrow.down")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .liquidGlass(.clear, interactive: true, in: Circle())
            .help("Save current settings as a preset")
            .popover(isPresented: $isShowingSavePreset, arrowEdge: .top) {
                SavePresetPopover(name: $presetName) {
                    controller.savePreset(named: presetName)
                    isShowingSavePreset = false
                }
            }

            Button {
                controller.toggleLevelMeter()
            } label: {
                Image(systemName: "chart.bar.fill")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .foregroundStyle(controller.isLevelMeterVisible ? Color.accentColor : Color.primary)
            .liquidGlass(
                .clear,
                tint: controller.isLevelMeterVisible ? Color.accentColor.opacity(0.2) : nil,
                interactive: true,
                in: Circle()
            )
            .help(controller.isLevelMeterVisible ? "Hide per-band levels" : "Show per-band levels")
            .accessibilityLabel(controller.isLevelMeterVisible ? "Hide per-band levels" : "Show per-band levels")

            if controller.userPresets.contains(where: { $0.id == controller.selectedPresetID }) {
                Button(role: .destructive) {
                    isShowingDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .liquidGlass(.clear, interactive: true, in: Circle())
                .help("Delete selected preset")
                .confirmationDialog(
                    "Delete this preset?",
                    isPresented: $isShowingDeleteConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Delete Preset", role: .destructive) {
                        controller.deleteSelectedPreset()
                    }
                }
            }
        }
        .padding(6)
        .liquidGlass(.regular, interactive: false, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var powerButton: some View {
        Button {
            controller.toggleEngine()
        } label: {
            Image(systemName: "power")
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 38, height: 38)
        }
        .buttonStyle(.plain)
        .foregroundStyle(controller.state.isRunning ? Color.orange : Color.green)
        .liquidGlass(
            .regular,
            tint: controller.state.isRunning ? .orange.opacity(0.22) : .green.opacity(0.22),
            interactive: true,
            in: Circle()
        )
        .disabled(controller.state == .starting)
        .help(controller.state.isRunning ? "Turn System EQ off" : "Turn System EQ on")
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch controller.state {
        case .off:
            Label("Off", systemImage: "circle")
                .foregroundStyle(.secondary)
        case .starting:
            Label("Starting...", systemImage: "waveform")
                .foregroundStyle(.secondary)
        case .running(let deviceName):
            Label("Processing through \(deviceName)", systemImage: "waveform.circle.fill")
                .foregroundStyle(.green)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .lineLimit(2)
        }
    }

    private var equalizer: some View {
        VStack(spacing: 16) {
            HStack {
                Label("Equalizer", systemImage: "slider.vertical.3")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Stepper(
                    "\(controller.bands.count) bands",
                    onIncrement: controller.addBand,
                    onDecrement: controller.removeLastBand
                )
                .disabled(!controller.canAddBand && !controller.canRemoveBand)
                .help("Add a band or remove the rightmost band")

                Button {
                    if let flat = EQPreset.builtIn.first {
                        controller.applyPreset(flat)
                    }
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .liquidGlass(.clear, interactive: true, in: Circle())
                .help("Reset all bands")
            }
            .frame(maxWidth: .infinity)

            GeometryReader { geometry in
                let metrics = BandLayoutMetrics(
                    availableSize: geometry.size,
                    bandCount: controller.bands.count,
                    showsLevels: controller.isLevelMeterVisible
                )

                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: metrics.spacing) {
                        ForEach(Array(controller.bands.enumerated()), id: \.element.id) { index, band in
                            BandSlider(
                                band: band,
                                rmsDecibels: controller.audioLevels.rmsDecibels(at: index),
                                peakDecibels: controller.audioLevels.peakDecibels(at: index),
                                showsLevel: controller.isLevelMeterVisible,
                                sliderLength: metrics.sliderLength,
                                onGainChange: { controller.setGain($0, at: index) },
                                onFrequencyChange: { controller.setFrequency($0, at: index) },
                                onFilterChange: { controller.setFilterType($0, at: index) },
                                onQualityChange: { controller.setQuality($0, at: index) }
                            )
                            .frame(width: metrics.bandWidth)
                        }
                    }
                    .frame(minWidth: geometry.size.width, alignment: .center)
                    .padding(.horizontal, 2)
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.never)
            }
            .frame(maxWidth: .infinity)
            .frame(maxHeight: .infinity)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .frame(maxHeight: .infinity)
    }

    private var footer: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 22) {
                preampControl
                    .frame(width: 290)
                toggleControls
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 12) {
                preampControl
                toggleControls
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Divider().opacity(0.45)
        }
    }

    private var preampControl: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Preamp", systemImage: "dial.medium")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(String(format: "%+.1f dB", controller.effectivePreamp))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(
                value: Binding(
                    get: { Double(controller.preamp) },
                    set: {
                        controller.preamp = Float($0)
                        controller.controlsChanged()
                    }
                ),
                in: -12...6,
                step: 0.5
            )
        }
    }

    private var toggleControls: some View {
        HStack(spacing: 18) {
            Toggle("Automatic headroom", isOn: Binding(
                get: { controller.automaticHeadroom },
                set: {
                    controller.automaticHeadroom = $0
                    controller.controlsChanged()
                }
            ))
            .toggleStyle(.switch)

            Toggle("Bypass filters", isOn: Binding(
                get: { controller.bypassed },
                set: {
                    controller.bypassed = $0
                    controller.controlsChanged(markPresetCustom: false)
                }
            ))
            .toggleStyle(.switch)
        }
    }

    private var presetSelection: Binding<String> {
        Binding(
            get: { controller.selectedPresetID },
            set: { id in
                guard let preset = controller.preset(withID: id) else { return }
                controller.applyPreset(preset)
            }
        )
    }

}

private struct BandLevelMeter: View {
    let frequency: Float
    let rmsDecibels: Float
    let peakDecibels: Float

    var body: some View {
        VStack(spacing: 3) {
            GeometryReader { geometry in
                let rmsWidth = geometry.size.width * normalized(rmsDecibels)
                let peakPosition = geometry.size.width * normalized(peakDecibels)

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.primary.opacity(0.10))

                    LinearGradient(
                        colors: [.green, .green, .yellow, .orange, .red],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .mask(alignment: .leading) {
                        Capsule()
                            .frame(width: rmsWidth)
                    }

                    if peakDecibels > BandAudioLevels.floorDecibels {
                        Rectangle()
                            .fill(.primary.opacity(0.9))
                            .frame(width: 2)
                            .offset(x: max(0, min(peakPosition - 1, geometry.size.width - 2)))
                    }
                }
            }
            .frame(height: 5)

            Text(levelText)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 54)
        }
        .frame(width: 54, height: 18)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(FrequencyText.format(frequency)) band level")
        .accessibilityValue(levelText)
    }

    private var levelText: String {
        peakDecibels <= BandAudioLevels.floorDecibels
            ? "-inf dB"
            : String(format: "%.0f dB", peakDecibels)
    }

    private func normalized(_ decibels: Float) -> CGFloat {
        let value = CGFloat(
            (decibels - BandAudioLevels.floorDecibels) / -BandAudioLevels.floorDecibels
        )
        return min(max(value, 0), 1)
    }
}

private struct SavePresetPopover: View {
    @Binding var name: String
    let onSave: () -> Void
    @FocusState private var isNameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Save Preset")
                .font(.headline)

            TextField("Preset name", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($isNameFocused)
                .onSubmit(saveIfPossible)

            HStack {
                Spacer()
                Button("Save", action: saveIfPossible)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedName.isEmpty)
            }
        }
        .padding(16)
        .frame(width: 260)
        .onAppear { isNameFocused = true }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func saveIfPossible() {
        guard !trimmedName.isEmpty else { return }
        onSave()
    }
}

private struct BandSlider: View {
    let band: EQBand
    let rmsDecibels: Float
    let peakDecibels: Float
    let showsLevel: Bool
    let sliderLength: CGFloat
    let onGainChange: (Float) -> Void
    let onFrequencyChange: (Float) -> Void
    let onFilterChange: (EQFilterType) -> Void
    let onQualityChange: (Float) -> Void
    @State private var frequencyText: String
    @State private var qualityText: String
    @FocusState private var isEditingFrequency: Bool
    @FocusState private var isEditingQuality: Bool

    init(
        band: EQBand,
        rmsDecibels: Float,
        peakDecibels: Float,
        showsLevel: Bool,
        sliderLength: CGFloat,
        onGainChange: @escaping (Float) -> Void,
        onFrequencyChange: @escaping (Float) -> Void,
        onFilterChange: @escaping (EQFilterType) -> Void,
        onQualityChange: @escaping (Float) -> Void
    ) {
        self.band = band
        self.rmsDecibels = rmsDecibels
        self.peakDecibels = peakDecibels
        self.showsLevel = showsLevel
        self.sliderLength = sliderLength
        self.onGainChange = onGainChange
        self.onFrequencyChange = onFrequencyChange
        self.onFilterChange = onFilterChange
        self.onQualityChange = onQualityChange
        _frequencyText = State(initialValue: FrequencyText.format(band.frequency))
        _qualityText = State(initialValue: QualityText.format(band.quality))
    }

    var body: some View {
        VStack(spacing: 10) {
            Text(band.filterType.usesGain ? String(format: "%+.1f", band.gain) : "--")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(band.filterType.usesGain && abs(band.gain) > 0.01 ? Color.primary : Color.secondary)
                .frame(width: 44)

            if showsLevel {
                BandLevelMeter(
                    frequency: band.frequency,
                    rmsDecibels: rmsDecibels,
                    peakDecibels: peakDecibels
                )
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }

            Slider(
                value: Binding(
                    get: { Double(band.gain) },
                    set: { onGainChange(Float($0)) }
                ),
                in: -12...12,
                step: 0.5
            )
            .rotationEffect(.degrees(-90))
            .frame(width: sliderLength, height: 30)
            .frame(width: 48, height: sliderLength + 10)
            .disabled(!band.filterType.usesGain)
            .opacity(band.filterType.usesGain ? 1 : 0.42)

            TextField("Hz", text: $frequencyText)
                .textFieldStyle(.roundedBorder)
                .font(.system(.caption, design: .monospaced).weight(.medium))
                .multilineTextAlignment(.center)
                .frame(width: 56)
                .focused($isEditingFrequency)
                .onSubmit(commitFrequency)
                .onChange(of: isEditingFrequency) { _, isFocused in
                    if !isFocused { commitFrequency() }
                }

            Menu {
                ForEach(EQFilterType.allCases) { filterType in
                    Button {
                        onFilterChange(filterType)
                    } label: {
                        if filterType == band.filterType {
                            Label(filterType.name, systemImage: "checkmark")
                        } else {
                            Text(filterType.name)
                        }
                    }
                }
            } label: {
                Text(band.filterType.abbreviation)
                    .font(.caption2.weight(.semibold))
                    .frame(width: 40)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 56)
            .help(band.filterType.name)
            .accessibilityLabel("Filter: \(band.filterType.name)")

            HStack(spacing: 3) {
                Text("Q")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                TextField("Q", text: $qualityText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.caption2, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .frame(width: 42)
                    .focused($isEditingQuality)
                    .onSubmit(commitQuality)
                    .onChange(of: isEditingQuality) { _, isFocused in
                        if !isFocused { commitQuality() }
                    }
            }
            .frame(width: 64)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 3)
        .frame(maxWidth: .infinity)
        .liquidGlass(.clear, interactive: false, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onChange(of: band.frequency) { _, newFrequency in
            frequencyText = FrequencyText.format(newFrequency)
        }
        .onChange(of: band.quality) { _, newQuality in
            qualityText = QualityText.format(newQuality)
        }
    }

    private func commitFrequency() {
        guard let frequency = FrequencyText.parse(frequencyText) else {
            frequencyText = FrequencyText.format(band.frequency)
            return
        }
        frequencyText = FrequencyText.format(frequency)
        if frequency != band.frequency {
            onFrequencyChange(frequency)
        }
    }

    private func commitQuality() {
        guard let quality = QualityText.parse(qualityText) else {
            qualityText = QualityText.format(band.quality)
            return
        }
        qualityText = QualityText.format(quality)
        if quality != band.quality {
            onQualityChange(quality)
        }
    }
}

private struct BandLayoutMetrics {
    let spacing: CGFloat = 10
    let bandWidth: CGFloat
    let sliderLength: CGFloat

    init(availableSize: CGSize, bandCount: Int, showsLevels: Bool) {
        let count = max(bandCount, 1)
        let totalSpacing = spacing * CGFloat(max(count - 1, 0))
        let fittedWidth = (availableSize.width - totalSpacing - 4) / CGFloat(count)
        bandWidth = min(max(fittedWidth, 62), 88)
        sliderLength = min(max(availableSize.height - (showsLevels ? 166 : 142), 130), 360)
    }
}

private extension View {
    @ViewBuilder
    func liquidGlass<S: Shape>(
        _ glass: GlassStyle,
        tint: Color? = nil,
        interactive: Bool,
        in shape: S
    ) -> some View {
        if #available(macOS 26.0, *) {
            switch glass {
            case .regular:
                self.glassEffect(.regular.tint(tint).interactive(interactive), in: shape)
            case .clear:
                self.glassEffect(.clear.tint(tint).interactive(interactive), in: shape)
            }
        } else {
            self
                .background(.regularMaterial, in: shape)
                .overlay {
                    shape.stroke(Color.white.opacity(0.18), lineWidth: 0.5)
                }
        }
    }
}

private enum GlassStyle {
    case regular
    case clear
}

private struct TranslucentWindowBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

private struct WindowMaterialConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        configureWindow(for: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        configureWindow(for: nsView)
    }

    private func configureWindow(for view: NSView) {
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.isOpaque = false
            window.backgroundColor = .clear
            window.titlebarAppearsTransparent = true
        }
    }
}
