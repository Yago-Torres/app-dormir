import Foundation

/// Adivina de quién es un sonido cuando dormís los dos.
///
/// Dos pistas, y ninguna es magia:
/// 1. **Lado** (solo con el móvil en medio y grabando en estéreo): el balance izquierda/derecha del sonido comparado
///    con el que se midió al calibrar con cada una hablando desde su almohada.
/// 2. **Cómo suena** cada una: tono y brillo medios de los sonidos que ya habéis confirmado. Cuantos más confirméis,
///    mejor acierta.
/// Si las pistas no se ponen de acuerdo, devuelve nil («no lo sé») en vez de inventar.
enum Atribucion {
    static func adivinar(_ h: Huella?, tipo: TipoSonido, cama: Cama, estereo: Bool, perfiles: [String: Perfil]) -> Persona? {
        if cama != .juntos { return cama.personas.first }
        guard let h else { return nil }
        let aj = Ajustes.compartidos
        var aFavorDeAitana = 0.0

        // 1. Lado
        if estereo, aj.posicion == .medio, let b = h.balance {
            if let bA = aj.balanceAitana, let bY = aj.balanceYago, abs(bA - bY) > 0.08 {
                aFavorDeAitana += 1.5 * (abs(b - bY) - abs(b - bA)) / abs(bA - bY)
            } else if let pA = perfiles["aitana-\(tipo.rawValue)"], let pY = perfiles["yago-\(tipo.rawValue)"],
                      pA.nBalance >= 2, pY.nBalance >= 2, abs(pA.balance - pY.balance) > 0.08 {
                aFavorDeAitana += 1.0 * (abs(b - pY.balance) - abs(b - pA.balance)) / abs(pA.balance - pY.balance)
            }
        }

        // 2. Cómo suena
        if let pA = perfiles["aitana-\(tipo.rawValue)"], let pY = perfiles["yago-\(tipo.rawValue)"], pA.n >= 2, pY.n >= 2 {
            let dA = distancia(h, pA), dY = distancia(h, pY)
            let peso = min(1.0, Double(pA.n + pY.n) / 12)
            aFavorDeAitana += 2 * peso * (dY - dA) / (dA + dY + 0.001)
        }

        if aFavorDeAitana > 0.3 { return .aitana }
        if aFavorDeAitana < -0.3 { return .yago }
        return nil
    }

    private static func distancia(_ h: Huella, _ p: Perfil) -> Double {
        var d = abs(h.brillo - p.brillo) / 0.03
        if h.tono > 0, p.tono > 0 { d += abs(h.tono - p.tono) / 80 }
        return d
    }

    /// De quién es un minuto ronco o hablado: lo confirmado en un clip de ese minuto manda; si no, se adivina.
    static func quienDelMinuto(_ m: Minuto, noche: Noche, perfiles: [String: Perfil]) -> Persona? {
        if noche.cama != .juntos { return noche.cama.personas.first }
        guard m.ronca || m.habla else { return nil }
        let tipo: TipoSonido = m.ronca ? .ronquido : .habla
        let fin = m.inicio.addingTimeInterval(60)
        if let e = noche.eventos.first(where: { $0.tipo == tipo && $0.quienConfirmado != nil
            && $0.inicio < fin && $0.inicio.addingTimeInterval($0.duracion) > m.inicio }) {
            return e.quienConfirmado
        }
        return adivinar(m.huella, tipo: tipo, cama: noche.cama, estereo: noche.estereo, perfiles: perfiles)
    }
}
