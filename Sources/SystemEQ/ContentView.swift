import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var controller: AudioController
    @State private var isShowingSavePreset = false
    @State private var isShowingDeleteConfirmation = false
    @State private var presetName = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            equalizer
            Divider()
            footer
        }
        .frame(minWidth: 820, idealWidth: 920, minHeight: 540, idealHeight: 620)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("System EQ")
                    .font(.system(size: 26, weight: .semibold))
                statusLabel
            }

            Spacer()

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
            .frame(width: 150)

            Button {
                presetName = controller.preset(withID: controller.selectedPresetID)?.name ?? ""
                isShowingSavePreset = true
            } label: {
                Image(systemName: "square.and.arrow.down")
            }
            .help("Save current settings as a preset")
            .popover(isPresented: $isShowingSavePreset, arrowEdge: .top) {
                SavePresetPopover(name: $presetName) {
                    controller.savePreset(named: presetName)
                    isShowingSavePreset = false
                }
            }

            if controller.userPresets.contains(where: { $0.id == controller.selectedPresetID }) {
                Button(role: .destructive) {
                    isShowingDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
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

            Button {
                controller.toggleEngine()
            } label: {
                Label(controller.state.isRunning ? "Turn Off" : "Turn On", systemImage: "power")
                    .frame(minWidth: 92)
            }
            .buttonStyle(.borderedProminent)
            .tint(controller.state.isRunning ? .orange : .green)
            .disabled(controller.state == .starting)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
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
        VStack(spacing: 20) {
            HStack {
                Text("EQUALIZER")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Stepper(
                    "\(controller.bands.count) bands",
                    onIncrement: controller.addBand,
                    onDecrement: controller.removeLastBand
                )
                .disabled(!controller.canAddBand && !controller.canRemoveBand)
                .help("Add a band or remove the rightmost band")

                Button("Reset") {
                    if let flat = EQPreset.builtIn.first {
                        controller.applyPreset(flat)
                    }
                }
                .buttonStyle(.plain)
            }

            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 18) {
                    ForEach(Array(controller.bands.enumerated()), id: \.element.id) { index, band in
                        BandSlider(
                            band: band,
                            onGainChange: { controller.setGain($0, at: index) },
                            onFrequencyChange: { controller.setFrequency($0, at: index) },
                            onFilterChange: { controller.setFilterType($0, at: index) },
                            onQualityChange: { controller.setQuality($0, at: index) }
                        )
                        .frame(width: 64)
                    }
                }
                .padding(.horizontal, 2)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        .frame(maxHeight: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Preamp")
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
            .frame(width: 270)

            Toggle("Automatic headroom", isOn: Binding(
                get: { controller.automaticHeadroom },
                set: {
                    controller.automaticHeadroom = $0
                    controller.controlsChanged()
                }
            ))

            Toggle("Bypass filters", isOn: Binding(
                get: { controller.bypassed },
                set: {
                    controller.bypassed = $0
                    controller.controlsChanged(markPresetCustom: false)
                }
            ))

            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
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
        onGainChange: @escaping (Float) -> Void,
        onFrequencyChange: @escaping (Float) -> Void,
        onFilterChange: @escaping (EQFilterType) -> Void,
        onQualityChange: @escaping (Float) -> Void
    ) {
        self.band = band
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

            Slider(
                value: Binding(
                    get: { Double(band.gain) },
                    set: { onGainChange(Float($0)) }
                ),
                in: -12...12,
                step: 0.5
            )
            .rotationEffect(.degrees(-90))
            .frame(width: 240, height: 30)
            .frame(width: 48, height: 250)
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
        .frame(maxWidth: .infinity)
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
