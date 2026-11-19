import AVFoundation
import Observation
import SoundAnalysis
import SwiftUI

/// «Probar el micro» (Ajustes): lo que oye ahora el clasificador de Apple y con qué seguridad, sobre todo «ronquido»,
/// frente al umbral de la sensibilidad elegida. Para comprobar sin esperar una noche que Nana te oye desde donde
/// dejas el móvil (ronca de mentira, habla, tose).
@Observable
final class Probador {
    struct Oido: Identifiable, Equatable {
        var etiqueta: String
        var confianza: Double
        var id: String { etiqueta }
    }

    var activo = false
    var nivel = 0.0
    var ronquido = 0.0
    var maxRonquido = 0.0
    var ventanasRonquido = 0
    var oidos: [Oido] = []
    var error: String?

    private let engine = AVAudioEngine()
    private let cola = DispatchQueue(label: "dev.yagotg.nana.probar")
    private var analizador: SNAudioStreamAnalyzer?
    private var observador: Observador?
    private var posicion: AVAudioFramePosition = 0
    private var umbral = 0.3

    /// SoundAnalysis pide un NSObject: este pasa los resultados al Probador en el hilo principal.
    private final class Observador: NSObject, SNResultsObserving {
        weak var probador: Probador?
        func request(_ request: SNRequest, didProduce result: SNResult) {
            guard let r = result as? SNClassificationResult else { return }
            let ronca = r.classification(forIdentifier: "snoring")?.confidence ?? 0
            let top = r.classifications.prefix(3).map { Oido(etiqueta: $0.identifier, confianza: $0.confidence) }
            DispatchQueue.main.async { [weak self] in self?.probador?.recibir(ronca, top) }
        }
        func request(_ request: SNRequest, didFailWithError error: Error) {
            DispatchQueue.main.async { [weak self] in self?.probador?.error = "El reconocimiento se ha parado: \(error.localizedDescription)" }
        }
    }

    @MainActor
    func empezar(umbral: Double) async {
        guard !activo else { return }
        error = nil
        guard await AVAudioApplication.requestRecordPermission() else {
            error = "Nana necesita el micrófono. Actívalo en Ajustes > Privacidad > Micrófono."
            return
        }
        self.umbral = umbral
        maxRonquido = 0; ventanasRonquido = 0; ronquido = 0; oidos = []
        do {
            try Sesion.configurar()
            let input = engine.inputNode
            let f = input.outputFormat(forBus: 0)
            guard f.sampleRate > 0, f.channelCount > 0,
                  let mono = AVAudioFormat(standardFormatWithSampleRate: f.sampleRate, channels: 1) else {
                throw FalloNana("No encuentro el micrófono.")
            }
            let an = SNAudioStreamAnalyzer(format: mono)
            let obs = Observador()
            obs.probador = self
            try an.add(try SNClassifySoundRequest(classifierIdentifier: .version1), withObserver: obs)
            analizador = an
            observador = obs
            posicion = 0
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 4096, format: f) { [weak self] buf, _ in
                guard let self, let m = Analisis.mono(buf, formato: mono) else { return }
                let db = Analisis.nivel(m)
                self.cola.async {
                    self.analizador?.analyze(m, atAudioFramePosition: self.posicion)
                    self.posicion += AVAudioFramePosition(m.frameLength)
                }
                DispatchQueue.main.async { self.nivel = db }
            }
            engine.prepare()
            try engine.start()
            activo = true
        } catch {
            self.error = "No he podido empezar a escuchar: \(error.localizedDescription)"
            parar()
        }
    }

    func parar() {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        cola.sync {
            analizador?.completeAnalysis()
            analizador = nil
        }
        observador = nil
        if activo { Sesion.soltar() }
        activo = false
    }

    private func recibir(_ ronca: Double, _ top: [Oido]) {
        guard activo else { return }
        ronquido = ronca
        maxRonquido = max(maxRonquido, ronca)
        if ronca >= umbral { ventanasRonquido += 1 }
        oidos = top
    }

    /// Nombre en español de lo que más importa; lo demás, la etiqueta de Apple tal cual («dog», «music»…).
    static func nombre(_ etiqueta: String) -> String {
        if let t = TipoSonido.desde(etiqueta: etiqueta) { return t.nombre }
        return ["silence": "Silencio", "breathing": "Respiración", "music": "Música", "dog": "Perro", "cat": "Gato",
                "fan": "Ventilador", "air_conditioner": "Aire acondicionado", "rain": "Lluvia", "car_passing_by": "Coche",
                "white_noise": "Ruido blanco", "pink_noise": "Ruido rosa", "television": "Tele", "typing": "Teclear",
                "gurgling": "Gorgoteo", "gasp": "Jadeo", "sigh": "Suspiro", "door": "Puerta", "knock": "Golpes"][etiqueta]
            ?? etiqueta.replacingOccurrences(of: "_", with: " ")
    }
}

struct ProbarMicroView: View {
    @Environment(Ajustes.self) private var ajustes
    @Environment(Grabadora.self) private var grabadora
    @Environment(\.dismiss) private var cerrar
    @State private var p = Probador()

    private var umbral: Double { Motor.umbralRonquido(ajustes.sensibilidad) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Deja el móvil donde lo pondrás por la noche, túmbate y ronca de mentira, habla o tose. Abajo ves qué oye el reconocimiento de Apple y lo seguro que está.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if grabadora.grabando {
                        Label("Hay una noche grabándose: termínala para probar.", systemImage: "moon.zzz")
                            .font(.footnote).foregroundStyle(.orange)
                    } else {
                        Button(p.activo ? "Parar" : "Empezar a escuchar") {
                            if p.activo { p.parar() } else { Task { await p.empezar(umbral: umbral) } }
                        }
                        .bold()
                    }
                    if let e = p.error {
                        Label(e, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(.orange)
                    }
                }

                if p.activo || p.maxRonquido > 0 {
                    Section {
                        barra("Ahora", p.ronquido, destacado: true)
                        barra("Lo más alto", p.maxRonquido, destacado: false)
                        LabeledContent("Veces que contaría como ronquido", value: "\(p.ventanasRonquido)")
                        LabeledContent("Nivel", value: "\(Int(p.nivel)) dB")
                    } header: {
                        Text("Ronquido")
                    } footer: {
                        Text(consejo)
                    }

                    Section("Lo que más se parece ahora") {
                        if p.oidos.isEmpty {
                            Text("Escuchando…").foregroundStyle(.secondary)
                        }
                        ForEach(p.oidos) { o in
                            barra(Probador.nombre(o.etiqueta), o.confianza, destacado: false, conUmbral: false)
                        }
                    }
                }
            }
            .navigationTitle("Probar el micro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { cerrar() } } }
            .onDisappear { p.parar() }
        }
    }

    private var consejo: String {
        let u = Int(umbral * 100)
        if p.maxRonquido >= umbral { return "Cuenta a partir del \(u) %: con lo que has hecho, Nana te oiría roncar desde ahí." }
        if p.maxRonquido >= umbral * 0.5 { return "Cuenta a partir del \(u) %: te oye, pero no llega. Sube la sensibilidad o acerca el móvil." }
        return "Cuenta a partir del \(u) %. Ronca de mentira unos segundos cerca del móvil y luego desde tu almohada."
    }

    private func barra(_ titulo: String, _ v: Double, destacado: Bool, conUmbral: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(titulo).font(destacado ? .body.weight(.semibold) : .body)
                Spacer()
                Text("\(Int(v * 100)) %").monospacedDigit().foregroundStyle(conUmbral && v >= umbral ? Estilo.acento : .secondary)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.1))
                    Capsule().fill(conUmbral && v >= umbral ? Estilo.acento : Color.white.opacity(0.4))
                        .frame(width: g.size.width * min(1, max(0, v)))
                    if conUmbral {
                        Rectangle().fill(Color.orange).frame(width: 2).offset(x: g.size.width * umbral - 1)
                    }
                }
            }
            .frame(height: 8)
            .animation(.easeOut(duration: 0.2), value: v)
        }
        .accessibilityElement(children: .combine)
    }
}
