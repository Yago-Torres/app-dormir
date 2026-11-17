import Foundation
import Observation

enum PosicionMovil: String, CaseIterable, Identifiable {
    case medio, ladoAitana, ladoYago

    var id: String { rawValue }

    var nombre: String {
        switch self {
        case .medio: return "En medio (cabecero)"
        case .ladoAitana: return "En la mesilla de \(Ajustes.compartidos.nombreAitana)"
        case .ladoYago: return "En la mesilla de \(Ajustes.compartidos.nombreYago)"
        }
    }
}

/// Ajustes guardados en UserDefaults. Un solo objeto para toda la app (`Ajustes.compartidos`).
@Observable
final class Ajustes {
    static let compartidos = Ajustes()

    private let d = UserDefaults.standard

    var nombreAitana: String { didSet { d.set(nombreAitana, forKey: "nombreAitana") } }
    var nombreYago: String { didSet { d.set(nombreYago, forKey: "nombreYago") } }
    var posicion: PosicionMovil { didSet { d.set(posicion.rawValue, forKey: "posicion") } }
    /// Seguridad mínima del clasificador (0–1) para contar un sonido.
    var sensibilidad: Double { didSet { d.set(sensibilidad, forKey: "sensibilidad") } }
    var tiposGuardados: Set<TipoSonido> { didSet { d.set(tiposGuardados.map(\.rawValue), forKey: "tiposGuardados") } }
    /// Minutos entre dos clips de ronquido (los minutos roncando se cuentan igual).
    var pausaRonquidos: Double { didSet { d.set(pausaRonquidos, forKey: "pausaRonquidos") } }
    var maxClips: Int { didSet { d.set(maxClips, forKey: "maxClips") } }
    /// Los clips que no son favoritos se borran pasados estos días (0 = nunca).
    var borrarTrasDias: Int { didSet { d.set(borrarTrasDias, forKey: "borrarTrasDias") } }
    /// Minutos sin guardar nada al empezar (para no grabar mientras os dormís).
    var retrasoInicio: Double { didSet { d.set(retrasoInicio, forKey: "retrasoInicio") } }
    var ultimaCama: Cama { didSet { d.set(ultimaCama.rawValue, forKey: "ultimaCama") } }
    /// Balance estéreo medido al calibrar con cada persona hablando desde su almohada.
    var balanceAitana: Double? { didSet { d.set(balanceAitana, forKey: "balanceAitana") } }
    var balanceYago: Double? { didSet { d.set(balanceYago, forKey: "balanceYago") } }

    private init() {
        nombreAitana = d.string(forKey: "nombreAitana") ?? "Aitana"
        nombreYago = d.string(forKey: "nombreYago") ?? "Yago"
        posicion = PosicionMovil(rawValue: d.string(forKey: "posicion") ?? "") ?? .medio
        sensibilidad = d.object(forKey: "sensibilidad") as? Double ?? 0.5
        if let t = d.stringArray(forKey: "tiposGuardados") {
            tiposGuardados = Set(t.compactMap(TipoSonido.init(rawValue:)))
        } else {
            tiposGuardados = [.ronquido, .habla, .tos, .risa]
        }
        pausaRonquidos = d.object(forKey: "pausaRonquidos") as? Double ?? 3
        maxClips = d.object(forKey: "maxClips") as? Int ?? 200
        borrarTrasDias = d.object(forKey: "borrarTrasDias") as? Int ?? 30
        retrasoInicio = d.object(forKey: "retrasoInicio") as? Double ?? 10
        ultimaCama = Cama(rawValue: d.string(forKey: "ultimaCama") ?? "") ?? .aitana
        balanceAitana = d.object(forKey: "balanceAitana") as? Double
        balanceYago = d.object(forKey: "balanceYago") as? Double
    }
}
