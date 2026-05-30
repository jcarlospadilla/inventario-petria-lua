# Uso de PetriaEQSearch

## Cargar inventario

```text
eqsync
```

Para usar una URL manual:

```text
eqsync https://www.petriamud.com/inv/inventarionew.json?t=1780176129349
```

## Búsquedas

Buscar por nombre o descripción:

```text
eqsearch varita
```

Buscar por rango de nivel:

```text
eqsearch 10-14
```

Buscar por rango y slot:

```text
eqsearch 10-14 escudo
eqsearch 10-14 luz
eqsearch 10-14 sosteniendo
```

## Sets

Listar todos los sets:

```text
eqsearch set
```

Buscar items de un set:

```text
eqsearch set fuego
```

## Equipo faltante

Usar nivel desde GMCP:

```text
eqfaltante
```

Override manual:

```text
eqfaltante 14
```

El comando ejecuta internamente:

```lua
sendAll("equipo faltante", "equipo faltante inventario", false)
```

Luego captura los slots vacíos, ignora `emblema` y muestra 3 sugerencias por slot.

## Modos de recomendación

```text
eqmodo subir
eqmodo pk
eqmodo defensa
eqmodo caster
eqmodo healer
eqmodo danio
eqmodo balance
```

Cada tabla muestra el modo activo y los modos disponibles encima de los resultados.

## SpellPower / HealPower

```text
eqpower
eqpower 14
```

Muestra:

- cap de porcentaje por nivel;
- puntos requeridos para ese cap;
- tope bruto por objeto para ese nivel.
