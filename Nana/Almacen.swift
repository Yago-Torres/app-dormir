import Foundation
import Observation

/// Lo que Nana ha aprendido de cómo suena cada persona (media de las huellas confirmadas).
struct Perfil: Codable {
    var n: Int = 0
    var tono: Double = 0
    var brillo: Double = 0
    var nBalance: Int = 0
    var balance: Double = 0

    mutating func aprender(_ h: Huella) {
        n += 1
        let k = 1 / Double(n)
        tono += (h.tono - tono) * k
        brillo += (h.brillo - brillo) * k
        if let b = h.balance {
            nBalance += 1
            balance += (b - balance) / Double(nBalance)
        }
    }
}

/// Todas las noches y perfiles, en Documentos/nana.json. Los clips van en Documentos/Clips/.
@Observable
final class Almacen {
    var noches: [Noche] = []
    /// Clave: "<persona>-<tipo>", p. ej. "aitana-ronquido".
    var perfiles: [String: Perfil] = [:]
    /// Si no se pudo leer o guardar nana.json (lo enseña Inicio).
    var error: String?

    private struct Disco: Codable {
        var noches: [Noche]
        var perfiles: [String: Perfil]
    }

    static let documentos = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    static let carpetaClips = documentos.appendingPathComponent("Clips", isDirectory: true)
    private let fichero = documentos.appendingPathComponent("nana.json")

    init() {
        try? FileManager.default.createDirectory(at: Self.carpetaClips, withIntermediateDirectories: true)
        if let datos = try? Data(contentsOf: fichero) {
            do {
                let disco = try JSONDecoder.nana.decode(Disco.self, from: datos)
                noches = disco.noches
                perfiles = disco.perfiles
            } catch {
                // no se pisa: se aparta una copia antes de que el primer guardado lo sobrescriba
                let copia = Self.documentos.appendingPathComponent("nana-ilegible-\(Int(Date().timeIntervalSince1970)).json")
                try? FileManager.default.copyItem(at: fichero, to: copia)
                self.error = "No he podido leer tus noches guardadas (\(error.localizedDescription)). Las he apartado en \(copia.lastPathComponent)."
            }
        }
        // una noche que se quedó abierta (la app se cerró a la fuerza): se da por acabada en su último minuto
        for i in noches.indices where noches[i].fin == nil {
            noches[i].fin = noches[i].minutos.last.map { $0.inicio.addingTimeInterval(60) } ?? noches[i].inicio
        }
        limpiarClipsViejos()
    }

    func guardar() {
        let disco = Disco(noches: noches, perfiles: perfiles)
        do {
            let datos = try JSONEncoder.nana.encode(disco)
            try datos.write(to: fichero, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            self.error = "No he podido guardar: \(error.localizedDescription)"
        }
    }

    // MARK: noches

    var nochesOrdenadas: [Noche] { noches.sorted { $0.inicio > $1.inicio } }

    func guardarNoche(_ n: Noche) {
        if let i = noches.firstIndex(where: { $0.id == n.id }) { noches[i] = n } else { noches.append(n) }
        guardar()
    }

    func noche(_ id: UUID) -> Noche? { noches.first { $0.id == id } }

    func borrarNoche(_ id: UUID) {
        guard let n = noche(id) else { return }
        for e in n.eventos { borrarArchivo(e.archivo) }
        noches.removeAll { $0.id == id }
        guardar()
    }

    func editar(_ id: UUID, _ cambio: (inout Noche) -> Void) {
        guard let i = noches.firstIndex(where: { $0.id == id }) else { return }
        cambio(&noches[i])
        guardar()
    }

    // MARK: eventos

    static func url(_ archivo: String?) -> URL? {
        archivo.map { carpetaClips.appendingPathComponent($0) }
    }

    private func borrarArchivo(_ archivo: String?) {
        if let u = Self.url(archivo) { try? FileManager.default.removeItem(at: u) }
    }

    func borrarEvento(noche: UUID, evento: UUID) {
        editar(noche) { n in
            if let e = n.eventos.first(where: { $0.id == evento }) { borrarArchivo(e.archivo) }
            n.eventos.removeAll { $0.id == evento }
        }
    }

    /// Alguien dice de quién era un sonido: se apunta, Nana aprende y vuelve a adivinar el resto de la noche.
    func confirmar(noche: UUID, evento: UUID, quien: Persona) {
        editar(noche) { n in
            guard let i = n.eventos.firstIndex(where: { $0.id == evento }) else { return }
            n.eventos[i].quienConfirmado = quien
            if quien == .aitana || quien == .yago {
                perfiles["\(quien.rawValue)-\(n.eventos[i].tipo.rawValue)", default: Perfil()].aprender(n.eventos[i].huella)
            }
        }
        reatribuirTodo()
    }

    func alternarFavorito(noche: UUID, evento: UUID) {
        editar(noche) { n in
            if let i = n.eventos.firstIndex(where: { $0.id == evento }) { n.eventos[i].favorito.toggle() }
        }
    }

    /// Vuelve a adivinar todo lo no confirmado con los perfiles de ahora.
    func reatribuirTodo() {
        for i in noches.indices {
            let cama = noches[i].cama
            let estereo = noches[i].estereo
            for j in noches[i].eventos.indices {
                let e = noches[i].eventos[j]
                noches[i].eventos[j].quienAdivinado = Atribucion.adivinar(e.huella, tipo: e.tipo, cama: cama, estereo: estereo, perfiles: perfiles)
            }
            for j in noches[i].minutos.indices {
                noches[i].minutos[j].quien = Atribucion.quienDelMinuto(noches[i].minutos[j], noche: noches[i], perfiles: perfiles)
            }
        }
        guardar()
    }

    func olvidarPerfiles() {
        perfiles = [:]
        reatribuirTodo()
    }

    // MARK: espacio

    func limpiarClipsViejos() {
        let dias = Ajustes.compartidos.borrarTrasDias
        guard dias > 0 else { return }
        let limite = Date().addingTimeInterval(-Double(dias) * 86400)
        var cambiado = false
        for i in noches.indices where noches[i].inicio < limite {
            for j in noches[i].eventos.indices where !noches[i].eventos[j].favorito && noches[i].eventos[j].archivo != nil {
                borrarArchivo(noches[i].eventos[j].archivo)
                noches[i].eventos[j].archivo = nil
                cambiado = true
            }
        }
        if cambiado { guardar() }
    }

    var espacioClips: Int64 {
        let urls = (try? FileManager.default.contentsOfDirectory(at: Self.carpetaClips, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return urls.reduce(0) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }
}

extension JSONEncoder {
    static let nana: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}

extension JSONDecoder {
    static let nana: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
