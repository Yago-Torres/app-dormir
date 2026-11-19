import AVFoundation
import Observation
import UIKit

/// La noche en curso, para la interfaz. El trabajo de verdad lo hace `Motor`.
@Observable
final class Grabadora {
    var noche: Noche?
    var nivel = 0.0
    /// Últimos niveles, para la onda en directo.
    var onda: [Double] = Array(repeating: 0, count: 60)
    var ultimoTipo: TipoSonido?
    var ultimoMomento: Date?
    var error: String?
    var estereo = false

    var grabando: Bool { noche != nil }

    private var motor: Motor?
    private var almacen: Almacen?
    private var minutosSinGuardar = 0
    private var ultimoSonido = Date()
    private var vigilante: Timer?
    private var avisadoSilencio = false

    /// Apunta un problema en la noche en curso (y lo enseña en la pantalla). Sin repetir el mismo.
    func avisa(_ texto: String) {
        let linea = "\(Estilo.hora(Date())) · \(texto)"
        error = texto
        guard var n = noche else { return }
        if n.avisos?.contains(where: { $0.hasSuffix(texto) }) == true { return }
        n.avisos = (n.avisos ?? []) + [linea]
        noche = n
        almacen?.guardarNoche(n)
    }

    @MainActor
    func empezar(cama: Cama, factores: [String: [Factor]], almacen: Almacen) async {
        guard noche == nil else { return }
        error = nil
        guard await AVAudioApplication.requestRecordPermission() else {
            error = "Nana necesita el micrófono. Actívalo en Ajustes > Privacidad > Micrófono."
            return
        }
        let aj = Ajustes.compartidos
        let m = Motor(config: .init(sensibilidad: aj.sensibilidad, tipos: aj.tiposGuardados,
                                    pausaRonquidos: aj.pausaRonquidos * 60, maxClips: aj.maxClips,
                                    retraso: aj.retrasoInicio * 60))
        m.alNivel = { [weak self] db in self?.recibirNivel(db) }
        m.alMinuto = { [weak self] min in self?.recibir(min) }
        m.alEvento = { [weak self] e in self?.recibir(e) }
        m.alAviso = { [weak self] texto in self?.avisa(texto) }
        m.alDetectar = { [weak self] t in
            self?.ultimoTipo = t
            self?.ultimoMomento = Date()
        }
        do {
            try m.empezar()
        } catch {
            self.error = "No he podido empezar a grabar: \(error.localizedDescription)"
            return
        }
        var n = Noche(inicio: Date(), cama: cama)
        n.estereo = m.estereo
        n.factores = factores
        estereo = m.estereo
        self.almacen = almacen
        motor = m
        noche = n
        almacen.guardarNoche(n)
        aj.ultimaCama = cama
        // si el micro deja de mandar sonido (iOS cortó la grabación), que se sepa en vez de grabar nada en silencio
        ultimoSonido = Date()
        avisadoSilencio = false
        vigilante = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            guard let self, self.noche != nil else { return }
            if Date().timeIntervalSince(self.ultimoSonido) > 90, !self.avisadoSilencio {
                self.avisadoSilencio = true
                self.avisa("El micro lleva más de un minuto sin mandar sonido: iOS ha parado la grabación. Abre Nana para seguir.")
            }
        }
        // la pantalla puede bloquearse: la grabación sigue (modo audio en segundo plano)
        UIApplication.shared.isIdleTimerDisabled = false
    }

    /// Termina la noche y devuelve su id cuando ya está guardada del todo.
    func terminar(_ listo: @escaping (UUID?) -> Void) {
        guard let motor else { listo(nil); return }
        vigilante?.invalidate()
        vigilante = nil
        motor.terminar()
        // el motor ya ha encolado en el hilo principal sus últimos minuto y clip: esto va detrás
        DispatchQueue.main.async { [weak self] in
            guard let self, var n = self.noche else { listo(nil); return }
            n.fin = Date()
            self.almacen?.guardarNoche(n)
            self.noche = nil
            self.motor = nil
            self.ultimoTipo = nil
            self.error = nil
            listo(n.id)
        }
    }

    private func recibirNivel(_ db: Double) {
        ultimoSonido = Date()
        if avisadoSilencio { avisadoSilencio = false; error = nil }   // ha vuelto
        nivel = db
        onda.removeFirst()
        onda.append(db)
    }

    private func recibir(_ m: Minuto) {
        guard var n = noche, let almacen else { return }
        var m = m
        m.quien = Atribucion.quienDelMinuto(m, noche: n, perfiles: almacen.perfiles)
        n.minutos.append(m)
        noche = n
        minutosSinGuardar += 1
        if minutosSinGuardar >= 5 {
            minutosSinGuardar = 0
            almacen.guardarNoche(n)
        }
    }

    private func recibir(_ e: Evento) {
        guard var n = noche, let almacen else { return }
        var e = e
        e.quienAdivinado = Atribucion.adivinar(e.huella, tipo: e.tipo, cama: n.cama, estereo: n.estereo, perfiles: almacen.perfiles)
        n.eventos.append(e)
        noche = n
        almacen.guardarNoche(n)
    }
}

/// Para escuchar los clips.
@Observable
final class Reproductor: NSObject, AVAudioPlayerDelegate {
    var sonando: UUID?
    var progreso = 0.0
    var error: String?
    /// De qué clip es el error (se enseña debajo de ese).
    var errorDe: UUID?
    private var player: AVAudioPlayer?
    private var temporizador: Timer?

    func alternar(_ e: Evento) {
        if sonando == e.id { parar(); return }
        parar()
        error = nil
        errorDe = e.id
        guard let url = Almacen.url(e.archivo) else {
            error = "Este clip ya no está en el móvil (se borran solos pasados los días de Ajustes)."
            return
        }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        let p: AVAudioPlayer
        do {
            p = try AVAudioPlayer(contentsOf: url)
        } catch {
            self.error = "No puedo reproducir este clip: \(error.localizedDescription)"
            return
        }
        p.delegate = self
        p.play()
        player = p
        sonando = e.id
        temporizador = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, let p = self.player, p.duration > 0 else { return }
            self.progreso = p.currentTime / p.duration
        }
    }

    func parar() {
        player?.stop()
        player = nil
        sonando = nil
        progreso = 0
        temporizador?.invalidate()
        temporizador = nil
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { self.parar() }
    }
}
