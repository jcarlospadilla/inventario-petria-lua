-- PetriaEQSearch Updater para Mudlet
-- Version: 2026.05.30-updater3
--
-- Comandos:
--   eqversion
--   eqcheckupdate
--   equpdate
--   equpdate force
--   eqautoupdate
--   eqautoupdate off|check|on

_petriaEqUpdater = _petriaEqUpdater or {}
eqUpdater = _petriaEqUpdater

function eqUpdater.safeKillAlias(id)
  if id then pcall(killAlias, id) end
end

function eqUpdater.safeKillEventHandler(id)
  if id then pcall(killAnonymousEventHandler, id) end
end

function eqUpdater.safeKillTimer(id)
  if id then pcall(killTimer, id) end
end

function eqUpdater.cleanupRuntime()
  if eqUpdater.aliasIds then
    for _, id in pairs(eqUpdater.aliasIds) do eqUpdater.safeKillAlias(id) end
  end
  eqUpdater.aliasIds = {}

  if eqUpdater.handlers then
    for _, id in pairs(eqUpdater.handlers) do eqUpdater.safeKillEventHandler(id) end
  end
  eqUpdater.handlers = {}

  if eqUpdater.timers then
    for _, id in pairs(eqUpdater.timers) do eqUpdater.safeKillTimer(id) end
  end
  eqUpdater.timers = {}
end

eqUpdater.cleanupRuntime()

eqUpdater.config = eqUpdater.config or {
  updaterVersion = "2026.05.30-updater3",
  localVersion = "2026.05.30-rev22-module",
  versionUrl = "https://raw.githubusercontent.com/jcarlospadilla/inventario-petria-lua/main/VERSION",
  moduleUrl = "https://raw.githubusercontent.com/jcarlospadilla/inventario-petria-lua/main/dist/PetriaEQSearch.xml",
  moduleName = "PetriaEQSearch",
  versionPath = getMudletHomeDir() .. "/PetriaEQSearch_REMOTE_VERSION.txt",
  modulePath = getMudletHomeDir() .. "/PetriaEQSearch.xml",
  autoUpdatePath = getMudletHomeDir() .. "/PetriaEQSearch_AUTOUPDATE.txt",
  autoUpdateMode = "check" -- off | check | on
}

eqUpdater.state = eqUpdater.state or {
  action = nil,
  force = false,
  remoteVersion = nil,
  versionEventHandled = false,
  moduleEventHandled = false
}

function eqUpdater.trim(s)
  s = tostring(s or "")
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

function eqUpdater.echo(msg)
  cecho("<cyan>[EQUpdate]<reset> " .. tostring(msg) .. "\n")
end

function eqUpdater.warn(msg)
  cecho("<yellow>[EQUpdate]<reset> " .. tostring(msg) .. "\n")
end

function eqUpdater.err(msg)
  cecho("<red>[EQUpdate]<reset> " .. tostring(msg) .. "\n")
end

function eqUpdater.readFile(path)
  local f, err = io.open(path, "r")
  if not f then return nil, err end
  local content = f:read("*a")
  f:close()
  return content
end

function eqUpdater.writeFile(path, content)
  local f, err = io.open(path, "w")
  if not f then return nil, err end
  f:write(tostring(content or ""))
  f:close()
  return true
end

function eqUpdater.getLocalVersion()
  if type(eqInv) == "table" and eqInv.version then
    return tostring(eqInv.version)
  end
  return tostring(eqUpdater.config.localVersion)
end

function eqUpdater.showVersion()
  eqUpdater.echo("Updater: " .. tostring(eqUpdater.config.updaterVersion or "?"))
  eqUpdater.echo("Version local: " .. eqUpdater.getLocalVersion())
  eqUpdater.echo("Version URL: " .. eqUpdater.config.versionUrl)
  eqUpdater.echo("Auto-update: " .. tostring(eqUpdater.config.autoUpdateMode or "check"))
end

function eqUpdater.loadAutoUpdateMode()
  local content = eqUpdater.readFile(eqUpdater.config.autoUpdatePath)
  local mode = eqUpdater.trim(content or "")
  if mode ~= "off" and mode ~= "check" and mode ~= "on" then
    mode = eqUpdater.config.autoUpdateMode or "check"
  end
  eqUpdater.config.autoUpdateMode = mode
  return mode
end

function eqUpdater.saveAutoUpdateMode(mode)
  mode = eqUpdater.trim(mode or "")
  if mode ~= "off" and mode ~= "check" and mode ~= "on" then
    eqUpdater.warn("Uso: eqautoupdate off | check | on")
    return
  end
  eqUpdater.config.autoUpdateMode = mode
  eqUpdater.writeFile(eqUpdater.config.autoUpdatePath, mode)
  eqUpdater.echo("Auto-update definido: " .. mode)
  if mode == "off" then
    eqUpdater.echo("No revisara actualizaciones al iniciar.")
  elseif mode == "check" then
    eqUpdater.echo("Al iniciar solo avisara si hay actualizacion.")
  elseif mode == "on" then
    eqUpdater.echo("Al iniciar descargara e instalara automaticamente si hay actualizacion.")
  end
end

function eqUpdater.showAutoUpdate()
  eqUpdater.echo("Auto-update actual: " .. tostring(eqUpdater.config.autoUpdateMode or "check"))
  echo("Uso: eqautoupdate off | check | on\n")
end

function eqUpdater.checkUpdate()
  eqUpdater.state.action = "check-version"
  eqUpdater.state.force = false
  eqUpdater.state.remoteVersion = nil
  eqUpdater.state.versionEventHandled = false
  eqUpdater.state.moduleEventHandled = false
  eqUpdater.echo("Consultando VERSION en GitHub...")
  downloadFile(eqUpdater.config.versionPath, eqUpdater.config.versionUrl)
end

function eqUpdater.update(force)
  eqUpdater.state.action = "update-version"
  eqUpdater.state.force = force == true
  eqUpdater.state.remoteVersion = nil
  eqUpdater.state.versionEventHandled = false
  eqUpdater.state.moduleEventHandled = false
  eqUpdater.echo("Consultando VERSION en GitHub...")
  downloadFile(eqUpdater.config.versionPath, eqUpdater.config.versionUrl)
end

function eqUpdater.onVersionDownloaded()
  if eqUpdater.state.versionEventHandled then return end
  if eqUpdater.state.action ~= "check-version" and eqUpdater.state.action ~= "update-version" then return end
  eqUpdater.state.versionEventHandled = true

  local content, err = eqUpdater.readFile(eqUpdater.config.versionPath)
  if not content then
    eqUpdater.err("No pude leer VERSION descargado: " .. tostring(err))
    eqUpdater.state.action = nil
    return
  end

  local remote = eqUpdater.trim(content)
  eqUpdater.state.remoteVersion = remote
  local localVersion = eqUpdater.getLocalVersion()

  eqUpdater.echo("Version local: " .. localVersion)
  eqUpdater.echo("Version disponible: " .. remote)

  if remote == "" then
    eqUpdater.err("VERSION remoto esta vacio.")
    eqUpdater.state.action = nil
    return
  end

  if eqUpdater.state.action == "check-version" then
    if remote ~= localVersion then
      eqUpdater.warn("Hay una actualizacion disponible. Usa: equpdate")
    else
      eqUpdater.echo("Ya tienes la version mas reciente.")
    end
    eqUpdater.state.action = nil
    return
  end

  if remote == localVersion and not eqUpdater.state.force then
    eqUpdater.echo("Ya tienes la version mas reciente. Usa 'equpdate force' para reinstalar.")
    eqUpdater.state.action = nil
    return
  end

  eqUpdater.echo("Descargando modulo actualizado...")
  eqUpdater.state.action = "download-module"
  eqUpdater.state.moduleEventHandled = false
  downloadFile(eqUpdater.config.modulePath, eqUpdater.config.moduleUrl)
end

function eqUpdater.onModuleDownloaded()
  if eqUpdater.state.moduleEventHandled then return end
  if eqUpdater.state.action ~= "download-module" then return end
  eqUpdater.state.moduleEventHandled = true
  eqUpdater.state.action = "installing-module"

  local content, err = eqUpdater.readFile(eqUpdater.config.modulePath)
  if not content or eqUpdater.trim(content) == "" then
    eqUpdater.err("Modulo descargado vacio o ilegible: " .. tostring(err))
    eqUpdater.state.action = nil
    return
  end

  eqUpdater.echo("Modulo descargado: " .. eqUpdater.config.modulePath)
  eqUpdater.echo("Instalando modulo en Mudlet...")

  local ok, installErr = pcall(installModule, eqUpdater.config.modulePath)
  if not ok then
    eqUpdater.err("installModule fallo: " .. tostring(installErr))
    eqUpdater.state.action = nil
    return
  end

  eqUpdater.config.localVersion = eqUpdater.state.remoteVersion or eqUpdater.config.localVersion
  eqUpdater.state.action = nil
  eqUpdater.echo("Actualizacion instalada. Si no ves cambios, recarga el perfil o Module Manager.")
end

function eqUpdater.onDownloadDone(_, filename)
  if filename == eqUpdater.config.versionPath then
    eqUpdater.onVersionDownloaded()
  elseif filename == eqUpdater.config.modulePath then
    eqUpdater.onModuleDownloaded()
  end
end

function eqUpdater.onDownloadError(_, ...)
  local args = {...}
  eqUpdater.err("Error de descarga: " .. table.concat(args, " | "))
  eqUpdater.state.action = nil
end

function eqUpdater.registerHandlers()
  eqUpdater.handlers.downloadDone = registerAnonymousEventHandler("sysDownloadDone", eqUpdater.onDownloadDone)
  eqUpdater.handlers.downloadError = registerAnonymousEventHandler("sysDownloadError", eqUpdater.onDownloadError)
end

function eqUpdater.installAliases()
  eqUpdater.aliasIds.version = tempAlias([[^eqversion$]], function()
    eqUpdater.showVersion()
  end)

  eqUpdater.aliasIds.check = tempAlias([[^eqcheckupdate$]], function()
    eqUpdater.checkUpdate()
  end)

  eqUpdater.aliasIds.update = tempAlias([[^equpdate(?:\s+(force))?$]], function()
    eqUpdater.update((matches[2] or "") == "force")
  end)

  eqUpdater.aliasIds.auto = tempAlias([[^eqautoupdate(?:\s+(off|check|on))?\s*$]], function()
    local mode = matches[2] or ""
    if mode == "" then eqUpdater.showAutoUpdate()
    else eqUpdater.saveAutoUpdateMode(mode) end
  end)
end

function eqUpdater.runStartupAutoUpdate()
  local mode = eqUpdater.loadAutoUpdateMode()
  if mode == "off" then return end

  eqUpdater.timers.startupAutoUpdate = tempTimer(4, function()
    if mode == "check" then
      eqUpdater.echo("Auto-check de actualizaciones...")
      eqUpdater.checkUpdate()
    elseif mode == "on" then
      eqUpdater.echo("Auto-update activo: revisando e instalando si hay nueva version...")
      eqUpdater.update(false)
    end
  end)
end

function eqUpdater.init()
  eqUpdater.registerHandlers()
  eqUpdater.installAliases()
  eqUpdater.loadAutoUpdateMode()
  eqUpdater.echo("Updater listo. Usa: eqversion | eqcheckupdate | equpdate | eqautoupdate")
  eqUpdater.runStartupAutoUpdate()
end

eqUpdater.init()
