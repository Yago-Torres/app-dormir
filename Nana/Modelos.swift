import Foundation
import SwiftUI

/// Quién duerme o quién hizo un ruido. `ambos` = los dos a la vez; `nadie` = no era ninguno (la calle, el gato…).
enum Persona: String, Codable, CaseIterable, Identifiable {
    case aitana, yago, ambos, nadie

    var id: String { rawValue }

    var nombre: String {
        switch self {
        case .aitana: return Ajustes.compartidos.nombreAitana
        case .yago: return Ajustes.compartidos.nombreYago
        case .ambos: return "Los dos"
        case .nadie: return "Ninguno"
        }
    }

    var color: Color {
        switch self {
        case .aitana: return Color(red: 0.96, green: 0.56, blue: 0.78)
        case .yago: return Color(red: 0.36, green: 0.80, blue: 0.78)
        case .ambos: return Color(red: 0.72, green: 0.66, blue: 0.98)
        case .nadie: return .gray
        }
    }

    var icono: String {
        switch self {
        case .aitana, .yago: return "person.fill"
        case .ambos: return "person.2.fill"
        case .nadie: return "speaker.wave.2"
        }
    }

    /// Las dos personas de verdad (para perfiles, tendencias…).
    static let durmientes: [Persona] = [.aitana, .yago]
}

/// Quién está en la cama esta noche.
enum Cama: String, Codable, CaseIterable, Identifiable {
    case aitana, yago, juntos

    var id: String { rawValue }

    var nombre: String {
        switch self {
        case .aitana: return "\(Ajustes.compartidos.nombreAitana) sola"
        case .yago: return "\(Ajustes.compartidos.nombreYago) solo"
        case .juntos: return "Los dos"
        }
    }

    var personas: [Persona] {
        switch self {
        case .aitana: return [.aitana]
        case .yago: return [.yago]
        case .juntos: return [.aitana, .yago]
        }
    }
}

enum TipoSonido: String, Codable, CaseIterable, Identifiable {
    case ronquido, habla, tos, risa, ruido

    var id: String { rawValue }

    var nombre: String {
        switch self {
        case .ronquido: return "Ronquido"
        case .habla: return "Habla en sueños"
        case .tos: return "Tos"
        case .risa: return "Risa"
        case .ruido: return "Otro ruido"
        }
    }

    var plural: String {
        switch self {
        case .ronquido: return "Ronquidos"
        case .habla: return "Hablando"
        case .tos: return "Tos"
        case .risa: return "Risas"
        case .ruido: return "Ruidos"
        }
    }

    var icono: String {
        switch self {
        case .ronquido: return "zzz"
        case .habla: return "quote.bubble.fill"
        case .tos: return "lungs.fill"
        case .risa: return "face.smiling.inverse"
        case .ruido: return "waveform"
        }
    }

    /// Las etiquetas del clasificador de sonidos de Apple (SoundAnalysis, versión 1) que cuentan como este tipo.
    static func desde(etiqueta: String) -> TipoSonido? {
        switch etiqueta {
        case "snoring": return .ronquido
        case "speech", "whispering", "shout", "yell", "battle_cry", "screaming", "babble", "singing", "humming":
            return .habla
        case "cough", "sneeze", "throat_clearing": return .tos
        case "laughter", "giggling", "chuckle_chortle", "snicker", "belly_laugh": return .risa
        default: return nil
        }
    }
}

/// Rasgos sencillos de un trozo de sonido para adivinar de quién es.
/// - balance: −1 todo por la izquierda del micro, +1 todo por la derecha (solo si el iPhone graba en estéreo).
/// - tono: frecuencia fundamental en Hz (0 si no se oye tono claro).
/// - brillo: cruces por cero por muestra (sube con los sonidos agudos o con aire).
/// - nivel: dB aproximados.
struct Huella: Codable, Equatable {
    var balance: Double?
    var tono: Double
    var brillo: Double
    var nivel: Double
}

/// Un trozo guardado: un ronquido, una frase dicha en sueños…
struct Evento: Codable, Identifiable, Equatable {
    var id = UUID()
    var inicio: Date
    var duracion: Double
    var tipo: TipoSonido
    var confianza: Double
    var huella: Huella
    /// Lo que adivina Nana.
    var quienAdivinado: Persona?
    /// Lo que ha dicho una persona (manda sobre lo adivinado).
    var quienConfirmado: Persona?
    var favorito = false
    var archivo: String?
    var nota: String?

    var quien: Persona? { quienConfirmado ?? quienAdivinado }
}

/// Resumen de un minuto de la noche, para la gráfica y para contar minutos roncando.
struct Minuto: Codable, Identifiable, Equatable {
    var inicio: Date
    var nivelMedio: Double
    var nivelMax: Double
    /// Ventanas (≈0,5 s) en las que el clasificador oyó cada tipo.
    var ventanas: [TipoSonido: Int]
    var huella: Huella?
    var quien: Persona?
    /// La confianza más alta de «ronquido» del minuto, aunque no pasara el umbral (diagnóstico; nil en noches viejas).
    var maxRonquido: Double? = nil

    var id: Date { inicio }

    /// Roncando: al menos 4 ventanas con ronquido en el minuto (un ronquido cada 4–5 s da 12–15 ronquidos por minuto).
    var ronca: Bool { (ventanas[.ronquido] ?? 0) >= 4 }
    var habla: Bool { (ventanas[.habla] ?? 0) >= 2 }
}

enum Factor: String, Codable, CaseIterable, Identifiable {
    case alcohol, cenaTarde, congestion, cansancio, deporte, tirasNasales, bocaArriba, cafe, estres, almohadaAlta, medicacion

    var id: String { rawValue }

    var nombre: String {
        switch self {
        case .alcohol: return "Alcohol"
        case .cenaTarde: return "Cena tarde"
        case .congestion: return "Congestión"
        case .cansancio: return "Muy cansada/o"
        case .deporte: return "Deporte"
        case .tirasNasales: return "Tiras nasales"
        case .bocaArriba: return "Boca arriba"
        case .cafe: return "Café tarde"
        case .estres: return "Estrés"
        case .almohadaAlta: return "Almohada alta"
        case .medicacion: return "Medicación"
        }
    }

    var icono: String {
        switch self {
        case .alcohol: return "wineglass.fill"
        case .cenaTarde: return "fork.knife"
        case .congestion: return "nose.fill"
        case .cansancio: return "battery.25percent"
        case .deporte: return "figure.run"
        case .tirasNasales: return "bandage.fill"
        case .bocaArriba: return "bed.double.fill"
        case .cafe: return "cup.and.saucer.fill"
        case .estres: return "bolt.heart.fill"
        case .almohadaAlta: return "rectangle.stack.fill"
        case .medicacion: return "pills.fill"
        }
    }
}

struct Noche: Codable, Identifiable, Equatable {
    var id = UUID()
    var inicio: Date
    var fin: Date?
    var cama: Cama
    var estereo = false
    var minutos: [Minuto] = []
    var eventos: [Evento] = []
    /// Factores de cada persona (clave: rawValue de Persona).
    var factores: [String: [Factor]] = [:]
    /// Cómo ha dormido cada una del 1 al 5 (clave: rawValue de Persona).
    var valoracion: [String: Int] = [:]
    var nota = ""
    /// Lo que fue mal esa noche («se cortó el micro»…), con la hora. Opcional: las noches viejas no lo tienen.
    var avisos: [String]?

    var duracion: TimeInterval { (fin ?? Date()).timeIntervalSince(inicio) }
    var horas: Double { max(duracion / 3600, 0.01) }

    func factores(de p: Persona) -> [Factor] { factores[p.rawValue] ?? [] }

    /// Minutos roncando que se atribuyen a la persona (los de «los dos» cuentan para las dos).
    func minutosRoncando(_ p: Persona) -> Int {
        minutos.filter { $0.ronca && (cama.personas.count == 1 ? cama.personas.first == p : ($0.quien == p || $0.quien == .ambos)) }.count
    }

    func minutosRoncandoTotal() -> Int { minutos.filter(\.ronca).count }

    /// Puntuación tipo «snore score»: minutos roncando por hora, en una escala de 0 a 100.
    func puntuacion(_ p: Persona) -> Int {
        let porHora = Double(minutosRoncando(p)) / horas
        return min(100, Int((porHora / 30 * 100).rounded()))
    }

    func eventos(de p: Persona) -> [Evento] {
        eventos.filter { $0.quien == p || ($0.quien == .ambos && p != .nadie) }
    }

    var titulo: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateFormat = "EEEE d 'de' MMMM"
        return f.string(from: inicio).capitalizedPrimera
    }
}

extension String {
    var capitalizedPrimera: String { prefix(1).uppercased() + dropFirst() }
}

extension TimeInterval {
    /// «7 h 12 min»
    var textoHoras: String {
        let m = Int(self / 60)
        return m >= 60 ? "\(m / 60) h \(m % 60) min" : "\(m) min"
    }
}
