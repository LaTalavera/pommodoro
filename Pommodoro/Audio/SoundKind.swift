import Foundation

/// Paisajes sonoros disponibles. Todos se sintetizan en tiempo real,
/// no hay ficheros de audio en el bundle.
enum SoundKind: String, CaseIterable, Identifiable, Hashable {
    case none
    case binaural
    case rain
    case ocean
    case stream
    case brown
    case pink
    case white
    case softRain
    case fireplace
    case forest
    case wind
    case fan

    var id: String { rawValue }

    init?(id: String) {
        self.init(rawValue: id)
    }

    var title: String {
        switch self {
        case .none: "Silencio"
        case .binaural: "Binaural"
        case .rain: "Lluvia"
        case .ocean: "Olas"
        case .stream: "Arroyo"
        case .brown: "Ruido marrón"
        case .pink: "Ruido rosa"
        case .white: "Ruido blanco"
        case .softRain: "Lluvia suave"
        case .fireplace: "Chimenea"
        case .forest: "Bosque"
        case .wind: "Viento"
        case .fan: "Ventilador"
        }
    }

    var subtitle: String {
        switch self {
        case .none: "Sin sonido de fondo"
        case .binaural: "Tonos con desfase entre oídos"
        case .rain: "Lluvia constante"
        case .ocean: "Oleaje lento"
        case .stream: "Agua corriendo"
        case .brown: "Grave y envolvente"
        case .pink: "Equilibrado, natural"
        case .white: "Enmascara ruido de fondo"
        case .softRain: "Gotas lejanas y textura cálida"
        case .fireplace: "Crepitar sobre un fondo grave"
        case .forest: "Brisa y pájaros suaves"
        case .wind: "Ráfagas lentas entre las hojas"
        case .fan: "Zumbido estable y aire suave"
        }
    }

    var symbol: String {
        switch self {
        case .none: "speaker.slash"
        case .binaural: "waveform.path.ecg"
        case .rain: "cloud.rain"
        case .ocean: "water.waves"
        case .stream: "drop"
        case .brown: "waveform"
        case .pink: "waveform.path"
        case .white: "aqi.medium"
        case .softRain: "cloud.drizzle"
        case .fireplace: "flame"
        case .forest: "leaf"
        case .wind: "wind"
        case .fan: "fan"
        }
    }

    var isSilent: Bool { self == .none }

    var category: SoundCategory? {
        switch self {
        case .none: nil
        case .rain, .softRain, .ocean, .stream, .fireplace, .forest, .wind: .nature
        case .brown, .pink, .white, .fan: .steady
        case .binaural: .tones
        }
    }
}

enum SoundCategory: String, CaseIterable, Identifiable {
    case nature, steady, tones
    var id: String { rawValue }
    var title: String {
        switch self {
        case .nature: "Naturaleza"
        case .steady: "Uniformes"
        case .tones: "Tonos"
        }
    }
    var sounds: [SoundKind] { SoundKind.allCases.filter { $0.category == self } }
}

/// Presets de frecuencia de batido para los binaurales.
enum BinauralPreset: String, CaseIterable, Identifiable {
    case delta, theta, alpha, beta, gamma

    var id: String { rawValue }

    var hz: Double {
        switch self {
        case .delta: 2.5
        case .theta: 6
        case .alpha: 10
        case .beta: 16
        case .gamma: 40
        }
    }

    var title: String {
        switch self {
        case .delta: "Delta"
        case .theta: "Theta"
        case .alpha: "Alpha"
        case .beta: "Beta"
        case .gamma: "Gamma"
        }
    }

    /// Describe el pulso del batido, no un efecto prometido: la evidencia sobre
    /// binaurales y estado mental es floja y contradictoria, así que el texto
    /// se limita a lo que de verdad se puede afirmar — cómo suena.
    var caption: String {
        switch self {
        case .delta: "Pulso muy lento y grave"
        case .theta: "Pulso lento"
        case .alpha: "Pulso moderado"
        case .beta: "Pulso rápido"
        case .gamma: "Pulso muy rápido, casi un zumbido"
        }
    }

    static func closest(to hz: Double) -> BinauralPreset? {
        allCases.first { abs($0.hz - hz) < 0.01 }
    }
}
