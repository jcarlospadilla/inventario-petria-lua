-- PetriaEQSearch Updater para Mudlet
-- Version: 2026.05.30-updater1
--
-- Instalar este script como modulo pequeño o pegarlo dentro del perfil.
-- Comandos:
--   eqversion
--   eqcheckupdate
--   equpdate
--   equpdate force

_petriaEqUpdater = _petriaEqUpdater or {}
eqUpdater = _petriaEqUpdater

function eqUpdater.safeKillAlias(id)
  if id then pcall(killAlias, id) end
end

function eqUpdater.safeKillEventHandler(id)
  if id then pcall(killAnonymousEventHandler, id) end
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
end

eqUpdater.cleanupRuntime()

eqUpdater.config = eqUpdater.config or {
  localVersion = "2026.05.30-rev12-module",
  versionUrl = "https://raw.githubusercontent.com/jcarlospadilla/inventario-petria-lua/main/VERSION",
  moduleUrl = "https://raw.githubusercontent.com/jcarlospadilla/inventario-petria-lua/main/dist/PetriaEQSearch.xml",
  moduleName = "PetriaEQSearch",
  versionPath = getMudletHomeDir() .. "/PetriaEQSearch_REMOTE_VERSION.txt",
  modulePath = getMudletHomeDir() .. "/PetriaEQSearch_update.xml"
}

eqUpdater.state = eqUpdater.state or {
  action = nil,
  force = false,
  remoteVersion = nil
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

function eqUpdater.getLocalVersion()
  -- Si el modulo principal existe y expone version, usala.
  if type(eqInv) == "table" and eqInv.version then
    return tostring(eqInv.version)
  end
  return tostring(eqUpdater.config.localVersion)
end

function eqUpdater.showVersion()
  eqUpdater.echo("Version local: " .. eqUpdater.getLocalVersion())
  eqUpdater.echo("Version URL: " .. eqUpdater.config.versionUrl)
end

function eqUpdater.checkUpdate(force)
  eqUpdater.state.action = force and "update-version" or "check-version"
  eqUpdater.state.force = force == true
  eqUpdater.state.remoteVersion = nil
  eqUpdater.echo("Consultando VERSION en GitHub...")
  downloadFile(eqUpdater.config.versionPath, eqUpdater.config.versionUrl)
end

function eqUpdater.update(force)
  eqUpdater.checkUpdate(force == true)
end

function eqUpdater.readFile(path)
  local f, err = io.open(path, "r")
  if not f then return nil, err end
  local content = f:read("*a")
  f:close()
  return content
end

function eqUpdater.onVersionDownloaded()
  local content, err = eqUpdater.readFile(eqUpdater.config.versionPath)
  if not content then
    eqUpdater.err("No pude leer VERSION descargado: " .. tostring(err))
    return
  end

  local remote = eqUpdater.trim(content)
  eqUpdater.state.remoteVersion = remote
  local localVersion = eqUpdater.getLocalVersion()

  eqUpdater.echo("Version local: " .. localVersion)
  eqUpdater.echo("Version disponible: " .. remote)

  if remote == "" then
    eqUpdater.err("VERSION remoto esta vacio.")
    return
  end

  if eqUpdater.state.action == "check-version" then
    if remote ~= localVersion then
      eqUpdater.warn("Hay una actualizacion disponible. Usa: equpdate")
    else
      eqUpdater.echo("Ya tienes la version mas reciente.")
    end
    return
  end

  if remote == localVersion and not eqUpdater.state.force then
    eqUpdater.echo("Ya tienes la version mas reciente. Usa 'equpdate force' para reinstalar.")
    return
  end

  eqUpdater.echo("Descargando modulo actualizado...")
  eqUpdater.state.action = "download-module"
  downloadFile(eqUpdater.config.modulePath, eqUpdater.config.moduleUrl)
end

function eqUpdater.onModuleDownloaded()
  local content, err = eqUpdater.readFile(eqUpdater.config.modulePath)
  if not content or eqUpdater.trim(content) == "" then
    eqUpdater.err("Modulo descargado vacio o ilegible: " .. tostring(err))
    return
  end

  eqUpdater.echo("Modulo descargado: " .. eqUpdater.config.modulePath)
  eqUpdater.echo("Instalando modulo en Mudlet...")

  local ok, installErr = pcall(installModule, eqUpdater.config.modulePath)
  if not ok then
    eqUpdater.err("installModule fallo: " .. tostring(installErr))
    return
  end

  eqUpdater.config.localVersion = eqUpdater.state.remoteVersion or eqUpdater.config.localVersion
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
    eqUpdater.checkUpdate(false)
  end)

  eqUpdater.aliasIds.update = tempAlias([[^equpdate(?:\s+(force))?$]], function()
    eqUpdater.update((matches[2] or "") == "force")
  end)
end

function eqUpdater.init()
  eqUpdater.registerHandlers()
  eqUpdater.installAliases()
  eqUpdater.echo("Updater listo. Usa: eqversion | eqcheckupdate | equpdate")
end

eqUpdater.init()
