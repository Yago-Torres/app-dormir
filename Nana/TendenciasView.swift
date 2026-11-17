import Charts
import SwiftUI

struct TendenciasView: View {
    @Environment(Almacen.self) private var almacen
    @State private var dias = 30

    private struct Punto: Identifiable {
        let id = UUID()
        let dia: Date
        let persona: Persona
        let valor: Int
    }

    private var noches: [Noche] {
        let limite = Date().addingTimeInterval(-Double(dias) * 86400)
        return almacen.noches.filter { $0.fin != nil && $0.inicio >= limite && $0.duracion > 1800 }.sorted { $0.inicio < $1.inicio }
    }

    private var puntos: [Punto] {
        noches.flatMap { n in n.cama.personas.map { Punto(dia: n.inicio, persona: $0, valor: n.puntuacion($0)) } }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Picker("Periodo", selection: $dias) {
                        Text("7 días").tag(7)
                        Text("30 días").tag(30)
                        Text("90 días").tag(90)
                        Text("1 año").tag(365)
                    }
                    .pickerStyle(.segmented)

                    if noches.isEmpty {
                        ContentUnavailableView("Faltan noches", systemImage: "chart.xyaxis.line", description: Text("Con unas cuantas noches aquí verás cómo vais."))
                    } else {
                        grafica
                        medias
                        factores
                    }
                }
                .padding(16)
            }
            .background(Estilo.fondo)
            .navigationTitle("Tendencias")
        }
    }

    private var grafica: some View {
        Tarjeta(titulo: "Puntuación de ronquidos") {
            Chart(puntos) { p in
                LineMark(x: .value("Día", p.dia, unit: .day), y: .value("Puntuación", p.valor))
                    .foregroundStyle(by: .value("Quién", p.persona.nombre))
                    .interpolationMethod(.catmullRom)
                PointMark(x: .value("Día", p.dia, unit: .day), y: .value("Puntuación", p.valor))
                    .foregroundStyle(by: .value("Quién", p.persona.nombre))
            }
            .chartForegroundStyleScale([Persona.aitana.nombre: Persona.aitana.color, Persona.yago.nombre: Persona.yago.color])
            .chartYScale(domain: 0...100)
            .frame(height: 180)
            Text("0 = ni un ronquido · 100 = media hora roncando por cada hora de sueño.")
                .font(.caption2).foregroundStyle(Estilo.suave)
        }
    }

    private var medias: some View {
        HStack(spacing: 12) {
            ForEach(Persona.durmientes) { p in
                let suyas = noches.filter { $0.cama.personas.contains(p) }
                Tarjeta {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(p.nombre).font(.headline).foregroundStyle(p.color)
                        if suyas.isEmpty {
                            Text("Sin noches").font(.caption).foregroundStyle(Estilo.suave)
                        } else {
                            let media = suyas.map { $0.puntuacion(p) }.reduce(0, +) / suyas.count
                            let horas = suyas.map(\.horas).reduce(0, +) / Double(suyas.count)
                            let frases = suyas.map { n in n.eventos(de: p).filter { $0.tipo == .habla }.count }.reduce(0, +)
                            let notas = suyas.compactMap { $0.valoracion[p.rawValue] }
                            Text("\(media)").font(.system(size: 34, weight: .bold, design: .rounded))
                            Text("de media · \(suyas.count) noches").font(.caption).foregroundStyle(Estilo.suave)
                            Text("Duerme \(String(format: "%.1f", horas)) h").font(.caption)
                            Text("\(frases) frases en sueños").font(.caption)
                            if !notas.isEmpty {
                                Text("★ \(String(format: "%.1f", Double(notas.reduce(0, +)) / Double(notas.count)))").font(.caption)
                            }
                        }
                    }
                }
            }
        }
    }

    /// Para cada factor: puntuación media las noches con él frente a las noches sin él.
    private var factores: some View {
        Tarjeta(titulo: "Qué os hace roncar") {
            let filas = filasFactores()
            if filas.isEmpty {
                Text("Marca factores al empezar la noche (alcohol, congestión…) y aquí verás cuáles empeoran los ronquidos.")
                    .font(.footnote).foregroundStyle(Estilo.suave)
            }
            ForEach(filas, id: \.clave) { f in
                HStack {
                    Image(systemName: f.factor.icono).frame(width: 22).foregroundStyle(f.persona.color)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(f.factor.nombre).font(.subheadline)
                        Text("\(f.persona.nombre) · \(f.noches) \(f.noches == 1 ? "noche" : "noches")").font(.caption2).foregroundStyle(Estilo.suave)
                    }
                    Spacer()
                    Text(f.diferencia > 0 ? "+\(f.diferencia)" : "\(f.diferencia)")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(f.diferencia > 5 ? .orange : (f.diferencia < -5 ? .green : Estilo.suave))
                }
            }
            if !filas.isEmpty {
                Text("Diferencia de puntuación frente a las noches sin ese factor. Con pocas noches, tómalo con calma.")
                    .font(.caption2).foregroundStyle(Estilo.suave)
            }
        }
    }

    private struct FilaFactor {
        let persona: Persona
        let factor: Factor
        let noches: Int
        let diferencia: Int
        var clave: String { persona.rawValue + factor.rawValue }
    }

    private func filasFactores() -> [FilaFactor] {
        var filas: [FilaFactor] = []
        for p in Persona.durmientes {
            let suyas = noches.filter { $0.cama.personas.contains(p) }
            for f in Factor.allCases {
                let con = suyas.filter { $0.factores(de: p).contains(f) }
                let sin = suyas.filter { !$0.factores(de: p).contains(f) }
                guard !con.isEmpty, !sin.isEmpty else { continue }
                let mCon = Double(con.map { $0.puntuacion(p) }.reduce(0, +)) / Double(con.count)
                let mSin = Double(sin.map { $0.puntuacion(p) }.reduce(0, +)) / Double(sin.count)
                filas.append(FilaFactor(persona: p, factor: f, noches: con.count, diferencia: Int((mCon - mSin).rounded())))
            }
        }
        return filas.sorted { abs($0.diferencia) > abs($1.diferencia) }
    }
}
