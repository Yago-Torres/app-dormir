import SwiftUI

struct HistorialView: View {
    @Environment(Almacen.self) private var almacen
    @State private var modo = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    Picker("Ver", selection: $modo) {
                        Text("Noches").tag(0)
                        Text("Favoritos").tag(1)
                    }
                    .pickerStyle(.segmented)

                    if modo == 0 { noches } else { favoritos }
                }
                .padding(16)
            }
            .background(Estilo.fondo)
            .navigationTitle("Noches")
            .navigationDestination(for: UUID.self) { NocheDetalleView(id: $0) }
        }
    }

    @ViewBuilder
    private var noches: some View {
        let lista = almacen.nochesOrdenadas.filter { $0.fin != nil }
        if lista.isEmpty {
            ContentUnavailableView("Aún no hay noches", systemImage: "moon.zzz", description: Text("Empieza una desde «Esta noche»."))
        }
        ForEach(lista) { n in
            NavigationLink(value: n.id) { FilaNoche(noche: n) }
                .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var favoritos: some View {
        let todos = almacen.nochesOrdenadas.flatMap { n in n.eventos.filter(\.favorito).map { Favorito(noche: n, evento: $0) } }
        if todos.isEmpty {
            ContentUnavailableView("Sin favoritos", systemImage: "star", description: Text("Marca con ★ las frases más graciosas para guardarlas siempre."))
        }
        ForEach(todos) { par in
            VStack(alignment: .leading, spacing: 4) {
                Text(par.noche.titulo).font(.caption).foregroundStyle(Estilo.suave)
                FilaEvento(noche: par.noche, evento: par.evento)
            }
        }
    }
}

private struct Favorito: Identifiable {
    let noche: Noche
    let evento: Evento
    var id: UUID { evento.id }
}

struct FilaNoche: View {
    let noche: Noche

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(noche.titulo).font(.headline)
                Text("\(Estilo.hora(noche.inicio)) – \(Estilo.hora(noche.fin ?? Date())) · \(noche.duracion.textoHoras)")
                    .font(.caption).foregroundStyle(Estilo.suave)
                HStack(spacing: 8) {
                    ForEach(noche.cama.personas) { p in
                        Circle().fill(p.color).frame(width: 8, height: 8)
                    }
                    let frases = noche.eventos.filter { $0.tipo == .habla }.count
                    if frases > 0 {
                        Label("\(frases)", systemImage: "quote.bubble.fill").font(.caption2).foregroundStyle(Estilo.suave)
                    }
                    if noche.eventos.contains(where: \.favorito) {
                        Image(systemName: "star.fill").font(.caption2).foregroundStyle(Estilo.luna)
                    }
                }
            }
            Spacer()
            ForEach(noche.cama.personas) { p in
                Anillo(valor: noche.puntuacion(p), color: p.color, tam: 40)
            }
        }
        .padding(14)
        .background(Estilo.tarjeta, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Estilo.borde))
    }
}
