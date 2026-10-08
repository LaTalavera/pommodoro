# Pommodoro

App de foco para iPhone, iPad y Mac: temporizador Pomodoro a pantalla completa con sonidos
relajantes sintetizados en tiempo real (incluidos binaurales).

## Estado — iteración 4

- Soporte nativo para iPad: anillo adaptable y distribución en dos columnas en
  ventanas horizontales amplias, con controles accesibles en ambas orientaciones.
- Cuenta atrás a pantalla completa, con anillo de progreso y modo inmersivo
  (a los 6 s en marcha desaparecen controles, barra de estado e indicador de
  inicio; un toque los devuelve).
- Ciclo completo: concentración → descanso corto → descanso largo, con
  duraciones y número de bloques por ciclo configurables.
- Biblioteca de 12 sonidos organizada en Naturaleza, Uniformes y Tonos: lluvia,
  lluvia suave, olas, arroyo, chimenea, bosque, viento, ventilador, ruido marrón /
  rosa / blanco y binaural. Síntesis estéreo sin conexión, transiciones suaves,
  filtrado de continua y control de picos; no necesita descargar grabaciones.
- Cada inicio de la app comienza sin sonido de fondo, aunque antes hubiera uno
  seleccionado. La elección dura hasta cerrar el proceso; volver del segundo
  plano conserva el sonido elegido. Se mantienen el volumen y los demás ajustes.
- Escucha previa con controles de volumen y detener/reanudar, selección por fase
  y botón Listo para aplicar. Cancelar restaura el sonido anterior. Los ambientes
  pueden mezclarse con otras apps; los binaurales se reproducen en exclusiva.
- Duración configurable arrastrando sobre el propio anillo: una vuelta son
  60 minutos. Los steppers de ajustes siguen ahí para el resto del rango.
- El descanso es otra pantalla, no la misma en verde: propone algo concreto
  (mirar lejos, levantarse, beber agua) y deja la cuenta atrás en segundo plano.
- Cada bloque lleva el nombre de la tarea, con las recientes como sugerencia.
- Historial en SwiftData: bloques por día, tiempo concentrado, interrupciones y
  la lista de sesiones, distinguiendo las completadas de las abandonadas.
- El tiempo concentrado suma también los minutos de bloques abandonados; los
  descansos y las pausas no se suman. Los bloques completados siguen separados.
- Resumen por semana natural, con navegación a semanas anteriores, minutos por
  día y totales de tiempo, bloques completados e interrupciones. El desglose por
  tarea se ordena por tiempo dedicado y distingue interrupciones externas y
  propias; los nombres se agrupan ignorando mayúsculas y espacios sobrantes.
- Live Activity en pantalla bloqueada y Dynamic Island: cuenta atrás del
  sistema, fase, tarea y estado de pausa. Se actualiza al reanudar o cambiar de
  fase y se retira al reiniciar, saltar o terminar sin encadenado automático.
- Marcar interrupciones durante el bloque sin detener el contador, separando las
  de fuera de las propias. Sigue accesible en modo inmersivo.
- Objetivo diario en bloques (1–20), minutos (5–600, en pasos de 5) o desactivado.
  El objetivo en minutos incluye el trabajo en curso y el esfuerzo guardado de
  bloques abandonados. Al cruzarlo, una hoja lo celebra una vez por día y anima a
  cerrar la app en vez de retener con un contador que solo sube.
- La duración del bloque iniciado queda fijada: cambiar ajustes mientras está
  en marcha o pausado se aplica a bloques futuros sin falsear el tiempo trabajado.
- Modo horizontal "de sobremesa": solo el anillo y los dígitos, pensado para
  dejar el móvil apoyado y mirarlo de lejos mientras trabajas en el ordenador.
- Recordatorio opcional de Concentración: si empiezas un bloque sin ningún
  modo de Concentración activo, un aviso discreto te lo recuerda. iOS no deja
  que ninguna app encienda un modo de Concentración por sí sola — esto solo
  lee si ya tienes uno puesto.
- Campana de transición sintetizada, vibración, notificación local al terminar
  la fase y audio en segundo plano.
- El temporizador se guarda en disco: sobrevive a que iOS descargue la app a
  mitad de un bloque.
- Accesibilidad: etiquetas de VoiceOver, Dynamic Type y respeto a «Reducir
  movimiento». El modo inmersivo no se activa con VoiceOver en marcha, para no
  dejar los controles fuera del recorrido de navegación.

## Ejecutar

```bash
xcodebuild -scheme Pommodoro -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

Los tests:

```bash
xcodebuild test -scheme Pommodoro -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

En el Mac (app nativa de macOS 14+, mismo código y mismo target):

```bash
xcodebuild -scheme Pommodoro -destination 'platform=macOS' build
xcodebuild test -scheme Pommodoro-Mac -destination 'platform=macOS'
```

Diferencias en Mac: sin Live Activity ni Dynamic Island (solo existen en iOS; las
del iPhone se reflejan solas en la barra de menús), la pantalla se mantiene
encendida con una aserción de energía en vez de `isIdleTimerDisabled`, el audio
no usa `AVAudioSession`, y la respuesta háptica solo se nota en el trackpad. Los
UI tests (orientación de dispositivo) son solo de iOS y por eso el esquema
`Pommodoro-Mac` incluye únicamente los tests unitarios.

O abrir `Pommodoro.xcodeproj` en Xcode y pulsar Run. Requiere Xcode 16+ (el
proyecto usa grupos sincronizados con el sistema de ficheros: añadir un `.swift`
dentro de `Pommodoro/` no requiere tocar el `.xcodeproj`). Destino iOS 17.

## Estructura

| Ruta | Qué hay |
| --- | --- |
| `Pommodoro/Model/PomodoroEngine.swift` | Reloj del ciclo. Cuenta contra una fecha de fin absoluta, no restando ticks, para sobrevivir al segundo plano. |
| `Pommodoro/Model/AppSettings.swift` | Preferencias persistidas en `UserDefaults`. |
| `Pommodoro/Audio/SoundSynth.swift` | Generación de audio muestra a muestra (ruidos, filtros, binaurales). Corre en el hilo de render: sin asignaciones ni bloqueos. |
| `Pommodoro/Audio/AudioService.swift` | `AVAudioEngine`, sesión de audio y campanas. Los parámetros llegan al hilo de audio por un buzón con `trylock`. |
| `Pommodoro/Model/PomodoroEffects.swift` | Costura entre el motor y el sistema (notificaciones, sonido, vibración, pantalla). Permite que el motor sea comprobable sin UIKit. |
| `Pommodoro/Views/` | Interfaz SwiftUI: pantalla del temporizador, hoja de sonido y hoja de ajustes. |
| `Pommodoro/Model/BreakSuggestion.swift` | Qué proponer en cada descanso. |
| `Pommodoro/Model/Session.swift` | Modelo SwiftData del historial y la costura `SessionRecording`, para que el motor registre sin depender de la base de datos. |
| `Pommodoro/Model/DailyGoal.swift` | Lógica pura de "objetivo recién alcanzado", separada de la vista para poder probarla sin SwiftUI. |
| `Pommodoro/Model/FocusHistorySummary.swift` | Totales diarios de esfuerzo, incluyendo bloques abandonados y excluyendo descansos. |
| `Pommodoro/Model/WeeklyFocusSummary.swift` | Semana del calendario local, días y agrupaciones por tarea. Cada sesión se atribuye a la fecha en que comenzó. |
| `Shared/PomodoroActivityAttributes.swift` | Estado compartido entre la app y la extensión de Live Activities. |
| `Pommodoro/Support/LiveActivityController.swift` | Ciclo de vida de ActivityKit, recuperación y actualizaciones ordenadas. |
| `PommodoroLiveActivity/` | Presentación de pantalla bloqueada y Dynamic Island. |
| `Pommodoro/Support/FocusStatusMonitor.swift` | Lectura de si hay un modo de Concentración activo (`INFocusStatusCenter`, de solo lectura — iOS no expone ninguna API para activarlo). |
| `PommodoroTests/` | Tests de ciclo, persistencia, recuento diario, duración por anillo, sonido por fase, tarea, desenlace, interrupciones, almacén, historial diario/semanal, objetivos flexibles, Live Activities y síntesis estéreo (niveles, silencio y frecuencias). |
| `PommodoroUITests/` | Pruebas de interfaz: esfuerzo parcial, Dynamic Island, resúmenes semanales por tarea, selección de objetivos, escucha previa, arranque silencioso y distribución nativa de iPad en ambas orientaciones. La captura del modo horizontal sigue excluida por defecto por las limitaciones de rotación del simulador. |

## Live Activities

Necesitan estar permitidas en los ajustes de iOS. La app funciona igualmente
si están desactivadas. Tocar la actividad abre Pommodoro para usar sus controles.
La cuenta atrás se dibuja con fechas, sin actualizaciones por segundo desde la
app. Si iOS suspende o termina el proceso, llega a cero y muestra la fase como
terminada; la siguiente fase se sincroniza cuando la app vuelve a ejecutarse.
No se promete encadenado de fases mientras el proceso está suspendido.

Las pruebas de interfaz de Dynamic Island requieren un simulador de iPhone
con Dynamic Island, como el iPhone 17 Pro del comando anterior. El test del
historial espera 32 segundos, ya que los bloques de menos de 30 segundos no se
registran. Para ejecutar solo las pruebas unitarias:

```bash
xcodebuild test -scheme Pommodoro -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PommodoroTests
```

## Sobre los binaurales

Cada oído recibe un tono puro distinto (base configurable, 80–400 Hz) y el
batido es la diferencia entre ambos. **Solo funciona con auriculares**: por
altavoz los dos tonos se mezclan en el aire y el efecto desaparece.

## Siguientes pasos

El plan completo, priorizado, está en la revisión de producto «Pommodoro v2».
Lo siguiente por orden:

1. Atajos y Siri (App Intents).
2. Onboarding mínimo para quien abre la app por primera vez.
