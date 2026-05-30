# Inventario Petria Lua

Módulo de Mudlet para consultar el inventario público de Petria MUD desde una base local, buscar equipo por nivel/slot/set y generar sugerencias automáticas para slots faltantes.

## Estado actual

Versión base trabajada en ChatGPT: `2026.05.30-rev12-module`.

El módulo permite:

- Descargar e indexar `inventarionew.json`.
- Buscar por nombre o descripción.
- Buscar por nivel o rango de nivel.
- Agrupar resultados por slot/`Vestir`.
- Detectar slots faltantes con `equipo faltante` y `equipo faltante inventario`.
- Usar nivel desde GMCP para recomendaciones automáticas.
- Sugerir 3 items por slot faltante.
- Cambiar modo de recomendación: `subir`, `pk`, `defensa`, `caster`, `healer`, `danio`, `balance`.
- Valorar stats como `Fue`, `Int`, `Sab`, `Des`, `Con`, `HP`, `Mana`, `Hitroll`, `Damroll`, `SpellPower`, `HealPower`, saves, protecciones, resistencias e inmunidades.

## Instalación rápida en Mudlet

1. Descargar el módulo `.xml` desde `dist/PetriaEQSearch.xml`.
2. Abrir Mudlet.
3. Ir a **Module Manager** con `Alt+I`.
4. Instalar el XML como módulo.
5. Ejecutar:

```text
eqsync
```

## Comandos principales

```text
eqsync [url]
eqsearch help
eqsearch 10-14
eqsearch 10-14 escudo
eqsearch set
eqsearch set fuego
eqsearch faltante
eqfaltante
eqmodo subir | pk | defensa | caster | healer | danio | balance
eqpower [nivel]
```

## Formato de Lugar

La columna `Lugar` se muestra como:

```text
{Area_Definicion} => {Instancia_Activa} (Extra_Data)
```

Si `Instancia_Activa` o `Extra_Data` no tienen información real, no se muestran.

## Notas de diseño

- `Tipo = light` se asume como compatible con el slot `usando como luz`, porque los objetos de tipo `light` no siempre traen `Vestir`.
- `emblema` se ignora en búsquedas automáticas de `eqfaltante`.
- La data de `Vestir` puede venir mezclada en inglés y español, por eso se manejan alias como `Shield`, `Rodela`, `Escudo`, `Finger`, `Dedo`, etc.

## Estructura del repositorio

```text
src/petria_eqsearch_mudlet.lua      Fuente Lua del módulo
dist/PetriaEQSearch.xml             Módulo instalable en Mudlet
tools/build_module.py               Genera dist/PetriaEQSearch.xml desde src/
docs/USAGE.md                       Guía de uso
CHANGELOG.md                        Historial de cambios
```

## Próximos pasos

- Crear releases con `.xml` y `.mpackage`.
- Agregar GitHub Action para generar el XML automáticamente desde `src/`.
- Mantener `dist/PetriaEQSearch.xml` sincronizado con el Lua fuente.
