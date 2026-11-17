import SwiftUI
import UIKit

/// Pantalla negra mientras dormís. Se puede bloquear el móvil: la grabación sigue.
struct NocheEnCursoView: View {
    var terminada: (UUID) -> Void

    @Environment(Grabadora.self) private var grabadora
    @Environment(Ajustes.self) private var ajustes
    @State private var apretando = false
    @State private var acabando = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let n = grabadora.noche {
                contenido(n)
            }
        }
        .preferredColorScheme(.dark)
    }

    private func contenido(_ n: Noche) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            VStack(spacing: 28) {
                Spacer()
                VStack(spacing: 6) {
                    Text(Estilo.hora(ctx.date))
                        .font(.system(size: 76, weight: .thin, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Estilo.luna.opacity(0.85))
                    Text("\(n.cama.nombre) · desde las \(Estilo.hora(n.inicio)) · \(ctx.date.timeIntervalSince(n.inicio).textoHoras)")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.45))
                }

                Onda(valores: grabadora.onda, color: Estilo.acento)
                    .frame(height: 70)
                    .padding(.horizontal, 30)
                    .opacity(0.8)

                estado(n, ahora: ctx.date)

                HStack(spacing: 26) {
                    contador(TipoSonido.ronquido.icono, "\(n.minutosRoncandoTotal()) min", "roncando")
                    contador(TipoSonido.habla.icono, "\(n.eventos.filter { $0.tipo == .habla }.count)", "frases")
                    contador("waveform", "\(n.eventos.count)", "clips")
                }

                Spacer()

                botonTerminar

                Text(grabadora.estereo ? "Micro en estéreo · puedes bloquear la pantalla" : "Puedes bloquear la pantalla")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.3))
                    .padding(.bottom, 8)
            }
            .padding()
        }
    }

    @ViewBuilder
    private func estado(_ n: Noche, ahora: Date) -> some View {
        let falta = ajustes.retrasoInicio * 60 - ahora.timeIntervalSince(n.inicio)
        Group {
            if falta > 0 {
                Text("Empiezo a guardar sonidos en \(Int(falta / 60) + 1) min. Que durmáis bien.")
            } else if let t = grabadora.ultimoTipo, let m = grabadora.ultimoMomento, ahora.timeIntervalSince(m) < 600 {
                Label("\(t.nombre) hace \(max(0, Int(ahora.timeIntervalSince(m) / 60))) min", systemImage: t.icono)
            } else {
                Label("Escuchando", systemImage: "ear")
            }
        }
        .font(.subheadline)
        .foregroundStyle(.white.opacity(0.55))
        .multilineTextAlignment(.center)
    }

    private func contador(_ icono: String, _ valor: String, _ texto: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icono).foregroundStyle(Estilo.acento.opacity(0.8))
            Text(valor).font(.headline).monospacedDigit().foregroundStyle(.white.opacity(0.8))
            Text(texto).font(.caption2).foregroundStyle(.white.opacity(0.4))
        }
    }

    /// Hay que mantenerlo pulsado: así no se para la noche con un manotazo dormida.
    private var botonTerminar: some View {
        Text(acabando ? "Guardando…" : (apretando ? "Suelta para seguir durmiendo" : "Mantén pulsado para despertar"))
            .font(.headline)
            .foregroundStyle(.black.opacity(0.8))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Estilo.luna.opacity(0.35)
                        Estilo.luna.frame(width: apretando ? g.size.width : 0)
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.horizontal, 24)
            .onLongPressGesture(minimumDuration: 1.2, maximumDistance: 40) {
                acabar()
            } onPressingChanged: { p in
                withAnimation(p ? .linear(duration: 1.2) : .easeOut(duration: 0.2)) { apretando = p }
            }
            .disabled(acabando)
    }

    private func acabar() {
        acabando = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        grabadora.terminar { id in
            acabando = false
            guard let id else { return }
            // espera a que se cierre esta pantalla antes de abrir el resumen
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { terminada(id) }
        }
    }
}
