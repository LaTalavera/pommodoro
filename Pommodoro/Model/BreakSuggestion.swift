import Foundation

/// Qué proponer durante un descanso.
///
/// Un descanso en el que sigues mirando la pantalla no es un descanso, así que
/// la app propone algo concreto en lugar de limitarse a contar hacia atrás.
struct BreakSuggestion: Hashable {
    let symbol: String
    let title: String
    let detail: String

    /// Descansos cortos: cosas que caben en cinco minutos sin levantar la sesión.
    static let short: [BreakSuggestion] = [
        .init(symbol: "eye",
              title: "Mira lejos",
              detail: "Veinte segundos a algo que esté a seis metros. Descansa el enfoque."),
        .init(symbol: "figure.stand",
              title: "Ponte de pie",
              detail: "Levántate y estira la espalda. No hace falta ir a ningún sitio."),
        .init(symbol: "drop",
              title: "Bebe agua",
              detail: "Un vaso entero, ahora que te acuerdas."),
        .init(symbol: "wind",
              title: "Respira hondo",
              detail: "Cinco respiraciones lentas, soltando el aire más despacio de lo que lo tomas."),
    ]

    /// Descansos largos: merecen salir del sitio.
    static let long: [BreakSuggestion] = [
        .init(symbol: "figure.walk",
              title: "Date una vuelta",
              detail: "Sal de la habitación. Caminar es lo que deja que la cabeza ordene sola."),
        .init(symbol: "cup.and.saucer",
              title: "Come algo",
              detail: "Algo de verdad, lejos del escritorio."),
        .init(symbol: "sun.max",
              title: "Busca luz natural",
              detail: "Asómate a una ventana o sal un momento."),
    ]

    /// Elige una propuesta estable durante todo el descanso pero distinta entre
    /// descansos, para que no se vuelva ruido de fondo.
    static func forBreak(phase: PomodoroPhase, seed: Int) -> BreakSuggestion {
        let pool = phase == .longBreak ? long : short
        return pool[abs(seed) % pool.count]
    }
}
