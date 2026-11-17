import SwiftUI

@main
struct NanaApp: App {
    @State private var almacen = Almacen()
    @State private var grabadora = Grabadora()
    @State private var reproductor = Reproductor()

    var body: some Scene {
        WindowGroup {
            Raiz()
                .environment(almacen)
                .environment(grabadora)
                .environment(reproductor)
                .environment(Ajustes.compartidos)
                .preferredColorScheme(.dark)
                .tint(Estilo.acento)
        }
    }
}

struct Raiz: View {
    @Environment(Grabadora.self) private var grabadora
    @State private var abierta: UUID?

    var body: some View {
        TabView {
            InicioView(abrir: { abierta = $0 })
                .tabItem { Label("Esta noche", systemImage: "moon.stars.fill") }
            HistorialView()
                .tabItem { Label("Noches", systemImage: "calendar") }
            TendenciasView()
                .tabItem { Label("Tendencias", systemImage: "chart.xyaxis.line") }
            AjustesView()
                .tabItem { Label("Ajustes", systemImage: "slider.horizontal.3") }
        }
        .fullScreenCover(isPresented: .constant(grabadora.grabando)) {
            NocheEnCursoView(terminada: { id in abierta = id })
        }
        .sheet(item: $abierta) { id in
            NavigationStack {
                NocheDetalleView(id: id, recienAcabada: true)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Listo") { abierta = nil }
                        }
                    }
            }
        }
    }
}
