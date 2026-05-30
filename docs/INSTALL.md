# Primera instalación en Mudlet

El repositorio incluye un bootstrap Lua para instalar por primera vez el módulo principal y el updater.

## Opción recomendada

1. Abrir el archivo raw:

```text
https://raw.githubusercontent.com/jcarlospadilla/inventario-petria-lua/main/install.lua
```

2. Copiar el contenido completo.
3. En Mudlet, pegarlo en un script temporal o ejecutarlo desde el editor Lua.
4. Ejecutar:

```text
eqinstall
```

El instalador descargará e instalará:

```text
dist/PetriaEQSearch.xml
dist/PetriaEQSearchUpdater.xml
```

Al terminar mostrará:

```text
Instalacion completada.
Comandos disponibles: eqsync | eqsearch help | eqversion | eqcheckupdate | equpdate
Siguiente paso recomendado: eqsync
```

## Reinstalación forzada

```text
eqinstall force
```

## Después de instalar

Actualizar inventario local:

```text
eqsync
```

Ver ayuda:

```text
eqsearch help
```

Revisar versión:

```text
eqversion
```

Revisar updates:

```text
eqcheckupdate
```

Actualizar desde GitHub:

```text
equpdate
```
