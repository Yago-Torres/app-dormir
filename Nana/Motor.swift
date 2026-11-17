import AVFoundation
import Accelerate
import SoundAnalysis

struct FalloNana: LocalizedError {
    let mensaje: String
    init(_ m: String) { mensaje = m }
    var errorDescription: String? { mensaje }
}

/// La sesión de audio: grabar toda la noche (también con la pantalla bloqueada), dejando sonar la música o el ruido
/// blanco de otras apps, y con el micro del iPhone en estéreo si se puede (sirve para saber de qué lado viene).
enum Sesion {
    @discardableResult
    static func configurar() throws -> Bool {
        let s = AVAudioSession.sharedInstance()
        try s.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers, .defaultToSpeaker])
        try s.setActive(true)
        guard let mic = s.availableInputs?.first(where: { $0.portType == .builtInMic }) else { return false }
        try? s.setPreferredInput(mic)
        if let fuente = mic.dataSources?.first(where: { $0.supportedPolarPatterns?.contains(.stereo) == true }) {
            do {
                try fuente.setPreferredPolarPattern(.stereo)
                try mic.setPreferredDataSource(fuente)
                try s.setPreferredInputOrientation(.portrait)
                try? s.setPreferredInputNumberOfChannels(2)
                return true
            } catch {
                return false
            }
        }
        return false
    }

    static func soltar() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

/// Cuentas sobre un trozo de audio.
enum Analisis {
    /// Mezcla a mono (formato estándar float32).
    static func mono(_ b: AVAudioPCMBuffer, formato: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let src = b.floatChannelData, b.frameLength > 0,
              let out = AVAudioPCMBuffer(pcmFormat: formato, frameCapacity: b.frameLength),
              let dst = out.floatChannelData?[0] else { return nil }
        let n = Int(b.frameLength), ch = Int(b.format.channelCount)
        out.frameLength = b.frameLength
        if b.format.isInterleaved {
            for i in 0..<n {
                var s: Float = 0
                for c in 0..<ch { s += src[0][i * ch + c] }
                dst[i] = s / Float(ch)
            }
        } else if ch == 1 {
            memcpy(dst, src[0], n * MemoryLayout<Float>.size)
        } else {
            for i in 0..<n {
                var s: Float = 0
                for c in 0..<ch { s += src[c][i] }
                dst[i] = s / Float(ch)
            }
        }
        return out
    }

    /// −1 (izquierda) … +1 (derecha). nil si no es estéreo.
    static func balance(_ b: AVAudioPCMBuffer) -> Double? {
        guard b.format.channelCount >= 2, !b.format.isInterleaved, let src = b.floatChannelData, b.frameLength > 0 else { return nil }
        let n = vDSP_Length(b.frameLength)
        var l: Float = 0, r: Float = 0
        vDSP_svesq(src[0], 1, &l, n)
        vDSP_svesq(src[1], 1, &r, n)
        guard l + r > 1e-9 else { return nil }
        return Double((r - l) / (r + l))
    }

    /// Nivel en «dB aproximados»: dBFS + 100 (una habitación en silencio da unos 30–40).
    static func nivel(_ m: AVAudioPCMBuffer) -> Double {
        guard let x = m.floatChannelData?[0], m.frameLength > 0 else { return 0 }
        var rms: Float = 0
        vDSP_rmsqv(x, 1, &rms, vDSP_Length(m.frameLength))
        return min(120, max(0, 20 * log10(Double(max(rms, 1e-7))) + 100))
    }

    /// Cruces por cero por muestra.
    static func brillo(_ m: AVAudioPCMBuffer) -> Double {
        guard let x = m.floatChannelData?[0], m.frameLength > 1 else { return 0 }
        let n = Int(m.frameLength)
        var cruces = 0
        for i in 1..<n where (x[i - 1] >= 0) != (x[i] >= 0) { cruces += 1 }
        return Double(cruces) / Double(n)
    }

    /// Frecuencia fundamental (70–400 Hz) por autocorrelación, sobre el audio reducido a 1/4. 0 si no hay tono claro.
    static func tono(_ m: AVAudioPCMBuffer, sr: Double) -> Double {
        guard let x = m.floatChannelData?[0], m.frameLength >= 1024 else { return 0 }
        let paso = 4
        let n = Int(m.frameLength) / paso
        var y = [Float](repeating: 0, count: n)
        for i in 0..<n {
            var s: Float = 0
            for k in 0..<paso { s += x[i * paso + k] }
            y[i] = s / Float(paso)
        }
        let sr4 = sr / Double(paso)
        let lagMin = Int(sr4 / 400), lagMax = min(Int(sr4 / 70), n / 2)
        guard lagMax > lagMin else { return 0 }
        var r0: Float = 0
        vDSP_svesq(y, 1, &r0, vDSP_Length(n))
        guard r0 > 1e-9 else { return 0 }
        var mejor: Float = 0, mejorLag = 0
        y.withUnsafeBufferPointer { p in
            guard let base = p.baseAddress else { return }
            for lag in lagMin...lagMax {
                var r: Float = 0
                vDSP_dotpr(base, 1, base + lag, 1, &r, vDSP_Length(n - lag))
                let norm = r / r0 * Float(n) / Float(n - lag)
                if norm > mejor { mejor = norm; mejorLag = lag }
            }
        }
        return mejor > 0.45 && mejorLag > 0 ? sr4 / Double(mejorLag) : 0
    }
}

/// Va sumando trozos para sacar una huella media.
struct AcumHuella {
    var n = 0, nTono = 0, nBalance = 0
    var tono = 0.0, brillo = 0.0, balance = 0.0, nivel = 0.0

    mutating func sumar(_ m: AVAudioPCMBuffer, balance b: Double?, nivel db: Double, sr: Double) {
        n += 1
        brillo += Analisis.brillo(m)
        nivel += db
        let t = Analisis.tono(m, sr: sr)
        if t > 0 { tono += t; nTono += 1 }
        if let b { balance += b; nBalance += 1 }
    }

    var huella: Huella? {
        guard n > 0 else { return nil }
        return Huella(balance: nBalance > 0 ? balance / Double(nBalance) : nil,
                      tono: nTono > 0 ? tono / Double(nTono) : 0,
                      brillo: brillo / Double(n),
                      nivel: nivel / Double(n))
    }
}

/// Escucha toda la noche. Todo lo pesado pasa en su propia cola; avisa por los `al…` en el hilo principal.
final class Motor: NSObject, SNResultsObserving {
    struct Config {
        var sensibilidad: Double
        var tipos: Set<TipoSonido>
        var pausaRonquidos: Double   // segundos
        var maxClips: Int
        var retraso: Double          // segundos
    }

    private final class Clip {
        let id = UUID()
        var tipo: TipoSonido
        let inicio: Date
        let nombre: String
        var archivo: AVAudioFile?
        var segundos = 0.0
        var ultimaActividad: Double
        var ventanas: [TipoSonido: Int] = [:]
        var confianza: Double
        var acum = AcumHuella()

        init(tipo: TipoSonido, inicio: Date, ahora: Double, confianza: Double) {
            self.tipo = tipo
            self.inicio = inicio
            self.nombre = "\(id.uuidString).m4a"
            self.ultimaActividad = ahora
            self.confianza = confianza
            ventanas[tipo] = 1
        }
    }

    var alNivel: ((Double) -> Void)?
    var alMinuto: ((Minuto) -> Void)?
    var alEvento: ((Evento) -> Void)?
    var alDetectar: ((TipoSonido) -> Void)?
    private(set) var estereo = false

    private let config: Config
    private let engine = AVAudioEngine()
    private let cola = DispatchQueue(label: "dev.yagotg.nana.motor", qos: .userInitiated)
    private var analizador: SNAudioStreamAnalyzer?
    private var sr = 48000.0
    private var posicion: AVAudioFramePosition = 0
    private var segundos = 0.0
    private var suelo = 45.0

    private var preRoll: [(buf: AVAudioPCMBuffer, balance: Double?, nivel: Double)] = []
    private var preRollSegundos = 0.0
    private let preRollMax = 3.0

    private var detectado: [TipoSonido: Double] = [:]

    private var minutoInicio = Date()
    private var mSuma = 0.0, mMax = 0.0, mN = 0
    private var mVentanas: [TipoSonido: Int] = [:]
    private var mHuella = AcumHuella()

    private var clip: Clip?
    private var ultimoClipRonquido = -Double.infinity
    private var clips = 0
    private var contadorNivel = 0
    private var observadores: [NSObjectProtocol] = []

    private static let prioridad: [TipoSonido] = [.habla, .risa, .tos, .ronquido]

    init(config: Config) {
        self.config = config
    }

    private var escuchando: Bool { segundos >= config.retraso }

    // MARK: arrancar y parar

    func empezar() throws {
        try Sesion.configurar()
        try montar()
        let nc = NotificationCenter.default
        observadores.append(nc.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: nil) { [weak self] n in
            guard let self,
                  let v = n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: v) == .ended else { return }
            self.cola.async { self.rearrancar() }
        })
        observadores.append(nc.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil) { [weak self] _ in
            guard let self else { return }
            self.cola.async { self.rearrancar() }
        })
    }

    private func montar() throws {
        let input = engine.inputNode
        let f = input.outputFormat(forBus: 0)
        guard f.sampleRate > 0, f.channelCount > 0 else { throw FalloNana("No encuentro el micrófono.") }
        sr = f.sampleRate
        estereo = f.channelCount >= 2
        guard let mono = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1) else { throw FalloNana("Formato de audio raro.") }
        let an = SNAudioStreamAnalyzer(format: mono)
        let peticion = try SNClassifySoundRequest(classifierIdentifier: .version1)
        try an.add(peticion, withObserver: self)
        analizador = an
        posicion = 0
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: f) { [weak self] buf, _ in
            guard let self, let m = Analisis.mono(buf, formato: mono) else { return }
            let b = Analisis.balance(buf)
            self.cola.async { self.procesar(m, balance: b) }
        }
        engine.prepare()
        try engine.start()
    }

    /// Tras una llamada, una alarma o un cambio de micro.
    private func rearrancar() {
        cerrarClip()
        engine.stop()
        try? Sesion.configurar()
        try? montar()
    }

    func terminar() {
        for o in observadores { NotificationCenter.default.removeObserver(o) }
        observadores = []
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        cola.sync {
            cerrarClip()
            emitirMinuto()
            analizador?.completeAnalysis()
            analizador = nil
        }
        Sesion.soltar()
    }

    // MARK: cada trozo de audio (≈85 ms)

    private func procesar(_ m: AVAudioPCMBuffer, balance: Double?) {
        let dur = Double(m.frameLength) / sr
        segundos += dur
        let db = Analisis.nivel(m)

        // suelo de ruido: baja de golpe, sube despacio (1 dB por minuto)
        if db < suelo { suelo = db } else { suelo += dur / 60 }

        analizador?.analyze(m, atAudioFramePosition: posicion)
        posicion += AVAudioFramePosition(m.frameLength)

        // minuto
        mSuma += db; mN += 1; mMax = max(mMax, db)
        if escuchando, db > suelo + 5, fresco(.ronquido) || fresco(.habla) {
            mHuella.sumar(m, balance: balance, nivel: db, sr: sr)
        }
        if Date().timeIntervalSince(minutoInicio) >= 60 { emitirMinuto() }

        contadorNivel += 1
        if contadorNivel % 3 == 0 {
            DispatchQueue.main.async { [weak self] in self?.alNivel?(db) }
        }

        preRoll.append((m, balance, db))
        preRollSegundos += dur
        while preRollSegundos > preRollMax, let primero = preRoll.first {
            preRollSegundos -= Double(primero.buf.frameLength) / sr
            preRoll.removeFirst()
        }

        if let c = clip {
            try? c.archivo?.write(from: m)
            c.segundos += dur
            if db > suelo + 5 { c.acum.sumar(m, balance: balance, nivel: db, sr: sr) }
            if c.tipo == .ruido, db > suelo + 15 { c.ultimaActividad = segundos }
            let espera = c.tipo == .habla ? 4.0 : 2.5
            let maximo: Double = c.tipo == .habla ? 60 : (c.tipo == .ruido ? 15 : 20)
            if segundos - c.ultimaActividad > espera || c.segundos > maximo { cerrarClip() }
        } else if escuchando, clips < config.maxClips, let t = tipoParaAbrir(nivel: db) {
            abrirClip(t)
        }
    }

    private func fresco(_ t: TipoSonido, _ margen: Double = 1.0) -> Bool {
        guard let d = detectado[t] else { return false }
        return segundos - d <= margen
    }

    private func tipoParaAbrir(nivel db: Double) -> TipoSonido? {
        for t in Self.prioridad where config.tipos.contains(t) && fresco(t) {
            if t == .ronquido && segundos - ultimoClipRonquido < config.pausaRonquidos { continue }
            return t
        }
        if config.tipos.contains(.ruido), db > suelo + 18, !Self.prioridad.contains(where: { fresco($0) }) {
            return .ruido
        }
        return nil
    }

    // MARK: clips

    private func abrirClip(_ t: TipoSonido) {
        let c = Clip(tipo: t, inicio: Date().addingTimeInterval(-preRollSegundos), ahora: segundos, confianza: t == .ruido ? 1 : 0.5)
        let url = Almacen.carpetaClips.appendingPathComponent(c.nombre)
        let ajustes: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sr,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 64000,
        ]
        c.archivo = try? AVAudioFile(forWriting: url, settings: ajustes, commonFormat: .pcmFormatFloat32, interleaved: false)
        guard c.archivo != nil else { return }
        for p in preRoll {
            try? c.archivo?.write(from: p.buf)
            c.segundos += Double(p.buf.frameLength) / sr
            if p.nivel > suelo + 5 { c.acum.sumar(p.buf, balance: p.balance, nivel: p.nivel, sr: sr) }
        }
        clip = c
    }

    private func cerrarClip() {
        guard let c = clip else { return }
        clip = nil
        c.archivo = nil  // cierra el fichero
        let url = Almacen.carpetaClips.appendingPathComponent(c.nombre)

        // el tipo final: lo más interesante que se haya oído al menos dos veces
        var tipo = c.tipo
        if let mejor = Self.prioridad.first(where: { (c.ventanas[$0] ?? 0) >= 2 }) { tipo = mejor }
        let minimo = tipo == .ruido ? 0 : (tipo == .ronquido ? 3 : 2)
        guard (c.ventanas[tipo] ?? 0) >= minimo else {
            try? FileManager.default.removeItem(at: url)  // un falso aviso de medio segundo
            return
        }
        if tipo == .ronquido { ultimoClipRonquido = segundos }
        clips += 1
        let h = c.acum.huella ?? Huella(balance: nil, tono: 0, brillo: 0, nivel: suelo)
        let e = Evento(inicio: c.inicio, duracion: c.segundos, tipo: tipo, confianza: c.confianza, huella: h, archivo: c.nombre)
        DispatchQueue.main.async { [weak self] in self?.alEvento?(e) }
    }

    private func emitirMinuto() {
        guard mN > 0 else { return }
        let m = Minuto(inicio: minutoInicio, nivelMedio: mSuma / Double(mN), nivelMax: mMax, ventanas: mVentanas, huella: mHuella.huella, quien: nil)
        minutoInicio = Date()
        mSuma = 0; mMax = 0; mN = 0; mVentanas = [:]; mHuella = AcumHuella()
        DispatchQueue.main.async { [weak self] in self?.alMinuto?(m) }
    }

    // MARK: SNResultsObserving

    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let r = result as? SNClassificationResult else { return }
        var vistos: [TipoSonido: Double] = [:]
        for c in r.classifications {
            guard let t = TipoSonido.desde(etiqueta: c.identifier), vistos[t] == nil else { continue }
            let umbral = t == .ronquido ? config.sensibilidad * 0.8 : config.sensibilidad
            if c.confidence >= umbral { vistos[t] = c.confidence }
        }
        guard !vistos.isEmpty else { return }
        cola.async { [weak self] in
            guard let self else { return }
            for (t, conf) in vistos {
                self.detectado[t] = self.segundos
                guard self.escuchando else { continue }
                self.mVentanas[t, default: 0] += 1
                if let c = self.clip {
                    c.ventanas[t, default: 0] += 1
                    c.ultimaActividad = self.segundos
                    if t == c.tipo || Self.prioridad.firstIndex(of: t)! < (Self.prioridad.firstIndex(of: c.tipo) ?? 99) {
                        c.confianza = max(c.confianza, conf)
                    }
                }
            }
            if self.escuchando, let t = Self.prioridad.first(where: { vistos[$0] != nil }) {
                DispatchQueue.main.async { self.alDetectar?(t) }
            }
        }
    }

    func request(_ request: SNRequest, didFailWithError error: Error) {}
    func requestDidComplete(_ request: SNRequest) {}
}

/// Graba unos segundos con una persona hablando desde su almohada, para saber de qué lado suena cada una.
final class Calibrador {
    private let engine = AVAudioEngine()
    private let cola = DispatchQueue(label: "dev.yagotg.nana.calibrar")
    private var trozos: [(m: AVAudioPCMBuffer, balance: Double?, nivel: Double)] = []
    private(set) var estereo = false

    func grabar(segundos: Double, listo: @escaping (Huella?, Bool) -> Void) {
        do {
            try Sesion.configurar()
            let input = engine.inputNode
            let f = input.outputFormat(forBus: 0)
            guard f.sampleRate > 0, let mono = AVAudioFormat(standardFormatWithSampleRate: f.sampleRate, channels: 1) else {
                listo(nil, false); return
            }
            estereo = f.channelCount >= 2
            input.installTap(onBus: 0, bufferSize: 4096, format: f) { [weak self] buf, _ in
                guard let self, let m = Analisis.mono(buf, formato: mono) else { return }
                let b = Analisis.balance(buf)
                let db = Analisis.nivel(m)
                self.cola.async { self.trozos.append((m, b, db)) }
            }
            engine.prepare()
            try engine.start()
        } catch {
            listo(nil, false); return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + segundos) { [self] in
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
            Sesion.soltar()
            let sr = engine.inputNode.outputFormat(forBus: 0).sampleRate
            cola.async { [self] in
                // solo los trozos claramente por encima del silencio
                let niveles = trozos.map(\.nivel).sorted()
                let base = niveles.isEmpty ? 0 : niveles[niveles.count / 5]
                var acum = AcumHuella()
                for t in trozos where t.nivel > base + 8 { acum.sumar(t.m, balance: t.balance, nivel: t.nivel, sr: sr > 0 ? sr : 48000) }
                let h = acum.huella
                let e = estereo
                DispatchQueue.main.async { listo(h, e) }
            }
        }
    }
}
