import SwiftUI

struct SoundSheet: View {
    @Environment(PomodoroEngine.self) private var engine
    @Environment(\.dismiss) private var dismiss

    private var settings = AppSettings.shared

    /// Qué fase se está editando.
    private enum Tab: String, CaseIterable, Identifiable {
        case work, rest
        var id: String { rawValue }
        var title: String { self == .work ? "Concentración" : "Descanso" }
    }

    /// Copia editable de los ajustes. Cada cambio se aplica al momento para que
    /// cerrar la hoja nunca restaure por sorpresa un sonido anterior.
    private struct Draft: Equatable {
        var workSound: SoundKind
        var breakFollowsWork: Bool
        var breakSound: SoundKind
        var volume: Double
        var beatHz: Double
        var carrierHz: Double
        var noiseMix: Double
        var mixWithOthers: Bool

        func sound(for tab: Tab) -> SoundKind {
            tab == .work ? workSound : (breakFollowsWork ? workSound : breakSound)
        }
    }

    @State private var tab: Tab = .work
    @State private var draft = Draft(
        workSound: .none, breakFollowsWork: true, breakSound: .none,
        volume: 0.55, beatHz: 10, carrierHz: 200, noiseMix: 0.35, mixWithOthers: true
    )
    @State private var category: SoundCategory = .nature
    @State private var isPreviewing = false

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Picker("Fase", selection: $tab) {
                        ForEach(Tab.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    if tab == .rest {
                        Toggle("Igual que en concentración", isOn: $draft.breakFollowsWork)
                            .font(.system(.subheadline, design: .rounded, weight: .medium))
                            .tint(engine.phase.tint)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Theme.card)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .stroke(Theme.stroke, lineWidth: 1)
                                    }
                            }
                    }

                    Group {
                        volumeSection
                        Button(isPreviewing ? "Detener escucha" : "Escuchar selección",
                               systemImage: isPreviewing ? "stop.fill" : "play.fill") {
                            if isPreviewing {
                                isPreviewing = false
                                AudioService.shared.apply(SoundConfig())
                            } else {
                                preview()
                            }
                        }
                        .disabled(previewedSound.isSilent)
                        .accessibilityIdentifier("sound.preview")
                    }

                    if tab == .work || !draft.breakFollowsWork {
                        soundCard(.none)
                        Picker("Categoría", selection: $category) {
                            ForEach(SoundCategory.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(category.sounds) { kind in
                                soundCard(kind)
                            }
                        }

                        Label("Elige un sonido para escucharlo y aplicarlo. Al iniciar la app, el fondo siempre estará en silencio. Todos los sonidos están disponibles sin conexión.",
                              systemImage: "hand.tap")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.white.opacity(0.45))
                            .padding(.horizontal, 4)
                    } else {
                        Text("El descanso usará el mismo sonido que la concentración.")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(.white.opacity(0.5))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if previewedSound == .binaural {
                        binauralSection
                    }

                    mixSection
                }
                .padding(20)
            }
            .background(Theme.base)
            .navigationTitle("Sonido")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
        .tint(engine.phase.tint)
        .preferredColorScheme(.dark)
        .animation(.snappy(duration: 0.25), value: tab)
        .onAppear(perform: loadDraft)
        .onChange(of: tab) { _, _ in
            category = previewedSound.category ?? .nature
            if isPreviewing { preview() }
        }
        .onChange(of: draft.breakFollowsWork) { _, _ in
            saveDraft()
            if isPreviewing { preview() }
        }
        .onDisappear {
            saveDraft()
            // Si se estaba comparando el sonido de la otra fase, al cerrar
            // vuelve a aplicar el que corresponde a la fase actual.
            AudioService.shared.apply(settings.soundConfig(for: engine.phase))
        }
    }

    // MARK: - Borrador

    private var previewedSound: SoundKind { draft.sound(for: tab) }

    private func loadDraft() {
        draft = Draft(
            workSound: settings.sound,
            breakFollowsWork: settings.breakFollowsWorkSound,
            breakSound: settings.breakSound,
            volume: settings.soundVolume,
            beatHz: settings.binauralBeatHz,
            carrierHz: settings.binauralCarrierHz,
            noiseMix: settings.binauralNoiseMix,
            mixWithOthers: settings.mixWithOtherAudio
        )
        tab = engine.phase.isBreak ? .rest : .work
        category = previewedSound.category ?? .nature
        isPreviewing = !settings.sound(for: engine.phase).isSilent
    }

    /// Suena lo que se está editando, sin tocar los ajustes guardados.
    private func preview() {
        isPreviewing = !previewedSound.isSilent
        AudioService.shared.apply(
            SoundConfig(
                kind: previewedSound,
                volume: draft.volume,
                beatHz: draft.beatHz,
                carrierHz: draft.carrierHz,
                noiseMix: draft.noiseMix,
                mixWithOthers: draft.mixWithOthers
            )
        )
    }

    private func saveDraft() {
        settings.sound = draft.workSound
        settings.breakFollowsWorkSound = draft.breakFollowsWork
        settings.breakSound = draft.breakSound
        settings.soundVolume = draft.volume
        settings.binauralBeatHz = draft.beatHz
        settings.binauralCarrierHz = draft.carrierHz
        settings.binauralNoiseMix = draft.noiseMix
        settings.mixWithOtherAudio = draft.mixWithOthers
    }

    // MARK: - Piezas

    private func soundCard(_ kind: SoundKind) -> some View {
        let isSelected = previewedSound == kind
        return Button {
            if tab == .work {
                draft.workSound = kind
            } else {
                draft.breakSound = kind
            }
            saveDraft()
            preview()
            Haptics.impact(.light)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: kind.symbol)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(isSelected ? engine.phase.tint : .white.opacity(0.75))
                    Spacer()
                    if isSelected, !kind.isSilent {
                        Image(systemName: isPreviewing ? "speaker.wave.2.fill" : "checkmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(engine.phase.tint)
                    }
                }
                Text(kind.title)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white)
                Text(kind.subtitle)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isSelected ? engine.phase.tint.opacity(0.16) : Theme.card)
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(isSelected ? engine.phase.tint.opacity(0.75) : Theme.stroke, lineWidth: 1)
                    }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("sound.\(kind.id)")
        .accessibilityLabel(kind.title)
        .accessibilityHint(kind.subtitle)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var volumeSection: some View {
        card(title: "Volumen") {
            HStack(spacing: 14) {
                Image(systemName: "speaker.fill")
                    .foregroundStyle(.white.opacity(0.5))
                Slider(value: $draft.volume, in: 0...1)
                    .onChange(of: draft.volume) { _, _ in
                        saveDraft()
                        if isPreviewing { preview() }
                    }
                Image(systemName: "speaker.wave.3.fill")
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    private var mixSection: some View {
        card(title: "Con otras apps") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Dejar sonar la música", isOn: $draft.mixWithOthers)
                    .font(.system(.subheadline, design: .rounded))
                    .tint(engine.phase.tint)
                    .onChange(of: draft.mixWithOthers) { _, _ in
                        saveDraft()
                        if isPreviewing { preview() }
                    }

                Text(draft.mixWithOthers
                     ? "El fondo se mezcla con lo que ya estés escuchando."
                     : "El fondo interrumpe cualquier otro audio.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))

                if previewedSound == .binaural, draft.mixWithOthers {
                    Label("Los tonos binaurales se reproducen sin mezclar con otras apps.",
                          systemImage: "exclamationmark.circle")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
        }
    }

    private var binauralSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            card(title: "Frecuencia del batido") {
                VStack(alignment: .leading, spacing: 14) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 90))], spacing: 8) {
                        ForEach(BinauralPreset.allCases) { preset in
                            presetChip(preset)
                        }
                    }

                    slider("Batido", value: $draft.beatHz, in: 1...45,
                           text: String(format: "%.1f Hz", draft.beatHz))
                    slider("Tono base", value: $draft.carrierHz, in: 80...400,
                           text: "\(Int(draft.carrierHz)) Hz")
                    slider("Colchón de ruido rosa", value: $draft.noiseMix, in: 0...0.8,
                           text: "\(Int(draft.noiseMix * 100))%")
                }
            }

            Label(
                "Los binaurales solo funcionan con auriculares: cada oído recibe un tono distinto y el batido nace de la diferencia.",
                systemImage: "headphones"
            )
            .font(.system(.caption, design: .rounded))
            .foregroundStyle(.white.opacity(0.5))
            .padding(.horizontal, 4)
        }
    }

    private func slider(
        _ title: String,
        value: Binding<Double>,
        in range: ClosedRange<Double>,
        text: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(text).foregroundStyle(.white.opacity(0.6))
            }
            .font(.system(.caption, design: .rounded))
            Slider(value: value, in: range)
                .onChange(of: value.wrappedValue) { _, _ in
                    saveDraft()
                    if isPreviewing { preview() }
                }
        }
    }

    private func presetChip(_ preset: BinauralPreset) -> some View {
        let isSelected = abs(draft.beatHz - preset.hz) < 0.05
        return Button {
            draft.beatHz = preset.hz
            saveDraft()
            if isPreviewing { preview() }
            Haptics.impact(.light)
        } label: {
            VStack(spacing: 2) {
                Text(preset.title)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                Text(preset.caption)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? engine.phase.tint.opacity(0.22) : Color.white.opacity(0.05))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(isSelected ? engine.phase.tint.opacity(0.7) : Theme.stroke, lineWidth: 1)
                    }
            }
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(preset.title), \(preset.caption)")
        .accessibilityValue("\(Int(preset.hz)) hercios")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func card<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(.footnote, design: .rounded, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
                .textCase(.uppercase)
                .kerning(1)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.card)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Theme.stroke, lineWidth: 1)
                }
        }
    }
}
