import Charts
import SwiftUI

struct NocheDetalleView: View {
    let id: UUID
    var recienAcabada = false

    @Environment(Almacen.self) private var almacen
    @Environment(\.dismiss) private var dismiss
    @State private var filtro: Filtro = .todos
    @State private var confirmarBorrado = false

    enum Filtro: String, CaseIterable, Identifiable {
        case todos = "Todo", ronquidos = "Ronquidos", habla = "Habla", dudas = "¿Quién?", favoritos = "★"
        var id: String { rawValue }
    }

    var body: some View {
        Group {
            if let n = almacen.noche(id) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        cabecera(n)
                        if let avisos = n.avisos, !avisos.isEmpty {
                            Tarjeta(titulo: "Esta noche algo falló") {
                                ForEach(avisos, id: \.self) { a in
                                    Label(a, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(.orange)
                                }
                            }
                        }
                        puntuaciones(n)
                        if n.cama == .juntos { avisoDudas(n) }
                        grafica(n)
                        valoracion(n)
                        clips(n)
                        notaYFactores(n)
                    }
                    .padding(16)
                }
            } else {
                ContentUnavailableView("Esta noche ya no existe", systemImage: "moon")
            }
        }
        .background(Estilo.fondo)
        .navigationTitle(almacen.noche(id)?.titulo ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Button("Borrar la noche", systemImage: "trash", role: .destructive) { confirmarBorrado = true }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .confirmationDialog("¿Borrar esta noche y todos sus clips?", isPresented: $confirmarBorrado, titleVisibility: .visible) {
            Button("Borrar", role: .destructive) {
                almacen.borrarNoche(id)
                dismiss()
            }
        }
    }

    // MARK: piezas

    private func cabecera(_ n: Noche) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if recienAcabada {
                Text("Buenos días ☀︎").font(.title2.weight(.bold))
            }
            Text("\(Estilo.hora(n.inicio)) – \(Estilo.hora(n.fin ?? Date())) · \(n.duracion.textoHoras) · \(n.cama.nombre)")
                .font(.subheadline)
                .foregroundStyle(Estilo.suave)
        }
    }

    private func puntuaciones(_ n: Noche) -> some View {
        HStack(spacing: 12) {
            ForEach(n.cama.personas) { p in
                Tarjeta {
                    HStack(spacing: 12) {
                        Anillo(valor: n.puntuacion(p), color: p.color)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(p.nombre).font(.headline).foregroundStyle(p.color)
                            Text("\(n.minutosRoncando(p)) min roncando").font(.caption)
                            let ev = n.eventos(de: p)
                            Text("\(ev.filter { $0.tipo == .habla }.count) frases · \(ev.filter { $0.tipo == .tos }.count) tos")
                                .font(.caption).foregroundStyle(Estilo.suave)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func avisoDudas(_ n: Noche) -> some View {
        let sinConfirmar = n.eventos.filter { $0.quienConfirmado == nil && $0.tipo != .ruido }.count
        if sinConfirmar > 0 {
            Button { filtro = .dudas } label: {
                HStack(spacing: 10) {
                    Image(systemName: "person.2.wave.2.fill").foregroundStyle(Estilo.acento)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("¿De quién es cada sonido?").font(.subheadline.weight(.semibold))
                        Text("Hay \(sinConfirmar) sin confirmar. Escúchalos y elige quién era: Nana aprende y acertará más.")
                            .font(.caption).foregroundStyle(Estilo.suave)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(Estilo.suave)
                }
                .padding(14)
                .background(Estilo.acento.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
        }
    }

    private func colorMinuto(_ m: Minuto) -> Color {
        guard m.ronca || m.habla else { return Color.white.opacity(0.18) }
        return (m.quien ?? .ambos).color.opacity(m.quien == nil ? 0.6 : 1)
    }

    private func grafica(_ n: Noche) -> some View {
        Tarjeta(titulo: "La noche") {
            if n.minutos.isEmpty {
                Text("Muy corta para dibujarla.").font(.footnote).foregroundStyle(Estilo.suave)
            } else {
                Chart {
                    ForEach(n.minutos) { m in
                        BarMark(x: .value("Hora", m.inicio, unit: .minute), y: .value("Nivel", max(0, m.nivelMax - 25)))
                            .foregroundStyle(colorMinuto(m))
                    }
                    ForEach(n.eventos.filter { $0.tipo == .habla }) { e in
                        PointMark(x: .value("Hora", e.inicio), y: .value("Nivel", 62))
                            .symbol { Image(systemName: "quote.bubble.fill").font(.system(size: 9)).foregroundStyle(Estilo.luna) }
                    }
                }
                .chartYAxis(.hidden)
                .chartYScale(domain: 0...66)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .hour)) { _ in
                        AxisGridLine().foregroundStyle(Estilo.borde)
                        AxisValueLabel(format: .dateTime.hour())
                    }
                }
                .frame(height: 150)
                leyenda(n)
                diagnostico(n)
            }
        }
    }

    /// Para ajustar la sensibilidad: lo más parecido a un ronquido que oyó, frente a lo que hace falta para contarlo.
    @ViewBuilder
    private func diagnostico(_ n: Noche) -> some View {
        if let maximo = n.minutos.compactMap(\.maxRonquido).max() {
            let umbral = Motor.umbralRonquido(Ajustes.compartidos.sensibilidad)
            let pasan = n.minutos.filter { ($0.maxRonquido ?? 0) >= umbral }.count
            Text("Ronquido más claro que oyó: \(Int(maximo * 100)) % (cuenta a partir del \(Int(umbral * 100)) %; \(pasan) min lo pasan)."
                 + (maximo < umbral && maximo > umbral * 0.4 ? " Si roncabais, sube la sensibilidad en Ajustes." : ""))
                .font(.caption2).foregroundStyle(Estilo.suave)
        }
    }

    private func leyenda(_ n: Noche) -> some View {
        Flujo(espacio: 12) {
            ForEach(n.cama == .juntos ? [Persona.aitana, .yago, .ambos] : n.cama.personas) { p in
                HStack(spacing: 5) {
                    Circle().fill(p.color).frame(width: 8, height: 8)
                    Text(p == .ambos ? "Los dos / no sé" : p.nombre).font(.caption2).foregroundStyle(Estilo.suave)
                }
            }
            HStack(spacing: 5) {
                Circle().fill(Color.white.opacity(0.18)).frame(width: 8, height: 8)
                Text("Silencio").font(.caption2).foregroundStyle(Estilo.suave)
            }
        }
    }

    private func valoracion(_ n: Noche) -> some View {
        Tarjeta(titulo: "¿Qué tal habéis dormido?") {
            ForEach(n.cama.personas) { p in
                HStack {
                    Text(p.nombre).font(.subheadline).foregroundStyle(p.color)
                    Spacer()
                    Estrellas(valor: n.valoracion[p.rawValue] ?? 0) { v in
                        almacen.editar(id) { $0.valoracion[p.rawValue] = v }
                    }
                }
            }
        }
    }

    private func eventosFiltrados(_ n: Noche) -> [Evento] {
        let e = n.eventos.sorted { $0.inicio < $1.inicio }
        switch filtro {
        case .todos: return e
        case .ronquidos: return e.filter { $0.tipo == .ronquido }
        case .habla: return e.filter { $0.tipo == .habla }
        case .dudas: return e.filter { $0.quienConfirmado == nil && $0.tipo != .ruido }
        case .favoritos: return e.filter(\.favorito)
        }
    }

    private func clips(_ n: Noche) -> some View {
        Tarjeta(titulo: "Sonidos (\(n.eventos.count))") {
            Picker("Filtro", selection: $filtro) {
                ForEach(Filtro.allCases.filter { n.cama == .juntos || $0 != .dudas }) { f in Text(f.rawValue).tag(f) }
            }
            .pickerStyle(.segmented)

            let lista = eventosFiltrados(n)
            if lista.isEmpty {
                Text(n.eventos.isEmpty ? "Ni un ruido. Noche de película." : "Nada por aquí.")
                    .font(.footnote).foregroundStyle(Estilo.suave)
                    .padding(.vertical, 8)
            }
            LazyVStack(spacing: 10) {
                ForEach(lista) { e in
                    FilaEvento(noche: n, evento: e)
                }
            }
        }
    }

    private func notaYFactores(_ n: Noche) -> some View {
        Tarjeta(titulo: "Factores y nota") {
            ForEach(n.cama.personas) { p in
                VStack(alignment: .leading, spacing: 6) {
                    if n.cama == .juntos { Text(p.nombre).font(.caption.weight(.semibold)).foregroundStyle(p.color) }
                    Flujo(espacio: 6) {
                        ForEach(Factor.allCases) { f in
                            let activo = n.factores(de: p).contains(f)
                            Chip(texto: f.nombre, icono: f.icono, color: p.color, activo: activo) {
                                almacen.editar(id) { noche in
                                    var lista = noche.factores[p.rawValue] ?? []
                                    if activo { lista.removeAll { $0 == f } } else { lista.append(f) }
                                    noche.factores[p.rawValue] = lista
                                }
                            }
                        }
                    }
                }
            }
            TextField("Una nota (soñé con…)", text: Binding(
                get: { almacen.noche(id)?.nota ?? "" },
                set: { v in almacen.editar(id) { $0.nota = v } }
            ), axis: .vertical)
            .textFieldStyle(.roundedBorder)
        }
    }
}

/// Un clip: escucharlo, decir de quién es, guardarlo en favoritos, compartirlo.
struct FilaEvento: View {
    let noche: Noche
    let evento: Evento

    @Environment(Almacen.self) private var almacen
    @Environment(Reproductor.self) private var reproductor

    private var sonando: Bool { reproductor.sonando == evento.id }
    private var errorAqui: String? { reproductor.errorDe == evento.id ? reproductor.error : nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Button { reproductor.alternar(evento) } label: {
                    ZStack {
                        Circle().fill(Estilo.acento.opacity(0.2))
                        if sonando {
                            Circle().trim(from: 0, to: reproductor.progreso).stroke(Estilo.acento, lineWidth: 3).rotationEffect(.degrees(-90))
                        }
                        Image(systemName: evento.archivo == nil ? "speaker.slash" : (sonando ? "stop.fill" : "play.fill"))
                            .foregroundStyle(Estilo.acento)
                    }
                    .frame(width: 42, height: 42)
                }
                .buttonStyle(.plain)
                .disabled(evento.archivo == nil)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Image(systemName: evento.tipo.icono).font(.caption)
                        Text(evento.tipo.nombre).font(.subheadline.weight(.medium))
                    }
                    Text("\(Estilo.hora(evento.inicio)) · \(Int(evento.duracion.rounded())) s")
                        .font(.caption).foregroundStyle(Estilo.suave)
                }
                Spacer()
                Button { almacen.alternarFavorito(noche: noche.id, evento: evento.id) } label: {
                    Image(systemName: evento.favorito ? "star.fill" : "star")
                        .foregroundStyle(evento.favorito ? Estilo.luna : Estilo.suave)
                }
                .buttonStyle(.plain)
                if let url = Almacen.url(evento.archivo) {
                    ShareLink(item: url) { Image(systemName: "square.and.arrow.up").foregroundStyle(Estilo.suave) }
                }
            }
            if noche.cama == .juntos {
                quienEra
            }
            if let e = errorAqui {
                Label(e, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
            }
        }
        .padding(12)
        .background(Color.white.opacity(sonando ? 0.09 : 0.04), in: RoundedRectangle(cornerRadius: 14))
        .contextMenu {
            Button("Borrar este sonido", systemImage: "trash", role: .destructive) {
                if sonando { reproductor.parar() }
                almacen.borrarEvento(noche: noche.id, evento: evento.id)
            }
        }
    }

    private var quienEra: some View {
        Flujo(espacio: 6) {
            if evento.quienConfirmado == nil {
                Text(evento.quienAdivinado.map { "¿\($0.nombre)?" } ?? "¿Quién?")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(evento.quienAdivinado?.color ?? Estilo.suave)
                    .padding(.vertical, 7)
            }
            ForEach(Persona.allCases) { p in
                Chip(texto: p.nombre, color: p.color, activo: evento.quienConfirmado == p) {
                    almacen.confirmar(noche: noche.id, evento: evento.id, quien: p)
                }
                .font(.caption)
            }
        }
    }
}
