# Nana: ronquidos y frases en sueños, para iPhone

App de iPhone (SwiftUI, iOS 17+, pensada para el iPhone 15) que escucha mientras dormís. Hace lo mismo que SnoreLab o Sleep Talk Recorder, pero para **dos personas en la misma cama**:

- Guarda clips de **ronquidos**, de lo que se **dice en sueños**, de la **tos** y de las **risas** (y de otros ruidos, si lo activas). Para reconocerlos usa el clasificador de sonidos de Apple, que viene dentro de iOS: funciona sin internet y sin librerías externas.
- Cuenta los **minutos roncando** de cada persona y da una **puntuación** del 0 al 100 por noche.
- **¿Quién era?** Al empezar la noche eliges si duerme Aitana sola, Yago solo o los dos. Si dormís juntos, Nana adivina de quién es cada sonido con dos pistas:
  1. **El lado.** El micro del iPhone 15 graba en estéreo. Con el móvil en el cabecero, en medio, Nana compara de qué lado llega el sonido con lo que midió al calibrar (Ajustes → cada una habla 5 s desde su almohada).
  2. **Cómo suena cada una.** Por la mañana confirmas de quién era cada clip (Aitana / Yago / Los dos / Ninguno). Nana aprende el tono y el timbre de cada una y acierta cada vez más.
  Si las pistas no le bastan, pone «¿Quién?» en vez de inventarse la respuesta.
- Una **gráfica** de la noche (ruido por minuto, coloreado según quién ronca) y las frases marcadas encima.
- **Favoritos** (las frases graciosas no se borran nunca) y **compartir** cualquier clip.
- **Factores** de cada persona (alcohol, congestión, cena tarde, tiras nasales…) y en **Tendencias** cuánto empeora o mejora cada uno la puntuación. También la valoración ★ de cada mañana.
- Todo se queda en el iPhone: sin cuentas, sin nube y sin servidor. Los clips también se ven en Archivos → En mi iPhone → Nana.

## Instalar (SideStore)

Igual que Tom (la guía completa de SideStore está en el README de `Yago-Torres/todo`, carpeta `ios/`):

1. En el iPhone, abre en Safari `https://github.com/Yago-Torres/app-dormir/releases/download/ios/Nana.ipa`.
2. SideStore → Mis apps → **+** → elige `Nana.ipa`.
3. La primera vez que pulses «Empezar la noche», acepta el permiso del micrófono.

Con la cuenta gratis de Apple caben **3 apps activas contando SideStore**, y Nana gasta 1 App ID (`dev.yagotg.nana`).

## Cómo usarla

1. Por la noche: elige quién duerme, marca los factores si quieres y pulsa **Empezar la noche**. Deja el móvil enchufado. Puedes bloquear la pantalla, pero **no cierres la app** desde el multitarea: si la cierras, deja de escuchar.
2. Durante los primeros 10 minutos no guarda nada, para no grabaros mientras os dormís. Se cambia en Ajustes.
3. Por la mañana: **mantén pulsado** «despertar» (así no se para la noche con un manotazo). Sale el resumen. Escucha los clips y, si dormíais juntos, di de quién era cada uno.
4. Si os gusta escuchar música o ruido blanco, puede sonar a la vez desde otra app. Ojo: el micro también lo oye.

## Por dentro

| Fichero | Qué hace |
|---|---|
| `Nana/Motor.swift` | AVAudioEngine con el audio en segundo plano. Clasifica con `SNClassifySoundRequest(.version1)`, guarda clips AAC con 3 s de antes, resume cada minuto y calcula la huella (balance estéreo, tono y brillo). También el calibrador. |
| `Nana/ProbarMicro.swift` | «Probar el micro» (en Ajustes): lo que oye ahora el clasificador y su confianza de ronquido frente al umbral, para comprobar sin esperar una noche que Nana os oye desde donde está el móvil. |
| `Nana/Atribucion.swift` | Adivina quién era: el lado, los perfiles aprendidos o «no lo sé». |
| `Nana/Almacen.swift` | `Documentos/nana.json` (noches y perfiles) y `Documentos/Clips/*.m4a`. Borra los clips viejos que no son favoritos. |
| `Nana/Grabadora.swift` | Une el motor con la interfaz. Guarda la noche cada 5 minutos, así que si iOS cierra la app no se pierde. También el reproductor. |
| `Nana/*View.swift` | Esta noche, la noche en curso, el detalle, Noches, Tendencias y Ajustes. |

No hay Mac: el proyecto de Xcode lo genera XcodeGen (`project.yml`) en GitHub Actions (`.github/workflows/ios.yml`). Cada push a `main` publica `Nana.ipa` en la release `ios`. Si falla, el registro queda en la release `ios-log` (`errores.txt`).
