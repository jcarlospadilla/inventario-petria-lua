-- PetriaEQSearch First Install Bootstrap
-- Uso en Mudlet:
--   1) Copia este archivo o ejecutalo como script temporal.
--   2) Ejecuta: eqinstall
--
-- Instala:
--   - dist/PetriaEQSearch.xml
--   - dist/PetriaEQSearchUpdater.xml

_petriaEqInstaller = _petriaEqInstaller or {}
eqInstaller = _petriaEqInstaller

function eqInstaller.safeKillAlias(id)
  if id then pcall(killAlias, id) end
end

function eqInstaller.safeKillEventHandler(id)
  if id then pcall(killAnonymousEventHandler, id) end
end

function eqInstaller.cleanupRuntime()
  if eqInstaller.aliasIds then
    for _, id in pairs(eqInstaller.aliasIds) do eqInstaller.safeKillAlias(id) end
  end
  eqInstaller.aliasIds = {}

  if eqInstaller.handlers then
    for _, id in pairs(eqInstaller.handlers) do eqInstaller.safeKillEventHandler(id) end
  end
  eqInstaller.handlers = {}
end

eqInstaller.cleanupRuntime()

eqInstaller.config = eqInstaller.config or {
  baseRawUrl = "https://raw.githubusercontent.com/jcarlospadilla/inventario-petria-lua/main",
  installDir = getMudletHomeDir(),
  modules = {
    {
      name = "PetriaEQSearch",
      url = "https://raw.githubusercontent.com/jcarlospadilla/inventario-petria-lua/main/dist/PetriaEQSearch.xml",
      path = getMudletHomeDir() .. "/PetriaEQSearch.xml"
    },
    {
      name = "PetriaEQSearchUpdater",
      url = "https://raw.githubusercontent.com/jcarlospadilla/inventario-petria-lua/main/dist/PetriaEQSearchUpdater.xml",
      path = getMudletHomeDir() .. "/PetriaEQSearchUpdater.xml"
    }
  }
}

eqInstaller.state = eqInstaller.state or {
  running = false,
  index = 0
}

function eqInstaller.echo(msg)
  cecho("<cyan>[EQInstall]<reset> " .. tostring(msg) .. "\n")
end

function eqInstaller.warn(msg)
  cecho("<yellow>[EQInstall]<reset> " .. tostring(msg) .. "\n")
end

function eqInstaller.err(msg)
  cecho("<red>[EQInstall]<reset> " .. tostring(msg) .. "\n")
end

function eqInstaller.trim(s)
  s = tostring(s or "")
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

function eqInstaller.readFile(path)
  local f, err = io.open(path, "r")
  if not f then return nil, err end
  local content = f:read("*a")
  f:close()
  return content
end

function eqInstaller.installCurrentModule()
  local item = eqInstaller.config.modules[eqInstaller.state.index]
  if not item then return end

  local content, err = eqInstaller.readFile(item.path)
  if not content or eqInstaller.trim(content) == "" then
    eqInstaller.err("Archivo descargado vacio o ilegible: " .. tostring(item.path) .. " | " .. tostring(err))
    eqInstaller.state.running = false
    return
  end

  eqInstaller.echo("Instalando modulo: " .. item.name)
  local ok, installErr = pcall(installModule, item.path)
  if not ok then
    eqInstaller.err("installModule fallo para " .. item.name .. ": " .. tostring(installErr))
    eqInstaller.state.running = false
    return
  end

  eqInstaller.echo("Instalado: " .. item.name)
  eqInstaller.downloadNext()
end

function eqInstaller.downloadNext()
  eqInstaller.state.index = eqInstaller.state.index + 1
  local item = eqInstaller.config.modules[eqInstaller.state.index]

  if not item then
    eqInstaller.state.running = false
    eqInstaller.echo("Instalacion completada.")
    eqInstaller.echo("Comandos disponibles: eqsync | eqsearch help | eqversion | eqcheckupdate | equpdate")
    eqInstaller.echo("Siguiente paso recomendado: eqsync")
    return
  end

  eqInstaller.echo("Descargando " .. item.name .. "...")
  downloadFile(item.path, item.url)
end

function eqInstaller.start(force)
  if eqInstaller.state.running and not force then
    eqInstaller.warn("Ya hay una instalacion en curso. Usa eqinstall force para reiniciar.")
    return
  end

  eqInstaller.state.running = true
  eqInstaller.state.index = 0
  eqInstaller.echo("Iniciando primera instalacion desde GitHub...")
  eqInstaller.downloadNext()
end

function eqInstaller.onDownloadDone(_, filename)
  if not eqInstaller.state.running then return end

  local current = eqInstaller.config.modules[eqInstaller.state.index]
  if current and filename == current.path then
    eqInstaller.installCurrentModule()
  end
end

function eqInstaller.onDownloadError(_, ...)
  local args = {...}
  eqInstaller.err("Error de descarga: " .. table.concat(args, " | "))
  eqInstaller.state.running = false
end

function eqInstaller.registerHandlers()
  eqInstaller.handlers.downloadDone = registerAnonymousEventHandler("sysDownloadDone", eqInstaller.onDownloadDone)
  eqInstaller.handlers.downloadError = registerAnonymousEventHandler("sysDownloadError", eqInstaller.onDownloadError)
end

function eqInstaller.installAliases()
  eqInstaller.aliasIds.install = tempAlias([[^eqinstall(?:\s+(force))?$]], function()
    eqInstaller.start((matches[2] or "") == "force")
  end)
end

function eqInstaller.init()
  eqInstaller.registerHandlers()
  eqInstaller.installAliases()
  eqInstaller.echo("Bootstrap listo. Ejecuta: eqinstall")
end

eqInstaller.init()
