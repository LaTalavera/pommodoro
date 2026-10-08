import SwiftUI
import SwiftData

struct TimerView: View {
    @Environment(\.calendar) private var calendar
    @Query private var sessions: [Session]
    @Environment(PomodoroEngine.self) private var engine
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    #if os(macOS)
    @Environment(\.openSettings) private var openSettings
    #endif
    /// En iPhone, clase de tamaño vertical compacta == apaisado. Se usa en vez
    /// de comparar ancho/alto de un GeometryReader porque así los modificadores
    /// de fuera del árbol de layout (barra de estado, animaciones) también
    /// pueden leerlo.
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    private var focus = FocusStatusMonitor.shared

    /// Deja que el reloj crezca con el ajuste de tamaño de texto del sistema,
    /// partiendo del tamaño calculado a partir del anillo.
    @ScaledMetric(relativeTo: .largeTitle) private var clockScale: Double = 1

    private var settings = AppSettings.shared

    @State private var showSettings = false
    @State private var showSounds = false
    @State private var showTask = false
    @State private var showHistory = false
    @State private var showInterruptionChoice = false
    /// El banner de "objetivo cumplido" se muestra una vez y se puede cerrar;
    /// no vuelve a aparecer solo hasta el siguiente bloque que cruce el objetivo.
    @State private var showGoalReached = false
    @State private var reachedGoalSummary = ""
    /// Modo inmersivo: con el reloj en marcha los controles se retiran para que
    /// solo quede la cuenta atrás. Un toque en cualquier sitio los devuelve.
    @State private var immersive = false
    @State private var dimTask: Task<Void, Never>?
    /// Minutos que marca el dedo mientras se arrastra sobre el anillo.
    @State private var draggedMinutes: Int?

    #if os(iOS)
    private var isLandscape: Bool { UIDevice.current.userInterfaceIdiom == .phone && verticalSizeClass == .compact }
    #else
    /// El apaisado "de sobremesa" es cosa del iPhone; en el Mac la ventana se
    /// adapta por tamaño (tablet/retrato) y no hay clase compacta vertical.
    private let isLandscape = false
    #endif

    var body: some View {
        GeometryReader { geometry in
            if geometry.size.width >= 600 && geometry.size.height >= 500 {
                tabletBody(size: geometry.size)
            } else if isLandscape {
                landscapeBody
            } else {
                portraitBody
            }
        }
        .preferredColorScheme(.dark)
        .hidingSystemChrome(isLandscape || (engine.isRunning && immersive))
        #if os(macOS)
        // En el Mac, mover el ratón devuelve los controles, como en un
        // reproductor de vídeo. El clic en el fondo no llega: la vista con
        // scroll del diseño ancho se lo queda.
        .onContinuousHover { phase in
            guard case .active = phase, engine.isRunning else { return }
            immersive = false
            scheduleDim()
        }
        #endif
        .animation(.easeInOut(duration: 0.45), value: immersive)
        .animation(.easeInOut(duration: 0.3), value: isLandscape)
        .onChange(of: engine.isRunning) { _, isRunning in
            scheduleDim()
            updateFocusPolling(isRunning: isRunning)
        }
        .onChange(of: goalProgress) { old, new in
            if DailyGoal.shouldCelebrate(before: old, after: new, lastCelebrationDay: settings.lastGoalCelebrationDay) {
                settings.lastGoalCelebrationDay = new.day
                reachedGoalSummary = new.achievementText
                showGoalReached = true
            }
        }
        .onChange(of: engine.phase) { _, newPhase in
            wakeControls()
            // Cada fase puede tener su propio fondo sonoro.
            AudioService.shared.apply(settings.soundConfig(for: newPhase))
        }
        .onChange(of: scenePhase) { _, new in
            if new == .active {
                engine.sync()
                engine.refreshLiveActivity()
                AudioService.shared.resumeIfNeeded()
            }
        }
        .onAppear {
            engine.refreshLiveActivity()
            // El permiso de notificaciones se pide al arrancar el primer
            // temporizador, no al abrir la app.
            AudioService.shared.apply(settings.soundConfig(for: engine.phase))
            updateFocusPolling(isRunning: engine.isRunning)
        }
        .onDisappear { focus.stopPolling() }
        .sheet(isPresented: $showSettings) {
            SettingsSheet()
                .sheetSizing(minHeight: 620)
                .presentationDetents([.large])
                .presentationBackground(Theme.base)
        }
        .sheet(isPresented: $showTask) {
            TaskSheet()
                .sheetSizing(minHeight: 340)
                .presentationDetents([.medium, .large])
                .presentationBackground(Theme.base)
        }
        .sheet(isPresented: $showHistory) {
            HistorySheet()
                .sheetSizing(minHeight: 620)
                .presentationDetents([.large])
                .presentationBackground(Theme.base)
        }
        .sheet(isPresented: $showSounds) {
            SoundSheet()
                .sheetSizing(minHeight: 620)
                .presentationDetents([.large])
                .presentationBackground(Theme.base)
        }
        .sheet(isPresented: $showGoalReached) {
            GoalReachedSheet(summary: reachedGoalSummary)
                .sheetSizing(minHeight: 320)
        }
    }

    /// Se adapta al espacio de la ventana, también cuando el iPad comparte pantalla.
    private func tabletBody(size: CGSize) -> some View {
        let wide = size.width > size.height && size.width >= 900
        let ringSize = wide
            ? min(size.width * 0.49, max(220, size.height - 280), 660)
            : min(size.width * 0.72, max(220, min(size.height * 0.50, size.height - 400)), 620)
        return ZStack {
            PhaseBackground(phase: engine.phase, isRunning: engine.isRunning)
                .contentShape(Rectangle())
                .onTapGesture { wakeControls() }
            ScrollView {
                VStack(spacing: 28) {
                    header.opacity(immersive ? 0.35 : 1)
                    Spacer(minLength: 0)
                    if wide {
                        HStack(spacing: 44) {
                            tabletClock(ringSize: ringSize)
                                .frame(maxWidth: .infinity)
                            tabletControls
                                .frame(width: min(size.width * 0.30, 380))
                        }
                    } else {
                        tabletClock(ringSize: ringSize)
                        Spacer(minLength: 0)
                        tabletControls
                    }
                    Spacer(minLength: 0)
                }
                .padding(36)
                .frame(minHeight: size.height)
            }
        }
    }

    @ViewBuilder
    private func tabletClock(ringSize: CGFloat) -> some View {
        if engine.phase.isBreak {
            breakBody(ringSize: ringSize)
        } else {
            VStack(spacing: 28) {
                taskPill
                clock(ringSize: ringSize)
            }
        }
    }

    private var tabletControls: some View {
        VStack(spacing: 24) {
            interruptionPill
            focusHint
            soundChip
                .opacity(immersive ? 0 : 1)
                .allowsHitTesting(!immersive)
            controls
                .opacity(immersive ? 0 : 1)
                .allowsHitTesting(!immersive)
        }
    }

    /// La pantalla completa, con tarea, historial, ajustes, sonido y controles.
    private var portraitBody: some View {
        GeometryReader { geo in
            let ringSize = min(geo.size.width - 76, 350)

            ZStack {
                PhaseBackground(phase: engine.phase, isRunning: engine.isRunning)
                    .contentShape(Rectangle())
                    .onTapGesture { wakeControls() }

                VStack(spacing: 0) {
                    header
                        .opacity(immersive ? 0.35 : 1)

                    Spacer(minLength: 12)

                    if engine.phase.isBreak {
                        breakBody(ringSize: ringSize)
                    } else {
                        VStack(spacing: 20) {
                            taskPill
                            clock(ringSize: ringSize)
                        }
                    }

                    Spacer(minLength: 12)

                    interruptionPill
                    focusHint

                    soundChip
                        .opacity(immersive ? 0 : 1)
                        .allowsHitTesting(!immersive)

                    controls
                        .padding(.top, 26)
                        .opacity(immersive ? 0 : 1)
                        .allowsHitTesting(!immersive)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 28)
            }
            // Deslizar hacia arriba entra en modo inmersivo sin esperar.
            // Simultáneo a propósito: un `gesture` normal aquí compite con los
            // botones de debajo y se come sus toques.
            .simultaneousGesture(
                DragGesture(minimumDistance: 40)
                    .onEnded { value in
                        guard value.translation.height < -40, engine.isRunning else { return }
                        enterImmersion()
                    }
            )
        }
    }

    /// La versión pura de sobremesa: solo el anillo y los dígitos, sin
    /// cabecera ni controles. Es la misma idea que el modo inmersivo vertical,
    /// pero aquí es el estado por defecto — para eso está el apaisado, para
    /// dejar el móvil apoyado y mirarlo de lejos. Pausar, saltar o cambiar la
    /// tarea sigue disponible girando el teléfono a vertical.
    private var landscapeBody: some View {
        GeometryReader { geo in
            let ringSize = min(geo.size.height - 32, geo.size.width * 0.6, 340)
            ZStack {
                PhaseBackground(phase: engine.phase, isRunning: engine.isRunning)
                clock(ringSize: ringSize)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
    }

    // MARK: - Secciones

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 8) {
                Label(engine.phase.title, systemImage: engine.phase.symbol)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(engine.phase.tint)
                sessionDots
            }
            Spacer()
            HStack(spacing: 10) {
                CircleButton(symbol: "chart.bar", label: "Historial", size: 42) {
                    showHistory = true
                }
                CircleButton(symbol: "slider.horizontal.3", label: "Ajustes", size: 42) {
                    #if os(macOS)
                    openSettings()
                    #else
                    showSettings = true
                    #endif
                }
            }
            .opacity(immersive ? 0 : 1)
            .allowsHitTesting(!immersive)
        }
        .padding(.top, 8)
    }

    // MARK: - Tarea

    /// En qué estás trabajando. Sin nombre, un pomodoro es solo una cuenta atrás.
    private var taskPill: some View {
        Button {
            showTask = true
        } label: {
            HStack(spacing: 9) {
                Image(systemName: engine.currentTask.isEmpty ? "plus.circle" : "target")
                    .font(.system(size: 13, weight: .semibold))
                Text(engine.currentTask.isEmpty ? "¿En qué trabajas?" : engine.currentTask)
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(engine.currentTask.isEmpty
                             ? .white.opacity(0.45)
                             : engine.phase.tint)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(Capsule().fill(Theme.card))
            .overlay(Capsule().stroke(Theme.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: 300)
        .opacity(immersive ? 0.4 : 1)
        .allowsHitTesting(!immersive)
        .accessibilityLabel("Tarea del bloque")
        .accessibilityValue(engine.currentTask.isEmpty ? "sin definir" : engine.currentTask)
    }

    // MARK: - Interrupciones

    /// Marcar una distracción no detiene el contador: registrarla es lo que
    /// reduce las siguientes. Sigue accesible en modo inmersivo a propósito,
    /// porque es justo cuando la pantalla está limpia cuando te distraes.
    @ViewBuilder
    private var interruptionPill: some View {
        if engine.isRunning, engine.phase == .work {
            // Un `Menu` aquí no llega a abrirse: el gesto de arrastre que cubre
            // toda la pantalla le cancela la pulsación. Un botón normal con
            // diálogo es fiable y además da dianas más grandes, que es lo que
            // hace falta justo después de distraerse.
            Button {
                showInterruptionChoice = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "hand.raised")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Distracción")
                        .font(.system(.footnote, design: .rounded, weight: .medium))
                    if engine.interruptionCount > 0 {
                        Text("\(engine.interruptionCount)")
                            .font(.system(.caption2, design: .rounded, weight: .bold))
                            .foregroundStyle(Theme.base)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(engine.phase.tint))
                    }
                }
                .foregroundStyle(.white.opacity(0.6))
                .padding(.horizontal, 15)
                .padding(.vertical, 9)
                .background(Capsule().fill(Theme.card))
                .overlay(Capsule().stroke(Theme.stroke, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .opacity(immersive ? 0.5 : 1)
            .padding(.bottom, 12)
            .accessibilityLabel("Marcar una distracción")
            .accessibilityValue("\(engine.interruptionCount) en este bloque")
            .confirmationDialog(
                "¿Qué ha pasado?",
                isPresented: $showInterruptionChoice,
                titleVisibility: .visible
            ) {
                Button("Me he distraído yo") { engine.markInterruption(external: false) }
                Button("Me han interrumpido") { engine.markInterruption(external: true) }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("Se apunta la marca. El contador no se detiene.")
            }
        }
    }

    /// Un punto por bloque del ciclo: lleno el que ya hiciste, hueco el que
    /// estás haciendo, apagado el que falta.
    private var sessionDots: some View {
        let total = max(settings.sessionsBeforeLongBreak, 1)
        let done = engine.completedInCycle
        return HStack(spacing: 7) {
            ForEach(0..<total, id: \.self) { index in
                Group {
                    if index < done {
                        Circle().fill(engine.phase.tint)
                    } else if index == done, engine.phase == .work {
                        Circle().strokeBorder(engine.phase.tint, lineWidth: 2)
                    } else {
                        Circle().fill(Color.white.opacity(0.35))
                    }
                }
                .frame(width: index == done ? 10 : 8, height: index == done ? 10 : 8)
            }
            HStack(spacing: 3) {
                if goalReached {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10, weight: .bold))
                }
                Text(goalProgress.label)
                    .accessibilityIdentifier("goal.progress")
                    .font(.system(.caption2, design: .rounded, weight: .medium))
            }
            .foregroundStyle(goalReached ? engine.phase.tint : .white.opacity(0.55))
            .padding(.leading, 5)
        }
        .animation(.snappy, value: done)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Progreso del ciclo")
        .accessibilityValue(
            "\(done) de \(total) bloques antes del descanso largo. "
            + goalProgress.label
        )
    }

    private var goalReached: Bool {
        goalProgress.reached
    }

    private var goalProgress: DailyGoal.Progress {
        DailyGoal.Progress(
            day: calendar.startOfDay(for: Date()), mode: settings.dailyGoalMode,
            blocks: settings.dailyGoal, minutes: settings.dailyGoalMinutes,
            summary: FocusHistorySummary(sessions: sessions, day: Date(), calendar: calendar),
            activeSeconds: engine.currentDayWorkSeconds
        )
    }

    // MARK: - Reloj

    private func clock(ringSize: CGFloat) -> some View {
        ZStack {
            ProgressRing(
                progress: isDragging ? draggedProgress : engine.progress,
                tint: engine.phase.tint,
                lineWidth: isDragging ? 14 : 10
            )
            .frame(width: ringSize, height: ringSize)
            .animation(.snappy(duration: 0.15), value: isDragging)

            VStack(spacing: 8) {
                Text(displayedTime.clockString)
                    .font(Theme.time(ringSize * 0.235 * min(clockScale, 1.3)))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.snappy(duration: 0.2), value: displayedTime.clockString)

                Text(isDragging ? "suelta para fijar" : stateCaption)
                    .font(.system(.footnote, design: .rounded, weight: .medium))
                    .foregroundStyle(isDragging ? engine.phase.tint : .white.opacity(0.45))
                    .textCase(.uppercase)
                    .kerning(1.4)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: ringSize * 0.8)
            }
        }
        .frame(width: ringSize, height: ringSize)
        .contentShape(Rectangle())
        .onTapGesture { immersive ? wakeControls() : engine.toggle() }
        .gesture(ringDrag(ringSize: ringSize))
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("timer.clock")
        .accessibilityLabel("\(engine.phase.title), \(stateCaption)")
        .accessibilityValue("Quedan \(engine.remaining.spokenString)")
        .accessibilityAddTraits(.updatesFrequently)
        .accessibilityHint(engine.isRunning ? "Activa para pausar" : "Activa para empezar")
        .accessibilityAdjustableAction { direction in
            guard engine.runState == .idle else { return }
            let current = Int(engine.totalForPhase / 60)
            engine.setCurrentPhaseDuration(minutes: direction == .increment ? current + 1 : current - 1)
        }
    }

    /// Durante el descanso la cuenta atrás pasa a segundo plano y manda la
    /// propuesta: el objetivo del descanso es que dejes de mirar la pantalla.
    private func breakBody(ringSize: CGFloat) -> some View {
        let suggestion = BreakSuggestion.forBreak(
            phase: engine.phase,
            seed: engine.completedTotal + engine.completedInCycle
        )
        return VStack(spacing: 26) {
            VStack(spacing: 14) {
                Image(systemName: suggestion.symbol)
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(engine.phase.tint)
                    .symbolRenderingMode(.hierarchical)

                Text(suggestion.title)
                    .font(.system(.title, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text(suggestion.detail)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
            }
            .accessibilityElement(children: .combine)

            clock(ringSize: ringSize * 0.52)
        }
        .transition(.opacity)
    }

    private var displayedTime: TimeInterval {
        if let draggedMinutes { return TimeInterval(draggedMinutes * 60) }
        return engine.remaining
    }

    private var isDragging: Bool { draggedMinutes != nil }

    private var draggedProgress: Double {
        guard let draggedMinutes else { return 0 }
        return Double(draggedMinutes) / Double(PomodoroEngine.ringMinutes.upperBound)
    }

    private var stateCaption: String {
        switch engine.runState {
        case .running: "en marcha"
        case .paused: "en pausa"
        case .idle: "listo"
        }
    }

    // MARK: - Arrastre sobre el anillo

    /// Arrastrar sobre el aro fija la duración de la fase. Una vuelta completa
    /// son 60 minutos. Solo con el reloj parado: cambiar la duración a mitad de
    /// un bloque no significa nada.
    private func ringDrag(ringSize: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                guard engine.runState == .idle else { return }
                let center = CGPoint(x: ringSize / 2, y: ringSize / 2)
                let dx = value.location.x - center.x
                let dy = value.location.y - center.y
                let distance = sqrt(dx * dx + dy * dy)
                // Solo cuenta si el dedo está sobre el aro, no en el centro:
                // así el gesto no compite con el toque para arrancar.
                guard distance > ringSize * 0.28, distance < ringSize * 0.68 else { return }

                var degrees = atan2(dy, dx) * 180 / .pi + 90
                if degrees < 0 { degrees += 360 }
                let minutes = max(
                    PomodoroEngine.ringMinutes.lowerBound,
                    Int((degrees / 360 * Double(PomodoroEngine.ringMinutes.upperBound)).rounded())
                )
                if minutes != draggedMinutes {
                    draggedMinutes = minutes
                    Haptics.impact(.soft)
                }
            }
            .onEnded { _ in
                if let draggedMinutes {
                    engine.setCurrentPhaseDuration(minutes: draggedMinutes)
                    Haptics.impact(.rigid)
                }
                draggedMinutes = nil
            }
    }

    // MARK: - Sonido y controles

    private var soundChip: some View {
        Button {
            showSounds = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: currentSound.symbol)
                    .font(.system(size: 14, weight: .semibold))
                Text(currentSound.title)
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                if !currentSound.isSilent {
                    Text(volumeLabel)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.white.opacity(0.45))
                }
                Image(systemName: "chevron.up")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(Capsule().fill(Theme.card))
            .overlay(Capsule().stroke(Theme.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Sonido de fondo")
        .accessibilityValue(currentSound.isSilent ? currentSound.title : "\(currentSound.title), \(volumeLabel)")
    }

    private var currentSound: SoundKind {
        settings.sound(for: engine.phase)
    }

    private var volumeLabel: String {
        currentSound == .binaural
            ? "\(Int(settings.binauralBeatHz.rounded())) Hz"
            : "\(Int((settings.soundVolume * 100).rounded()))%"
    }

    private var controls: some View {
        HStack(spacing: 26) {
            CircleButton(symbol: "arrow.counterclockwise", label: "Reiniciar la fase") {
                engine.reset()
            }

            CircleButton(
                symbol: engine.isRunning ? "pause.fill" : "play.fill",
                label: engine.isRunning ? "Pausar" : "Empezar",
                size: 84,
                prominent: true,
                tint: engine.phase.tint
            ) {
                engine.toggle()
            }

            CircleButton(symbol: "forward.end.fill", label: "Saltar a la fase siguiente") {
                engine.skip()
            }
        }
    }

    // MARK: - Modo inmersivo

    private func wakeControls() {
        if immersive { Haptics.impact(.soft) }
        immersive = false
        scheduleDim()
    }

    // MARK: - Aviso de Concentración

    /// El sistema no deja que ninguna app encienda un modo de Concentración por ti;
    /// esto solo lee si ya tienes uno puesto y te lo recuerda si no. Se calla
    /// en cuanto detecta uno activo, y no vuelve a insistir en el mismo bloque.
    @ViewBuilder
    private var focusHint: some View {
        if settings.suggestFocusMode, focus.isAuthorized, engine.isRunning,
           engine.phase == .work, !focus.isFocused {
            Label("Sin Concentración activa", systemImage: "moon.zzz")
                .font(.system(.caption2, design: .rounded, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
                .padding(.bottom, 10)
                .opacity(immersive ? 0 : 1)
                .accessibilityLabel("No tienes ningún modo de Concentración activo")
        }
    }

    private func updateFocusPolling(isRunning: Bool) {
        guard settings.suggestFocusMode, focus.isAuthorized else { return }
        if isRunning, engine.phase == .work {
            focus.startPolling()
        } else {
            focus.stopPolling()
        }
    }

    private func enterImmersion() {
        dimTask?.cancel()
        guard !voiceOverEnabled, settings.immersionMode != .never else { return }
        Haptics.impact(.soft)
        immersive = true
    }

    private func scheduleDim() {
        dimTask?.cancel()
        // Con VoiceOver activo esconder los controles los saca del recorrido de
        // navegación: la app se quedaría sin forma de pausar.
        guard engine.isRunning, !voiceOverEnabled,
              let delay = settings.immersionMode.delay
        else {
            immersive = false
            return
        }
        dimTask = Task { @MainActor in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, engine.isRunning else { return }
            immersive = true
        }
    }
}
