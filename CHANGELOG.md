# Changelog

## 2026.05.30-rev12-module

Versión inicial preparada como módulo de Mudlet.

### Agregado

- Descarga de inventario desde URL con `eqsync`.
- DB local de Mudlet para items, vestir, flags, spells, afectaciones e instancias.
- Búsqueda por nombre/descripción.
- Búsqueda por nivel y rango.
- Búsqueda por `Set`.
- Listado de índices: tipos, vestir, flags y sets.
- Salida agrupada por `Vestir`/slot.
- Formato compacto de lugar: `{Area_Definicion} => {Instancia_Activa} (Extra_Data)`.
- Ignora `emblema` en equipo faltante.
- Slot `usando como luz` se resuelve por `Tipo = light`.
- Captura automática de `equipo faltante` y `equipo faltante inventario`.
- Nivel automático desde GMCP para `eqfaltante`.
- 3 sugerencias por slot faltante.
- Modos de recomendación: `subir`, `pk`, `defensa`, `caster`, `healer`, `danio`, `balance`.
- Scoring heurístico con stats, HP, Mana, Hitroll, Damroll, saves, protecciones, resistencias, inmunidades, SpellPower y HealPower.
- Comando `eqpower [nivel]` para ver cap de SpellPower/HealPower.
- Limpieza defensiva para evitar duplicar aliases, triggers, handlers y timers al recargar.
