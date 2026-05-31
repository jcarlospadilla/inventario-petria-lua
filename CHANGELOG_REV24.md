## 2026.05.30-rev24-module

### Agregado

- `eqbusca <texto> + 14` busca literal por nombre/descripción y filtra nivel exacto 14.
- `eqbusca <texto> + 10-14` busca literal por nombre/descripción y filtra rango 10 a 14.
- `eqsearch` conserva el mismo comportamiento como alias de `eqbusca`.
- El texto antes del último `+` se toma completo como criterio literal, incluyendo espacios.

### Cambiado

- Se actualiza el comentario superior de comandos para reflejar la separación real entre `eqlista`, `eqbusca` y `eqsearch`.
