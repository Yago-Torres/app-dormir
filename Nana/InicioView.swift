import SwiftUI

struct InicioView: View {
    var abrir: (UUID) -> Void

    @Environment(Almacen.self) private var almacen
    @Environment(Grabadora.self) private var grabadora
    @Environment(Ajustes.self) private var ajustes
    @State private var cama: Cama = Ajustes.compartidos.ultimaCama
    @State private var factores: [String: Set<Factor>] = [:]
    @State private var empezando = false

    private var saludo: String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 6..<13: return "Buenos días"
        case 13..<20: return "Buenas tardes"
        default: return "Buenas noches"
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    cabecera
                    quienDuerme
                    factoresHoy
                    botonEmpezar
                    if let e = grabadora.error {
                        Label(e, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(.orange)
                    }
                    if let e = almacen.error {
                        Label(e, systemImage: "externaldrive.badge.exclamationmark").font(.footnote).foregroundStyle(.orange)
                    }
                    consejo
                    if let ultima = almacen.nochesOrdenadas.first(where: { $0.fin != nil }) {
                        Button { abrir(ultima.id) } label: { ResumenNoche(noche: ultima) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(20)
            }
            .background(Estilo.fondo)
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var cabecera: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(saludo).font(.subheadline).foregroundStyle(Estilo.suave)
                Text("Nana").font(.system(size: 40, weight: .bold, design: .rounded))
            }
            Spacer()
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 38))
                .foregroundStyle(Estilo.luna, Estilo.acento)
                .shadow(color: Estilo.acento.opacity(0.6), radius: 18)
        }
        .padding(.top, 8)
    }

    private var quienDuerme: some View {
        Tarjeta(titulo: "¿Quién duerme hoy?") {
            HStack(spacing: 10) {
                ForEach(Cama.allCases) { c in
                    Button { withAnimation(.snappy) { cama = c } } label: {
                        VStack(spacing: 8) {
                            HStack(spacing: -8) {
                                ForEach(c.personas) { p in
                                    Circle().fill(p.color.gradient).frame(width: 34, height: 34)
                                        .overlay(Text(String(p.nombre.prefix(1))).font(.headline).foregroundStyle(.black.opacity(0.7)))
                                        .overlay(Circle().stroke(Estilo.fondoArriba, lineWidth: 2))
                                }
                            }
                            Text(c.nombre).font(.footnote.weight(.medium)).lineLimit(1).minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(cama == c ? Estilo.acento.opacity(0.22) : Color.clear, in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(cama == c ? Estilo.acento : Estilo.borde))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var factoresHoy: some View {
        Tarjeta(titulo: "Hoy hay…") {
            ForEach(cama.personas) { p in
                VStack(alignment: .leading, spacing: 8) {
                    if cama == .juntos {
                        Text(p.nombre).font(.subheadline.weight(.semibold)).foregroundStyle(p.color)
                    }
                    Flujo {
                        ForEach(Factor.allCases) { f in
                            let activo = factores[p.rawValue]?.contains(f) == true
                            Chip(texto: f.nombre, icono: f.icono, color: p.color, activo: activo) {
                                if activo { factores[p.rawValue]?.remove(f) } else { factores[p.rawValue, default: []].insert(f) }
                            }
                        }
                    }
                }
            }
            Text("Opcional. Sirve para ver en Tendencias qué os hace roncar más.")
                .font(.caption).foregroundStyle(Estilo.suave)
        }
    }

    private var botonEmpezar: some View {
        Button {
            empezando = true
            var f: [String: [Factor]] = [:]
            for p in cama.personas { f[p.rawValue] = Array(factores[p.rawValue] ?? []) }
            Task {
                await grabadora.empezar(cama: cama, factores: f, almacen: almacen)
                empezando = false
                if grabadora.grabando { factores = [:] }
            }
        } label: {
            HStack {
                if empezando { ProgressView().tint(.black) } else { Image(systemName: "moon.zzz.fill") }
                Text("Empezar la noche").fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(LinearGradient(colors: [Estilo.luna, Estilo.acento], startPoint: .leading, endPoint: .trailing),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .foregroundStyle(.black.opacity(0.8))
        }
        .disabled(empezando)
    }

    private var consejo: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lightbulb.fill").foregroundStyle(Estilo.luna)
            Text(textoConsejo).font(.footnote).foregroundStyle(Estilo.suave)
        }
    }

    private var textoConsejo: String {
        if cama == .juntos {
            switch ajustes.posicion {
            case .medio:
                return ajustes.balanceAitana == nil
                    ? "Deja el móvil en medio, en el cabecero y enchufado. Calibra los lados en Ajustes para que Nana sepa quién ronca."
                    : "Deja el móvil en medio, en el cabecero, en la misma postura que al calibrar, y enchufado."
            default:
                return "Con el móvil en una mesilla Nana adivina por cómo suena cada una. Confirma algunos sonidos por la mañana y aprenderá."
            }
        }
        return "Deja el móvil en la mesilla, cerca de la cabeza y enchufado. Puedes bloquear la pantalla: Nana sigue escuchando."
    }
}

/// Tarjeta con lo esencial de una noche.
struct ResumenNoche: View {
    let noche: Noche

    var body: some View {
        Tarjeta(titulo: "Última noche") {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(noche.titulo).font(.headline)
                    Text("\(Estilo.hora(noche.inicio)) – \(Estilo.hora(noche.fin ?? Date())) · \(noche.duracion.textoHoras)")
                        .font(.subheadline).foregroundStyle(Estilo.suave)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(Estilo.suave)
            }
            HStack(spacing: 16) {
                ForEach(noche.cama.personas) { p in
                    HStack(spacing: 10) {
                        Anillo(valor: noche.puntuacion(p), color: p.color, tam: 48)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.nombre).font(.subheadline.weight(.semibold))
                            Text("\(noche.minutosRoncando(p)) min roncando").font(.caption).foregroundStyle(Estilo.suave)
                            let frases = noche.eventos(de: p).filter { $0.tipo == .habla }.count
                            if frases > 0 {
                                Text("\(frases) \(frases == 1 ? "frase" : "frases") en sueños").font(.caption).foregroundStyle(Estilo.suave)
                            }
                        }
                    }
                }
            }
        }
    }
}
