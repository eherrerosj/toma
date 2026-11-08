# Changelog

Todos los cambios relevantes se documentan aquí. El formato sigue
[Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/) y el proyecto usa
[Versionado Semántico](https://semver.org/lang/es/).

## [Unreleased]

## [1.4.1] - 2026-11-08

### Changed

- Local builds can pin an explicit Apple signing identity and team in repository-local Git settings.
- Configured builds fail before compilation if the signer is missing, ambiguous or from the wrong team. They cannot silently fall back to ad hoc signing.
- Bundle checks validate the Apple signing class, team and app identifier. Releases continue to require Developer ID signing and notarization.

### Added

- Signing configuration and build-preflight regression tests.

## [1.4.0] - 2026-11-08

### Added

- Reopen Last Recording retains one local original for another export.
- Thumbnail Auto-Save offers 6 seconds, 15 seconds, or Never.
- Start and end trimming applies to Save, Copy and drag in MP4, HEVC and GIF.
- Record Window uses the macOS single-window picker.
- An optional three-second countdown supports Cancel and Escape before capture starts.

## [1.3.2] - 2026-11-07

### Fixed

- Selecting MP4, HEVC or GIF keeps the result thumbnail open. Copy, Save and drag delivery use the selected format.
- A separate Save button replaces saving immediately when a format is selected. Untouched thumbnails still auto-save after six seconds.

## [1.3.1] - 2026-11-07

### Changed

- This personal fork uses its own application identity, storage and GitHub release feed.
- Failed exports keep the original for recovery across restarts. Drag delivery has exclusive ownership.
- Clipboard files expire during use and at launch. The privacy text explains network access and retained originals.
- Capture has storage and duration limits. Exports support cancellation and bound GIF concurrency.
- Updates require the expected Developer ID application, SHA-256 digest and exact advertised version.
- Builds discover the SwiftPM output path. Releases use an explicit signer and the built commit.

### Fixed

- MP4 and HEVC use supported bitrate settings. Intel H.264 export no longer throws an Objective-C exception for the JPEG quality setting.
- Long GIF holds preserve their duration. Decoder failures cannot silently produce a frozen GIF and delete the original.
- A second process cannot purge another process's active workspace at launch.

### Added

- Swift regression and real media export tests, release-script tests and macOS CI on Apple silicon and Intel.

## [1.3.0] - 2026-11-05

### Añadido

- **Interfaz en inglés**. Toma sigue el idioma del sistema: español si lo prefieres, inglés en
  cualquier otro caso. Los textos viven en `Resources/<idioma>.lproj/Localizable.strings`.
- **Actualizaciones desde la app**. Toma busca la última versión en GitHub una vez al día. Si hay
  una nueva, el menú muestra «Actualizar a Toma x.y.z…»: descarga el DMG, comprueba su SHA-256 y la
  firma (mismo Developer ID que la app en uso), reemplaza la app y se reabre. También hay
  «Buscar actualizaciones…».

### Cambiado

- Los archivos nuevos se llaman «Screen Recording 2026-10-15 at 21.03.12» en inglés; en español
  se mantiene «Grabación de pantalla 2026-10-15 a las 21.03.12».

## [1.2.0] - 2026-10-15

### Añadido

- Instalador **Toma.dmg**: arrastra Toma a Aplicaciones.
- Icono propio de la app y del disco.
- Binario universal: Apple silicon e Intel.
- Web en [toma.felipebasurto.com](https://toma.felipebasurto.com).
- `./build.sh dmg` genera el disco. La versión vive en el archivo `VERSION`.

## [1.1.0] - 2026-10-15

### Añadido

- **Guardar en**: elige la carpeta desde el menú. Por defecto, la de las capturas de pantalla.
- **HEVC**: tercer formato, la mitad de peso que MP4.
- **Copiar**: el botón de la miniatura deja el archivo en el portapapeles.
- **Tamaño del GIF**: nítido (resolución completa, 20 fps) o ligero (640 px, 15 fps).
- **Sonido**: sin sonido, el del Mac, o el del Mac y el micrófono. Todas las pistas se
  mezclan en una sola, porque muchos reproductores solo leen la primera.
- La miniatura muestra la duración del clip y una descripción de cada formato.
- Anillo de progreso en la barra de menús mientras se guarda, y ✓ al copiar.

### Cambiado

- MP4 y HEVC se recodifican según la calidad deseada: de 5 a 10 veces más ligeros con el
  texto igual de nítido.
- El formato que sueles elegir se codifica mientras miras la miniatura, así que guardarlo
  es inmediato.
- Codificador de GIF propio. Guarda solo lo que cambia, mantiene exactos los colores de la
  interfaz, difumina los degradados sin bandas y es el doble de rápido que ImageIO.
- La grabación ya no consume CPU extra: 0,13 s de CPU para 4 s a 60 fps.

### Corregido

- La miniatura no llegaba a aparecer: se quedaba fuera de la pantalla.
- Las ventanas de Toma ya se ven en capturas y en videollamadas. Siguen sin aparecer en sus
  propias grabaciones.
- Si una exportación falla, la grabación se guarda en MP4 en lugar de perderse.

## [1.0.0] - 2026-10-15

### Añadido

- Primera versión. <kbd>⌥⇧⌘4</kbd>, arrastra una zona y graba. Los modificadores son los de ⇧⌘4.
- Miniatura tras grabar con MP4 o GIF y arrastrar para compartir.
- Grabación a resolución nativa (Retina) con ScreenCaptureKit, sin que Toma salga en el vídeo.

[Unreleased]: https://github.com/felipebasurto/toma/compare/v1.2.0...HEAD
[1.2.0]: https://github.com/felipebasurto/toma/compare/v1.1...v1.2.0
[1.1.0]: https://github.com/felipebasurto/toma/releases/tag/v1.1
[1.0.0]: https://github.com/felipebasurto/toma/commits/main
