## 2026.05.30-rev23-module

### Cambiado

- La salida base usa tonos menos brillantes (`grey`, `dim_grey`, `dark_slate_grey`) para no saturar la ventana de Mudlet.
- Los códigos de color de Petria en textos del JSON (`{R`, `{G`, `{Y`, `{M`, `{x`, etc.) se convierten a colores de `cecho`.
- Los códigos de color de Petria se ignoran para normalización/búsqueda, evitando que afecten resultados.
- Si `useColor = false`, los códigos de Petria se eliminan de la salida en vez de mostrarse crudos.
