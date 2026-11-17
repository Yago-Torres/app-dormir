# Nana (app-dormir-Aitana): mapa para agentes

App de iPhone para detectar ronquidos y frases en sueños, para Aitana y Yago (a veces duermen juntos). Qué hace y qué
fichero hace qué: `README.md`. Este repo **es** el que se publica: `Yago-Torres/app-dormir` (público, para
que los Mac de Actions salgan gratis). Aquí solo hay código, nunca datos.

- No hay compilador de Swift ni en la Pi ni en el PC. Push a `main` → Actions compila → release `ios` (`Nana.ipa`).
  Si falla: `curl -sL https://github.com/Yago-Torres/app-dormir/releases/download/ios-log/errores.txt`.
  Estado sin token: `curl -s https://api.github.com/repos/Yago-Torres/app-dormir/actions/runs?per_page=1`.
- `git push` funciona con la clave `~/.ssh/github_publicar` (ya está en `core.sshCommand`). Pregunta antes de hacer push.
- Swift 5 (no 6), iOS 17. Sin dependencias: AVFoundation, SoundAnalysis, Accelerate, Charts, SwiftUI.
- Las etiquetas del clasificador de Apple que se usan están en `TipoSonido.desde(etiqueta:)` (`Modelos.swift`).
- Bundle `dev.yagotg.nana`. Si lo cambias, SideStore gasta otro App ID y se pierden los datos del iPhone.
