import SwiftUI

struct AjustesView: View {
    @Environment(Almacen.self) private var almacen
    @Environment(Ajustes.self) private var ajustes
    @State private var calibrando: Persona?
    @State private var cuenta = 0
    @State private var mensajeCalibrado: String?
    @State private var confirmarOlvido = false
    @State private var calibrador: Calibrador?

    var body: some View {
        @Bindable var aj = ajustes
        NavigationStack {
            Form {
                Section("Quiénes sois") {
                    TextField("Ella", text: $aj.nombreAitana)
                    TextField("Él", text: $aj.nombreYago)
                }

                Section {
                    Picker("Dónde dejáis el móvil", selection: $aj.posicion) {
                        ForEach(PosicionMovil.allCases) { Text($0.nombre).tag($0) }
                    }
                    if ajustes.posicion == .medio {
                        ForEach(Persona.durmientes) { p in
                            Button { calibrar(p) } label: {
                                HStack {
                                    Text(calibrando == p ? "Habla ahora… \(cuenta)" : "Calibrar el lado de \(p.nombre)")
                                    Spacer()
                                    Text(textoLado(p == .aitana ? ajustes.balanceAitana : ajustes.balanceYago))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .disabled(calibrando != nil)
                        }
                        if let mensajeCalibrado {
                            Text(mensajeCalibrado).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Cuando dormís los dos")
                } footer: {
                    Text(ajustes.posicion == .medio
                         ? "Pon el móvil en el cabecero, en medio, como lo dejaréis por la noche. Cada una se tumba en su almohada, pulsa su botón y habla 5 segundos. Nana mide de qué lado llega el sonido (el micro del iPhone 15 graba en estéreo). Por la noche, déjalo en la misma postura."
                         : "Con el móvil en una mesilla no se puede saber el lado. Nana adivina por cómo suena cada una: confirma de quién es cada sonido por la mañana y irá acertando más.")
                }

                Section {
                    VStack(alignment: .leading) {
                        Slider(value: Binding(get: { 1 - aj.sensibilidad }, set: { aj.sensibilidad = 1 - $0 }), in: 0.2...0.7)
                        HStack {
                            Text("Menos clips").font(.caption)
                            Spacer()
                            Text("Más sensible").font(.caption)
                        }
                        .foregroundStyle(.secondary)
                    }
                    ForEach(TipoSonido.allCases) { t in
                        Toggle(isOn: Binding(
                            get: { aj.tiposGuardados.contains(t) },
                            set: { if $0 { aj.tiposGuardados.insert(t) } else { aj.tiposGuardados.remove(t) } }
                        )) { Label(t.plural, systemImage: t.icono) }
                    }
                    Stepper("Un clip de ronquido cada \(Int(aj.pausaRonquidos)) min", value: $aj.pausaRonquidos, in: 1...30)
                    Stepper("Empezar a guardar a los \(Int(aj.retrasoInicio)) min", value: $aj.retrasoInicio, in: 0...60, step: 5)
                    Stepper("Máximo \(aj.maxClips) clips por noche", value: $aj.maxClips, in: 50...500, step: 50)
                } header: {
                    Text("Qué guardar")
                } footer: {
                    Text("Los minutos roncando se cuentan siempre; la pausa solo evita cientos de clips iguales. El reconocimiento de sonidos es el de Apple y funciona sin internet.")
                }

                Section {
                    Picker("Borrar clips pasados", selection: $aj.borrarTrasDias) {
                        Text("7 días").tag(7)
                        Text("30 días").tag(30)
                        Text("90 días").tag(90)
                        Text("Nunca").tag(0)
                    }
                    LabeledContent("Ocupan", value: ByteCountFormatter.string(fromByteCount: almacen.espacioClips, countStyle: .file))
                    LabeledContent("Noches", value: "\(almacen.noches.count)")
                    Button("Olvidar cómo suena cada una", role: .destructive) { confirmarOlvido = true }
                } header: {
                    Text("Espacio y memoria")
                } footer: {
                    Text("Los favoritos no se borran nunca. Los clips también están en la app Archivos > En mi iPhone > Nana.")
                }

                Section {
                    Text("Todo se queda en este iPhone: no hay cuentas, ni nube, ni internet. Para que funcione toda la noche, deja la app abierta (puedes bloquear la pantalla) y el móvil enchufado.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Estilo.fondo)
            .navigationTitle("Ajustes")
            .confirmationDialog("Nana volverá a no saber quién es quién por cómo suena.", isPresented: $confirmarOlvido, titleVisibility: .visible) {
                Button("Olvidar", role: .destructive) { almacen.olvidarPerfiles() }
            }
            .onChange(of: ajustes.borrarTrasDias) { almacen.limpiarClipsViejos() }
        }
    }

    private func textoLado(_ b: Double?) -> String {
        guard let b else { return "sin calibrar" }
        if abs(b) < 0.05 { return "centro" }
        return b < 0 ? "izquierda" : "derecha"
    }

    private func calibrar(_ p: Persona) {
        calibrando = p
        cuenta = 5
        mensajeCalibrado = nil
        let c = Calibrador()
        calibrador = c
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { t in
            cuenta -= 1
            if cuenta <= 0 { t.invalidate() }
        }
        c.grabar(segundos: 5) { huella, estereo in
            calibrando = nil
            calibrador = nil
            guard let huella else {
                mensajeCalibrado = "No he oído nada. Prueba otra vez hablando normal."
                return
            }
            if p == .aitana { ajustes.balanceAitana = huella.balance } else { ajustes.balanceYago = huella.balance }
            // también vale para aprender cómo habla cada una
            almacen.perfiles["\(p.rawValue)-habla", default: Perfil()].aprender(huella)
            almacen.reatribuirTodo()
            if !estereo || huella.balance == nil {
                mensajeCalibrado = "Este iPhone no me ha dado sonido en estéreo: adivinaré solo por la voz."
            } else if let a = ajustes.balanceAitana, let y = ajustes.balanceYago, abs(a - y) < 0.08 {
                mensajeCalibrado = "Los dos lados suenan casi igual. Gira el móvil 90° (que el lado largo mire a las almohadas) y calibra otra vez."
            } else {
                mensajeCalibrado = "Listo, \(p.nombre)."
            }
        }
    }
}
