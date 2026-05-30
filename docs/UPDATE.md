# Auto-update desde GitHub

El proyecto incluye un módulo pequeño de actualización:

```text
dist/PetriaEQSearchUpdater.xml
```

Este updater se instala una vez y permite actualizar el módulo principal `PetriaEQSearch.xml` desde GitHub.

## Instalación del updater

1. Descargar o instalar `dist/PetriaEQSearchUpdater.xml`.
2. En Mudlet, abrir **Module Manager** (`Alt+I`).
3. Instalar `PetriaEQSearchUpdater.xml` como módulo.
4. Usar los comandos:

```text
eqversion
eqcheckupdate
equpdate
equpdate force
```

## Flujo de actualización

```text
eqcheckupdate
```

Consulta:

```text
https://raw.githubusercontent.com/jcarlospadilla/inventario-petria-lua/main/VERSION
```

Luego compara con la versión local.

```text
equpdate
```

Descarga e instala:

```text
https://raw.githubusercontent.com/jcarlospadilla/inventario-petria-lua/main/dist/PetriaEQSearch.xml
```

## Actualizar forzado

```text
equpdate force
```

Reinstala el módulo aunque la versión local y remota sean iguales.

## Archivos involucrados

```text
VERSION                              Versión publicada actual
dist/PetriaEQSearch.xml              Módulo principal instalable
dist/PetriaEQSearchUpdater.xml       Módulo pequeño de actualización
src/PetriaEQSearchUpdater.lua        Fuente Lua del updater
```

## Recomendación de releases

Cada nueva versión debe actualizar:

1. `src/petria_eqsearch_mudlet.lua`
2. `dist/PetriaEQSearch.xml`
3. `VERSION`
4. `CHANGELOG.md`

El updater solo necesita actualizarse cuando cambie el flujo de actualización.
