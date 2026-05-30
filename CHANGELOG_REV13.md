## 2026.05.30-rev13-module

### Corregido

- Corrige error de importación `LuaSQL: table items has no column named _set_norm`.
- Los campos internos de cache `_vestir_norm`, `_tipo_norm`, `_flags_norm` y `_set_norm` ya no se insertan en SQLite.
- El módulo principal ahora expone `eqInv.version = "2026.05.30-rev13-module"` para que el updater compare correctamente contra `VERSION`.
