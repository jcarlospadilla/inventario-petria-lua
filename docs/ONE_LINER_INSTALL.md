# Instalación desde el input de Mudlet

Si tu Mudlet permite ejecutar Lua desde la línea de entrada usando `lua ...`, puedes instalar el bootstrap con este comando de una sola línea:

```lua
lua local p=getMudletHomeDir().."/petria_eq_install.lua"; local u="https://raw.githubusercontent.com/jcarlospadilla/inventario-petria-lua/main/install.lua"; registerAnonymousEventHandler("sysDownloadDone",function(_,f) if f==p then dofile(p); tempTimer(0.2,function() expandAlias("eqinstall") end) end end); downloadFile(p,u)
```

## Qué hace

1. Descarga `install.lua` desde GitHub.
2. Lo guarda como:

```text
<MudletHome>/petria_eq_install.lua
```

3. Ejecuta el archivo descargado con `dofile(...)`.
4. Llama `eqinstall` automáticamente.

## Si no funciona

Si el comando se envía al MUD como texto normal, tu Mudlet/perfil no está interpretando `lua ...` desde el input. En ese caso:

1. Abre el editor de scripts de Mudlet.
2. Crea un script temporal.
3. Pega el contenido de `install.lua`.
4. Guarda.
5. Ejecuta:

```text
eqinstall
```
