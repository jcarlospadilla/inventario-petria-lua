## 2026.05.30-updater3

### Corregido

- `equpdate` ahora descarga e instala la actualización cuando hay una versión nueva.
- `eqcheckupdate` queda como comando solo de verificación.
- Se evita procesar dos veces el mismo evento de descarga.
- El XML descargado ahora se guarda como `PetriaEQSearch.xml`, evitando crear un módulo extra `PetriaEQSearch_update`.

### Agregado

- `eqautoupdate off|check|on`.
- `check`: revisa al iniciar y solo avisa.
- `on`: revisa al iniciar e instala automáticamente si hay nueva versión.
