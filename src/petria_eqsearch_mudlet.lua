-- Petria EQSearch para Mudlet
-- Version: 2026.05.30-rev25-module
--
-- Que hace:
--   - Descarga inventarionew.json desde una URL configurable.
--   - Limpia la DB local anterior y reindexa el inventario.
--   - Busca items por nombre/descripcion, nivel, rango, slot, set, tipo y flags.
--   - Agrupa la salida por Vestir/slot, ordenando items por nivel descendente.
--   - Captura "equipo faltante" del MUD y busca 3 piezas compatibles por slot usando nivel GMCP.
--
-- Comandos:
--   eqsync [url]
--   eqlista help
--   eqlista 14
--   eqlista 14 luz
--   eqlista luz 14
--   eqlista 10-14
--   eqlista 10-14 escudo
--   eqlista set dragon
--   eqlista tipos|vestir|flags|sets
--   eqlista formato grouped|table|paragraph
--   eqlista modo subir|pk|defensa|caster|healer|danio|balance
--   eqbusca varita
--   eqbusca arco corto + 14
--   eqbusca arco corto + 10-14
--   eqsearch varita        -- alias de eqbusca
--   eqmodo subir|pk|defensa|caster|healer|danio|balance
--   eqorden nivel|pts|nombre
--   eqpower [nivel]
--   eqformat grouped|table|paragraph
--   eqfaltante [nivel]
--   eqfaltantes [nivel]
--   eqlevel 14
--
-- Notas:
--   - "usando como luz" busca Tipo = light, porque los light no siempre traen Vestir.
--   - "emblema" se ignora en eqfaltantes.
--   - La data trae Vestir mezclado en ingles/español, por eso los alias aceptan ambos.

_eqInv = _eqInv or {}
eqInv = _eqInv
eqInv.version = "2026.05.30-rev25-module"

-- ------------------------------------------------------------
-- Limpieza defensiva para evitar duplicados al recargar el script.
-- ------------------------------------------------------------
function eqInv.safeKillAlias(id)
  if id then pcall(killAlias, id) end
end

function eqInv.safeKillTrigger(id)
  if id then pcall(killTrigger, id) end
end

function eqInv.safeKillEventHandler(id)
  if id then pcall(killAnonymousEventHandler, id) end
end

function eqInv.safeKillTimer(id)
  if id then pcall(killTimer, id) end
end

function eqInv.cleanupRuntime()
  if eqInv.aliasIds then
    for _, id in pairs(eqInv.aliasIds) do eqInv.safeKillAlias(id) end
  end
  eqInv.aliasIds = {}

  if eqInv.handlers then
    for _, id in pairs(eqInv.handlers) do eqInv.safeKillEventHandler(id) end
  end
  eqInv.handlers = {}

  if eqInv.missingCapture and eqInv.missingCapture.triggers then
    for _, id in pairs(eqInv.missingCapture.triggers) do eqInv.safeKillTrigger(id) end
  end
  eqInv.missingCapture = nil

  if eqInv.timers then
    for _, id in pairs(eqInv.timers) do eqInv.safeKillTimer(id) end
  end
  eqInv.timers = {}
  eqInv.importState = nil
end

eqInv.cleanupRuntime()

eqInv.config = eqInv.config or {
  defaultUrl = "https://www.petriamud.com/inv/inventarionew.json?t=1780176129349",
  defaultLevel = nil,
  resultLimit = 25,
  -- En busquedas amplias agrupadas, muestra pocos items por grupo para que no se quede solo en el primer grupo.
  groupedItemLimit = 3,
  groupLimit = 25,

  -- Ancho maximo de salida. Mantener por debajo del ancho visual del MUD para evitar wrap feo.
  boxWidth = 84,

  missingSlotLimit = 3,
  importChunkSize = 120,
  dbName = "petriaeqinv",

  -- groupedTable = tabla agrupada por Vestir/slot; table = tabla plana; paragraph = parrafo minimalista.
  outputMode = "groupedTable",
  useColor = true,

  -- Colores base de salida. Se usan tonos menos brillantes para no saturar el buffer.
  baseTextColor = "grey",
  borderColor = "dim_grey",
  headerColor = "dark_slate_grey",
  renderMudColors = true,

  -- Modo de recomendacion: subir, pk, defensa, caster, healer, danio, balance.
  recommendMode = "subir",

  -- Orden visual normal: nivel | pts | nombre.
  -- eqfaltante usa siempre pts aunque aqui diga nivel.
  displaySortMode = "nivel",

  -- No usamos Vestir como columna: Vestir se muestra como encabezado de grupo.
  tableColumns = {
    nivel = 5,
    peso = 5,
    score = 6,
    tipo = 11,
    nombre = 38,
    afecta = 36,
    lugar = 64
  },

  ignoredMissingSlots = {
    ["emblema"] = true
  }
}

eqInv.cache = {
  ready = false,
  items = {},
  byVnum = {},
  typeCounts = {},
  wearCounts = {},
  flagCounts = {},
  setCounts = {},
  loadedAt = nil,
  lastUrl = nil
}

eqInv.timers = eqInv.timers or {}

-- ------------------------------------------------------------
-- Utilidades
-- ------------------------------------------------------------
function eqInv.echo(msg)
  cecho("<cyan>[EQSearch]<reset> " .. tostring(msg) .. "\n")
end

function eqInv.warn(msg)
  cecho("<yellow>[EQSearch]<reset> " .. tostring(msg) .. "\n")
end

function eqInv.err(msg)
  cecho("<red>[EQSearch]<reset> " .. tostring(msg) .. "\n")
end

function eqInv.mudColorMap()
  return {
    b = "blue",
    B = "dodger_blue",
    c = "cyan",
    C = "deep_sky_blue",
    g = "green",
    G = "lime_green",
    m = "purple",
    M = "magenta",
    o = "orange",
    O = "dark_orange",
    r = "red",
    R = "firebrick",
    y = "saddle_brown",
    Y = "yellow",
    w = "grey",
    W = "white",
    D = "dim_grey",
    H = "bold",
    i = "italic",
    u = "underline"
  }
end

function eqInv.stripMudColors(text)
  text = tostring(text or "")
  return (text:gsub("{[bBcCgGmMoOrRyYwWDHixu]", ""))
end

function eqInv.renderMudColors(text, baseColor)
  text = tostring(text or "")
  if not eqInv.config.renderMudColors then return eqInv.stripMudColors(text) end

  local map = eqInv.mudColorMap()
  local base = baseColor or eqInv.config.baseTextColor or "grey"

  -- Evita que texto del JSON rompa cecho con tags accidentales.
  text = text:gsub("<", "&lt;"):gsub(">", "&gt;")

  text = text:gsub("{(.)", function(code)
    if code == "x" then return "<reset><" .. base .. ">" end
    local mudletColor = map[code]
    if mudletColor then return "<" .. mudletColor .. ">" end
    return "{" .. code
  end)

  return text
end

function eqInv.out(text, color)
  text = tostring(text or "")
  color = color or eqInv.config.baseTextColor or "grey"

  if eqInv.config.useColor and color and color ~= "" then
    cecho("<" .. color .. ">" .. eqInv.renderMudColors(text, color) .. "<reset>\n")
  else
    echo(eqInv.stripMudColors(text) .. "\n")
  end
end

function eqInv.colorByLevel(level)
  level = tonumber(level) or 0
  if level <= 20 then return "green" end
  if level <= 60 then return "yellow" end
  if level <= 100 then return "orange" end
  return "red"
end

function eqInv.trim(s)
  s = tostring(s or "")
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

function eqInv.safeString(v)
  if v == nil then return "" end
  if type(v) == "string" then return v end
  if type(v) == "number" or type(v) == "boolean" then return tostring(v) end
  if type(v) == "table" then
    local ok, encoded = pcall(yajl.to_string, v)
    if ok and encoded then return encoded end
    return tostring(v)
  end
  return tostring(v)
end

function eqInv.norm(s)
  s = eqInv.stripMudColors(eqInv.safeString(s)):lower()
  local repl = {
    ["á"]="a", ["à"]="a", ["ä"]="a", ["â"]="a",
    ["é"]="e", ["è"]="e", ["ë"]="e", ["ê"]="e",
    ["í"]="i", ["ì"]="i", ["ï"]="i", ["î"]="i",
    ["ó"]="o", ["ò"]="o", ["ö"]="o", ["ô"]="o",
    ["ú"]="u", ["ù"]="u", ["ü"]="u", ["û"]="u",
    ["ñ"]="n"
  }
  for a, b in pairs(repl) do s = s:gsub(a, b) end
  s = s:gsub("[%p%c]", " ")
  s = s:gsub("%s+", " ")
  return eqInv.trim(s)
end

function eqInv.splitWords(s)
  local out = {}
  for w in eqInv.norm(s):gmatch("%S+") do table.insert(out, w) end
  return out
end

function eqInv.containsText(text, query)
  text = eqInv.norm(text)
  local words = eqInv.splitWords(query)
  if #words == 0 then return true end
  for _, w in ipairs(words) do
    if not text:find(w, 1, true) then return false end
  end
  return true
end

function eqInv.join(list, sep)
  sep = sep or ", "
  local out = {}
  for _, v in ipairs(list or {}) do
    local s = eqInv.safeString(v)
    if s ~= "" then table.insert(out, s) end
  end
  return table.concat(out, sep)
end

function eqInv.flagsToList(flags)
  local out = {}
  flags = eqInv.safeString(flags)
  for token in flags:gmatch("[^,%s]+") do
    token = eqInv.trim(token)
    if token ~= "" then table.insert(out, token) end
  end
  return out
end

function eqInv.formatModifier(n)
  n = tonumber(n) or 0
  if n > 0 then return "+" .. tostring(n) end
  return tostring(n)
end

function eqInv.formatAffects(list)
  local out = {}
  for _, a in ipairs(list or {}) do
    if type(a) == "table" then
      local loc = a.Location or a.location or a.loc or "?"
      local mod = a.Modifier or a.modifier or a.mod or 0
      table.insert(out, tostring(loc) .. " " .. eqInv.formatModifier(mod))
    end
  end
  return table.concat(out, ", ")
end

function eqInv.formatInstances(list)
  local out = {}
  for _, inst in ipairs(list or {}) do
    if type(inst) == "table" then
      for _, v in pairs(inst) do
        local s = eqInv.safeString(v)
        if s ~= "" then table.insert(out, s) end
      end
    else
      local s = eqInv.safeString(inst)
      if s ~= "" then table.insert(out, s) end
    end
  end
  return table.concat(out, "; ")
end

function eqInv.hasValue(s)
  s = eqInv.trim(s or "")
  if s == "" then return false end
  local n = eqInv.norm(s)
  return n ~= "" and n ~= "null" and n ~= "nil" and n ~= "[]" and n ~= "{}"
end

function eqInv.formatLugar(item)
  local area = eqInv.trim(item.area or "")
  local inst = eqInv.trim(item.instancias_text or "")
  local extra = eqInv.trim(item.extra_data or "")

  local lugar = "?"
  if eqInv.hasValue(area) then lugar = area end

  -- Solo muestra Instancia_Activa si trae informacion real.
  if eqInv.hasValue(inst) then
    lugar = lugar .. " => " .. inst
  end

  -- Solo muestra Extra_Data si trae informacion real.
  if eqInv.hasValue(extra) then
    lugar = lugar .. " (" .. extra .. ")"
  end

  return lugar
end

function eqInv.formatSpells(list)
  if type(list) ~= "table" then return eqInv.safeString(list) end
  local out = {}
  for _, sp in ipairs(list or {}) do
    if type(sp) == "table" then
      local name = sp.Spell or sp.spell or sp.Name or sp.name or sp[1]
      local lvl = sp.Level or sp.level or sp.Nivel or sp.nivel or sp[2]
      if name then
        if lvl then table.insert(out, tostring(name) .. "@" .. tostring(lvl))
        else table.insert(out, tostring(name)) end
      end
    else
      local s = eqInv.safeString(sp)
      if s ~= "" then table.insert(out, s) end
    end
  end
  return table.concat(out, ", ")
end

function eqInv.shorten(s, width)
  s = eqInv.safeString(s)
  width = tonumber(width) or 10
  if #s <= width then return s end
  if width <= 1 then return s:sub(1, width) end
  return s:sub(1, width - 1) .. "…"
end

function eqInv.padRight(s, width)
  s = eqInv.shorten(s, width)
  return s .. string.rep(" ", math.max(0, width - #s))
end

function eqInv.padLeft(s, width)
  s = eqInv.shorten(s, width)
  return string.rep(" ", math.max(0, width - #s)) .. s
end

function eqInv.repeatChar(ch, count)
  return string.rep(ch or "-", tonumber(count) or 1)
end

function eqInv.isArray(t)
  if type(t) ~= "table" then return false end
  local n = 0
  for k, _ in pairs(t) do
    if type(k) ~= "number" then return false end
    if k > n then n = k end
  end
  return n > 0
end

function eqInv.parseLevelArg(arg)
  arg = eqInv.trim(arg)
  if arg == "" then return nil, nil, "" end

  local a, b, rest = arg:match("^(%d+)%s*%-%s*(%d+)%s*(.*)$")
  if a and b then
    a, b = tonumber(a), tonumber(b)
    if a > b then a, b = b, a end
    return a, b, eqInv.trim(rest)
  end

  local n, rest2 = arg:match("^(%d+)%s*(.*)$")
  if n then
    n = tonumber(n)
    return 0, n, eqInv.trim(rest2)
  end

  return nil, nil, arg
end

function eqInv.getPath(root, path)
  local cur = root
  for key in tostring(path or ""):gmatch("[^.]+") do
    if type(cur) ~= "table" then return nil end
    cur = cur[key]
  end
  return cur
end

function eqInv.toPositiveNumber(v)
  if v == nil then return nil end
  if type(v) == "string" then
    v = v:match("(%d+)")
  end
  v = tonumber(v)
  if v and v > 0 then return math.floor(v) end
  return nil
end

function eqInv.getGMCPLevel()
  if type(gmcp) ~= "table" then return nil end

  -- Rutas comunes de GMCP. Petria puede variar el nombre entre level/nivel.
  local paths = {
    "Char.Status.level",
    "Char.Status.nivel",
    "Char.Vitals.level",
    "Char.Vitals.nivel",
    "Char.Base.level",
    "Char.Base.nivel",
    "Char.Info.level",
    "Char.Info.nivel",
    "char.status.level",
    "char.status.nivel",
    "char.vitals.level",
    "char.vitals.nivel"
  }

  for _, p in ipairs(paths) do
    local lvl = eqInv.toPositiveNumber(eqInv.getPath(gmcp, p))
    if lvl then return lvl, p end
  end

  -- Fallback defensivo: busca una llave llamada level/nivel hasta 3 niveles de profundidad.
  local function scan(t, depth)
    if type(t) ~= "table" or depth > 3 then return nil end
    for k, v in pairs(t) do
      local nk = eqInv.norm(k)
      if nk == "level" or nk == "nivel" then
        local lvl = eqInv.toPositiveNumber(v)
        if lvl then return lvl end
      end
      local nested = scan(v, depth + 1)
      if nested then return nested end
    end
    return nil
  end

  return scan(gmcp, 0), "scan"
end

-- ------------------------------------------------------------
-- Mapeo de slots visibles del MUD a Vestir/Tipo del JSON.
-- La data viene mezclada: algunos Vestir estan en ingles y otros en español.
-- ------------------------------------------------------------
eqInv.slotAliases = {
  ["luz"] = { mode = "tipo", tipo = "light" },
  ["como luz"] = { mode = "tipo", tipo = "light" },
  ["usando como luz"] = { mode = "tipo", tipo = "light" },

  ["dedo"] = { mode = "vestir", slots = {"Finger", "Dedo"} },
  ["en un dedo izq"] = { mode = "vestir", slots = {"Finger", "Dedo"} },
  ["en un dedo der"] = { mode = "vestir", slots = {"Finger", "Dedo"} },
  ["finger"] = { mode = "vestir", slots = {"Finger", "Dedo"} },

  ["cuello"] = { mode = "vestir", slots = {"Neck", "Cuello"} },
  ["en el cuello 1"] = { mode = "vestir", slots = {"Neck", "Cuello"} },
  ["en el cuello 2"] = { mode = "vestir", slots = {"Neck", "Cuello"} },
  ["neck"] = { mode = "vestir", slots = {"Neck", "Cuello"} },

  ["cuerpo"] = { mode = "vestir", slots = {"Body", "Cuerpo"} },
  ["en el cuerpo"] = { mode = "vestir", slots = {"Body", "Cuerpo"} },
  ["body"] = { mode = "vestir", slots = {"Body", "Cuerpo"} },

  ["cabeza"] = { mode = "vestir", slots = {"Head", "Cabeza"} },
  ["en la cabeza"] = { mode = "vestir", slots = {"Head", "Cabeza"} },
  ["head"] = { mode = "vestir", slots = {"Head", "Cabeza"} },

  ["piernas"] = { mode = "vestir", slots = {"Legs", "Piernas"} },
  ["en las piernas"] = { mode = "vestir", slots = {"Legs", "Piernas"} },
  ["legs"] = { mode = "vestir", slots = {"Legs", "Piernas"} },

  ["pies"] = { mode = "vestir", slots = {"Feet", "Pies"} },
  ["en los pies"] = { mode = "vestir", slots = {"Feet", "Pies"} },
  ["feet"] = { mode = "vestir", slots = {"Feet", "Pies"} },

  ["manos"] = { mode = "vestir", slots = {"Hands", "Manos"} },
  ["en las manos"] = { mode = "vestir", slots = {"Hands", "Manos"} },
  ["hands"] = { mode = "vestir", slots = {"Hands", "Manos"} },

  ["brazos"] = { mode = "vestir", slots = {"Arms", "Brazos"} },
  ["en los brazos"] = { mode = "vestir", slots = {"Arms", "Brazos"} },
  ["arms"] = { mode = "vestir", slots = {"Arms", "Brazos"} },

  ["escudo"] = { mode = "vestir", slots = {"Shield", "Rodela", "Escudo"} },
  ["como escudo"] = { mode = "vestir", slots = {"Shield", "Rodela", "Escudo"} },
  ["shield"] = { mode = "vestir", slots = {"Shield", "Rodela", "Escudo"} },
  ["rodela"] = { mode = "vestir", slots = {"Rodela", "Shield", "Escudo"} },

  ["espalda"] = { mode = "vestir", slots = {"About", "Back", "Espalda", "Sobre"} },
  ["en la espalda"] = { mode = "vestir", slots = {"About", "Back", "Espalda", "Sobre"} },
  ["about"] = { mode = "vestir", slots = {"About", "Back", "Espalda", "Sobre"} },
  ["back"] = { mode = "vestir", slots = {"Back", "About", "Espalda", "Sobre"} },

  ["cintura"] = { mode = "vestir", slots = {"Waist", "Cintura"} },
  ["en la cintura"] = { mode = "vestir", slots = {"Waist", "Cintura"} },
  ["waist"] = { mode = "vestir", slots = {"Waist", "Cintura"} },

  ["antebrazo"] = { mode = "vestir", slots = {"Wrist", "Muñeca", "Muneca", "Antebrazo"} },
  ["en antebrazo izq"] = { mode = "vestir", slots = {"Wrist", "Muñeca", "Muneca", "Antebrazo"} },
  ["en antebrazo der"] = { mode = "vestir", slots = {"Wrist", "Muñeca", "Muneca", "Antebrazo"} },
  ["muneca"] = { mode = "vestir", slots = {"Wrist", "Muñeca", "Muneca", "Antebrazo"} },
  ["muñeca"] = { mode = "vestir", slots = {"Wrist", "Muñeca", "Muneca", "Antebrazo"} },
  ["wrist"] = { mode = "vestir", slots = {"Wrist", "Muñeca", "Muneca", "Antebrazo"} },

  ["arma"] = { mode = "vestir", slots = {"Wield", "Blandir", "Blandiendo"} },
  ["blandiendo"] = { mode = "vestir", slots = {"Wield", "Blandir", "Blandiendo"} },
  ["wield"] = { mode = "vestir", slots = {"Wield", "Blandir", "Blandiendo"} },

  ["sostener"] = { mode = "vestir", slots = {"Hold", "Sostener", "Sosteniendo"} },
  ["sosteniendo"] = { mode = "vestir", slots = {"Hold", "Sostener", "Sosteniendo"} },
  ["hold"] = { mode = "vestir", slots = {"Hold", "Sostener", "Sosteniendo"} },

  ["flotando"] = { mode = "vestir", slots = {"Float", "Flotando", "Flotar"} },
  ["flotando cerca"] = { mode = "vestir", slots = {"Float", "Flotando", "Flotar"} },
  ["flotante"] = { mode = "vestir", slots = {"Float", "Flotando", "Flotar"} },
  ["float"] = { mode = "vestir", slots = {"Float", "Flotando", "Flotar"} },

  ["rear feet"] = { mode = "vestir", slots = {"Rear Feet"} }
}

function eqInv.getSlotAlias(q)
  return eqInv.slotAliases[eqInv.norm(q)]
end

function eqInv.isIgnoredMissingSlot(slot)
  return eqInv.config.ignoredMissingSlots[eqInv.norm(slot)] == true
end

-- ------------------------------------------------------------
-- DB
-- ------------------------------------------------------------
function eqInv.ensureDB()
  eqInv.db = db:create(eqInv.config.dbName, {
    meta = {
      key = "",
      value = "",
      _unique = {"key"},
      _violations = "REPLACE"
    },
    items = {
      vnum = 0,
      nombre = "",
      desc_corta = "",
      tipo = "",
      extra_flags = "",
      peso = 0,
      valor = 0,
      nivel = 0,
      material = "",
      area = "",
      vestir_text = "",
      spells_text = "",
      afectaciones_text = "",
      instancias_text = "",
      set_name = "",
      extra_data = "",
      raw_json = "",
      search_text = "",
      _unique = {"vnum"},
      _index = {"nombre", "tipo", "nivel", "area", "set_name"},
      _violations = "REPLACE"
    },
    vestir = {
      vnum = 0,
      slot = "",
      slot_norm = "",
      nombre = "",
      nivel = 0,
      tipo = "",
      _index = {"slot_norm", "nivel", "vnum"}
    },
    flags = {
      vnum = 0,
      flag = "",
      flag_norm = "",
      nombre = "",
      nivel = 0,
      _index = {"flag_norm", "nivel", "vnum"}
    },
    spells = {
      vnum = 0,
      spell = "",
      spell_norm = "",
      nombre = "",
      nivel = 0,
      _index = {"spell_norm", "nivel", "vnum"}
    },
    affects = {
      vnum = 0,
      location = "",
      location_norm = "",
      modifier = 0,
      nombre = "",
      nivel = 0,
      _index = {"location_norm", "nivel", "vnum"}
    },
    instances = {
      vnum = 0,
      source = "",
      source_norm = "",
      nombre = "",
      nivel = 0,
      area = "",
      _index = {"source_norm", "area", "vnum"}
    }
  }, true)
  return eqInv.db
end

function eqInv.clearDB()
  eqInv.ensureDB()
  for _, sheet in ipairs({"items", "vestir", "flags", "spells", "affects", "instances", "meta"}) do
    local ok, err = db:delete(eqInv.db[sheet], true)
    if ok == nil then eqInv.warn("No se pudo limpiar " .. sheet .. ": " .. tostring(err)) end
  end
end

function eqInv.setMeta(key, value)
  eqInv.ensureDB()
  db:add(eqInv.db.meta, { key = tostring(key), value = tostring(value or "") })
end

function eqInv.getMeta(key)
  eqInv.ensureDB()
  local rows = db:fetch(eqInv.db.meta, db:eq(eqInv.db.meta.key, tostring(key)))
  if rows and rows[1] then return rows[1].value end
  return nil
end

-- ------------------------------------------------------------
-- Transformacion de items
-- ------------------------------------------------------------
function eqInv.dbItemRow(row)
  -- Mudlet db:add solo acepta columnas definidas en el schema.
  -- Los campos internos con prefijo _ son solo cache/memoria y no deben insertarse.
  return {
    vnum = row.vnum,
    nombre = row.nombre,
    desc_corta = row.desc_corta,
    tipo = row.tipo,
    extra_flags = row.extra_flags,
    peso = row.peso,
    valor = row.valor,
    nivel = row.nivel,
    material = row.material,
    area = row.area,
    vestir_text = row.vestir_text,
    spells_text = row.spells_text,
    afectaciones_text = row.afectaciones_text,
    instancias_text = row.instancias_text,
    set_name = row.set_name,
    extra_data = row.extra_data,
    raw_json = row.raw_json,
    search_text = row.search_text
  }
end

function eqInv.itemToRow(item)
  local vestirText = eqInv.join(item.Vestir or {}, ", ")
  local spellsText = eqInv.formatSpells(item.Spells)
  local affectsText = eqInv.formatAffects(item.Afectaciones)
  local instancesText = eqInv.formatInstances(item.Instancia_Activa)
  local extraData = eqInv.safeString(item.Extra_Data)
  local setName = eqInv.safeString(item.Set)

  local raw = ""
  local ok, encoded = pcall(yajl.to_string, item)
  if ok and encoded then raw = encoded end

  local row = {
    vnum = tonumber(item.VNUM) or 0,
    nombre = eqInv.safeString(item.Nombre),
    desc_corta = eqInv.safeString(item.Descripcion_Corta),
    tipo = eqInv.safeString(item.Tipo),
    extra_flags = eqInv.safeString(item.Extra_Flags),
    peso = tonumber(item.Peso) or 0,
    valor = tonumber(item.Valor) or 0,
    nivel = tonumber(item.Nivel) or 0,
    material = eqInv.safeString(item.Material),
    area = eqInv.safeString(item.Area_Definicion),
    vestir_text = vestirText,
    spells_text = spellsText,
    afectaciones_text = affectsText,
    instancias_text = instancesText,
    set_name = setName,
    extra_data = extraData,
    raw_json = raw
  }

  row.search_text = eqInv.norm(table.concat({
    row.nombre, row.desc_corta, row.tipo, row.extra_flags, row.material,
    row.area, row.vestir_text, row.spells_text, row.afectaciones_text,
    row.instancias_text, row.set_name, row.extra_data
  }, " "))

  row._vestir_norm = eqInv.norm(row.vestir_text)
  row._tipo_norm = eqInv.norm(row.tipo)
  row._flags_norm = eqInv.norm(row.extra_flags)
  row._set_norm = eqInv.norm(row.set_name)
  return row
end

function eqInv.addCacheItem(row)
  row._vestir_norm = row._vestir_norm or eqInv.norm(row.vestir_text)
  row._tipo_norm = row._tipo_norm or eqInv.norm(row.tipo)
  row._flags_norm = row._flags_norm or eqInv.norm(row.extra_flags)
  row._set_norm = row._set_norm or eqInv.norm(row.set_name)
  row.search_text = row.search_text or eqInv.norm(table.concat({
    row.nombre, row.desc_corta, row.tipo, row.extra_flags, row.area,
    row.vestir_text, row.spells_text, row.afectaciones_text,
    row.instancias_text, row.set_name, row.extra_data
  }, " "))

  table.insert(eqInv.cache.items, row)
  eqInv.cache.byVnum[row.vnum] = row
  eqInv.cache.typeCounts[row.tipo] = (eqInv.cache.typeCounts[row.tipo] or 0) + 1
  if row.set_name ~= "" then eqInv.cache.setCounts[row.set_name] = (eqInv.cache.setCounts[row.set_name] or 0) + 1 end

  for slot in row.vestir_text:gmatch("[^,]+") do
    slot = eqInv.trim(slot)
    if slot ~= "" then eqInv.cache.wearCounts[slot] = (eqInv.cache.wearCounts[slot] or 0) + 1 end
  end

  for _, flag in ipairs(eqInv.flagsToList(row.extra_flags)) do
    eqInv.cache.flagCounts[flag] = (eqInv.cache.flagCounts[flag] or 0) + 1
  end
end

function eqInv.resetCache()
  eqInv.cache = {
    ready = false,
    items = {},
    byVnum = {},
    typeCounts = {},
    wearCounts = {},
    flagCounts = {},
    setCounts = {},
    loadedAt = nil,
    lastUrl = nil
  }
end

function eqInv.sortCache()
  table.sort(eqInv.cache.items, function(a, b)
    if (a.nivel or 0) == (b.nivel or 0) then return (a.nombre or "") < (b.nombre or "") end
    return (a.nivel or 0) > (b.nivel or 0)
  end)
end

function eqInv.loadCacheFromDB()
  eqInv.ensureDB()
  eqInv.resetCache()
  local rows = db:fetch(eqInv.db.items)
  for _, row in ipairs(rows or {}) do eqInv.addCacheItem(row) end
  eqInv.sortCache()
  eqInv.cache.ready = #eqInv.cache.items > 0
  eqInv.cache.loadedAt = eqInv.getMeta("loaded_at")
  eqInv.cache.lastUrl = eqInv.getMeta("last_url")
  if eqInv.cache.ready then
    eqInv.echo("Cache cargado desde DB: " .. tostring(#eqInv.cache.items) .. " items.")
  else
    eqInv.warn("DB vacia. Usa: eqsync")
  end
end

-- ------------------------------------------------------------
-- Descarga e importacion
-- ------------------------------------------------------------
function eqInv.sync(url)
  url = eqInv.trim(url)
  if url == "" then url = eqInv.config.defaultUrl end

  eqInv.ensureDB()
  eqInv.downloadUrl = url
  eqInv.downloadPath = getMudletHomeDir() .. "/petria_inventario_new.json"

  eqInv.echo("Descargando inventario: " .. url)
  eqInv.echo("Progreso: 0% descarga iniciada")
  downloadFile(eqInv.downloadPath, url)
end

function eqInv.onDownloadDone(_, filename)
  if filename ~= eqInv.downloadPath then return end
  eqInv.echo("Progreso: 10% descarga completada, leyendo JSON...")

  local f, err = io.open(filename, "r")
  if not f then
    eqInv.err("No pude abrir el archivo descargado: " .. tostring(err))
    return
  end
  local content = f:read("*a")
  f:close()

  local ok, data = pcall(yajl.to_value, content)
  if not ok or type(data) ~= "table" then
    eqInv.err("No pude parsear el JSON. Revisa URL o formato.")
    return
  end

  local items = data
  if not eqInv.isArray(items) then
    items = data.items or data.Items or data.data or data.Data or {}
  end
  if type(items) ~= "table" or #items == 0 then
    eqInv.err("El JSON no contiene una lista de items reconocible.")
    return
  end

  eqInv.startImport(items, eqInv.downloadUrl)
end

function eqInv.onDownloadError(_, ...)
  local args = {...}
  eqInv.err("Error descargando inventario: " .. table.concat(args, " | "))
end

function eqInv.registerDownloadHandlers()
  if eqInv.handlers.downloadDone then eqInv.safeKillEventHandler(eqInv.handlers.downloadDone) end
  if eqInv.handlers.downloadError then eqInv.safeKillEventHandler(eqInv.handlers.downloadError) end
  eqInv.handlers.downloadDone = registerAnonymousEventHandler("sysDownloadDone", eqInv.onDownloadDone)
  eqInv.handlers.downloadError = registerAnonymousEventHandler("sysDownloadError", eqInv.onDownloadError)
end

function eqInv.startImport(items, url)
  eqInv.echo("Progreso: 15% limpiando DB anterior...")
  eqInv.clearDB()
  eqInv.resetCache()

  eqInv.importState = {
    items = items,
    url = url,
    i = 1,
    total = #items,
    lastPct = 15,
    inserted = 0
  }

  eqInv.echo("Progreso: 20% importando e indexando " .. tostring(#items) .. " items...")
  eqInv.timers.importChunk = tempTimer(0, eqInv.importChunk)
end

function eqInv.indexListsForItem(item, row)
  for _, slot in ipairs(item.Vestir or {}) do
    slot = eqInv.safeString(slot)
    if slot ~= "" then
      db:add(eqInv.db.vestir, {
        vnum = row.vnum,
        slot = slot,
        slot_norm = eqInv.norm(slot),
        nombre = row.nombre,
        nivel = row.nivel,
        tipo = row.tipo
      })
    end
  end

  for _, flag in ipairs(eqInv.flagsToList(item.Extra_Flags)) do
    db:add(eqInv.db.flags, {
      vnum = row.vnum,
      flag = flag,
      flag_norm = eqInv.norm(flag),
      nombre = row.nombre,
      nivel = row.nivel
    })
  end

  if type(item.Spells) == "table" then
    for _, sp in ipairs(item.Spells or {}) do
      local spell = ""
      if type(sp) == "table" then spell = eqInv.safeString(sp.Spell or sp.spell or sp.Name or sp.name or sp[1])
      else spell = eqInv.safeString(sp) end
      if spell ~= "" then
        db:add(eqInv.db.spells, {
          vnum = row.vnum,
          spell = spell,
          spell_norm = eqInv.norm(spell),
          nombre = row.nombre,
          nivel = row.nivel
        })
      end
    end
  elseif eqInv.safeString(item.Spells) ~= "" then
    local spell = eqInv.safeString(item.Spells)
    db:add(eqInv.db.spells, {
      vnum = row.vnum,
      spell = spell,
      spell_norm = eqInv.norm(spell),
      nombre = row.nombre,
      nivel = row.nivel
    })
  end

  for _, a in ipairs(item.Afectaciones or {}) do
    if type(a) == "table" then
      local loc = eqInv.safeString(a.Location or a.location or a.loc)
      local mod = tonumber(a.Modifier or a.modifier or a.mod) or 0
      if loc ~= "" then
        db:add(eqInv.db.affects, {
          vnum = row.vnum,
          location = loc,
          location_norm = eqInv.norm(loc),
          modifier = mod,
          nombre = row.nombre,
          nivel = row.nivel
        })
      end
    end
  end

  for _, inst in ipairs(item.Instancia_Activa or {}) do
    if type(inst) == "table" then
      for _, v in pairs(inst) do
        local src = eqInv.safeString(v)
        if src ~= "" then
          db:add(eqInv.db.instances, {
            vnum = row.vnum,
            source = src,
            source_norm = eqInv.norm(src),
            nombre = row.nombre,
            nivel = row.nivel,
            area = row.area
          })
        end
      end
    end
  end
end

function eqInv.importChunk()
  local st = eqInv.importState
  if not st then return end

  local endAt = math.min(st.total, st.i + eqInv.config.importChunkSize - 1)
  for idx = st.i, endAt do
    local item = st.items[idx]
    if type(item) == "table" then
      local row = eqInv.itemToRow(item)
      local ok, err = db:add(eqInv.db.items, eqInv.dbItemRow(row))
      if ok == nil then
        eqInv.warn("No se pudo insertar VNUM " .. tostring(row.vnum) .. ": " .. tostring(err))
      else
        eqInv.indexListsForItem(item, row)
        eqInv.addCacheItem(row)
        st.inserted = st.inserted + 1
      end
    end
  end

  st.i = endAt + 1
  local pct = 20 + math.floor((st.i - 1) / st.total * 75)
  if pct >= st.lastPct + 5 then
    st.lastPct = pct
    eqInv.echo("Progreso: " .. tostring(math.min(pct, 95)) .. "%")
  end

  if st.i <= st.total then
    eqInv.timers.importChunk = tempTimer(0, eqInv.importChunk)
    return
  end

  eqInv.timers.importChunk = nil

  eqInv.sortCache()
  eqInv.cache.ready = true
  eqInv.cache.loadedAt = os.date("%Y-%m-%d %H:%M:%S")
  eqInv.cache.lastUrl = st.url
  eqInv.setMeta("loaded_at", eqInv.cache.loadedAt)
  eqInv.setMeta("last_url", st.url)
  eqInv.setMeta("count", tostring(st.inserted))

  eqInv.importState = nil
  eqInv.echo("Progreso: 100% completado. Items cargados: " .. tostring(st.inserted))
  eqInv.echo("Usa: eqlista help  |  eqbusca <texto>")
end

-- ------------------------------------------------------------
-- Busqueda y filtros
-- ------------------------------------------------------------
function eqInv.ensureReady()
  if eqInv.cache.ready then return true end
  eqInv.loadCacheFromDB()
  if eqInv.cache.ready then return true end
  eqInv.warn("Primero carga el inventario con: eqsync")
  return false
end

function eqInv.itemMatchesWearFilter(item, filter)
  filter = eqInv.trim(filter)
  if filter == "" then return true end

  local alias = eqInv.getSlotAlias(filter)
  if alias then
    if alias.mode == "tipo" then
      return item._tipo_norm == eqInv.norm(alias.tipo)
    end
    if alias.mode == "vestir" then
      local vt = item._vestir_norm or eqInv.norm(item.vestir_text)
      for _, slot in ipairs(alias.slots or {}) do
        if vt:find(eqInv.norm(slot), 1, true) then return true end
      end
      return false
    end
  end

  local f = eqInv.norm(filter)
  return (item._vestir_norm or ""):find(f, 1, true) ~= nil
      or (item._tipo_norm or "") == f
      or (item.search_text or ""):find(f, 1, true) ~= nil
end

function eqInv.itemInLevelRange(item, minLevel, maxLevel)
  local lvl = tonumber(item.nivel) or 0
  if minLevel and lvl < minLevel then return false end
  if maxLevel and lvl > maxLevel then return false end
  return true
end

function eqInv.findItems(opts)
  opts = opts or {}
  local results = {}
  local query = eqInv.trim(opts.query or "")
  local wear = eqInv.trim(opts.wear or "")
  local setQuery = eqInv.trim(opts.setQuery or "")

  for _, item in ipairs(eqInv.cache.items) do
    local ok = true

    if opts.minLevel or opts.maxLevel then ok = ok and eqInv.itemInLevelRange(item, opts.minLevel, opts.maxLevel) end
    if query ~= "" then ok = ok and eqInv.containsText((item.nombre or "") .. " " .. (item.desc_corta or ""), query) end
    if wear ~= "" then ok = ok and eqInv.itemMatchesWearFilter(item, wear) end
    if setQuery ~= "" then ok = ok and item.set_name ~= "" and eqInv.containsText(item.set_name, setQuery) end

    if ok then table.insert(results, item) end
  end

  table.sort(results, function(a, b)
    if (a.nivel or 0) == (b.nivel or 0) then return (a.nombre or "") < (b.nombre or "") end
    return (a.nivel or 0) > (b.nivel or 0)
  end)

  return results
end

function eqInv.itemDuplicateSignature(item)
  -- Firma visual para evitar sugerencias repetidas.
  -- No usa VNUM porque el objetivo es colapsar clones visualmente identicos.
  return table.concat({
    eqInv.norm(item.nombre or ""),
    eqInv.norm(item.tipo or ""),
    tostring(item.nivel or 0),
    tostring(item.peso or 0),
    eqInv.norm(item.afectaciones_text or ""),
    eqInv.norm(eqInv.formatLugar(item))
  }, "|")
end

function eqInv.dedupeSuggestionList(results)
  local seen, out = {}, {}
  for _, item in ipairs(results or {}) do
    local sig = eqInv.itemDuplicateSignature(item)
    if not seen[sig] then
      seen[sig] = true
      table.insert(out, item)
    end
  end
  return out, #results - #out
end

function eqInv.findTopSuggestionsForSlot(slot, maxLevel, limit)
  limit = limit or eqInv.config.missingSlotLimit or 3
  maxLevel = tonumber(maxLevel)

  -- Toma candidatos <= nivel y los ordena por recomendacion del modo actual.
  -- Si no hay del nivel actual, aparecen automaticamente niveles inferiores.
  local results = eqInv.findItems({ minLevel = 0, maxLevel = maxLevel, wear = slot })
  eqInv.sortByRecommendation(results, eqInv.config.recommendMode)

  local deduped, duplicatesRemoved = eqInv.dedupeSuggestionList(results)

  local out = {}
  for i = 1, math.min(limit, #deduped) do table.insert(out, deduped[i]) end

  return out, #deduped, duplicatesRemoved
end

function eqInv.formatItem(item)
  local flags = item.extra_flags or ""
  local afecta = item.afectaciones_text or ""
  local lugar = eqInv.formatLugar(item)

  if afecta == "" then afecta = "Ninguna" end

  local line = string.format(
    "Nivel %s (peso %s), %s, flags [%s], afecta: %s; Se encuentra en: %s",
    tostring(item.nivel or 0), tostring(item.peso or 0), tostring(item.nombre or "?"), flags, afecta, lugar
  )

  return line .. "."
end


-- ------------------------------------------------------------
-- Recomendacion heuristica de items
-- ------------------------------------------------------------
function eqInv.getRawItem(item)
  if item._rawItem ~= nil then return item._rawItem end
  item._rawItem = false

  if item.raw_json and item.raw_json ~= "" then
    local ok, raw = pcall(yajl.to_value, item.raw_json)
    if ok and type(raw) == "table" then
      item._rawItem = raw
      return raw
    end
  end

  return nil
end

function eqInv.normalizedAffectName(name)
  local n = eqInv.norm(name)
  local map = {
    ["fue"] = "fuerza",
    ["str"] = "fuerza",
    ["strength"] = "fuerza",
    ["fuerza"] = "fuerza",

    ["int"] = "inteligencia",
    ["intelligence"] = "inteligencia",
    ["inteligencia"] = "inteligencia",

    ["sab"] = "sabiduria",
    ["wis"] = "sabiduria",
    ["wisdom"] = "sabiduria",
    ["sabiduria"] = "sabiduria",

    ["des"] = "destreza",
    ["dex"] = "destreza",
    ["dexterity"] = "destreza",
    ["destreza"] = "destreza",

    ["con"] = "constitucion",
    ["constitution"] = "constitucion",
    ["constitucion"] = "constitucion",
    ["constitución"] = "constitucion",

    ["hp"] = "hp",
    ["hit points"] = "hp",
    ["vida"] = "hp",
    ["puntos de vida"] = "hp",

    ["mana"] = "mana",
    ["hitroll"] = "hitroll",
    ["hit roll"] = "hitroll",
    ["damroll"] = "damroll",
    ["dam roll"] = "damroll",

    ["spellpower"] = "spellpower",
    ["spell power"] = "spellpower",
    ["sp"] = "spellpower",

    ["healpower"] = "healpower",
    ["heal power"] = "healpower",
    ["hsp"] = "healpower",
    ["hpwr"] = "healpower",

    ["saves"] = "saves",
    ["save"] = "saves",
    ["saving spell"] = "saves",
    ["save vs spell"] = "saves",
    ["salvacion"] = "saves",
    ["salvación"] = "saves"
  }
  return map[n] or n
end

function eqInv.collectItemStats(item)
  local raw = eqInv.getRawItem(item) or {}
  local stats = {
    fuerza = 0,
    inteligencia = 0,
    sabiduria = 0,
    destreza = 0,
    constitucion = 0,
    hp = 0,
    mana = 0,
    hitroll = 0,
    damroll = 0,
    spellpower = 0,
    healpower = 0,
    saves = 0,
    armor = 0,
    resistCount = 0,
    immuneCount = 0,
    vulnCount = 0,
    flags = eqInv.norm(item.extra_flags or ""),
    tipo = eqInv.norm(item.tipo or "")
  }

  for _, a in ipairs(raw.Afectaciones or {}) do
    if type(a) == "table" then
      local loc = eqInv.normalizedAffectName(a.Location or a.location or a.loc or "")
      local mod = tonumber(a.Modifier or a.modifier or a.mod) or 0
      if stats[loc] ~= nil then
        stats[loc] = stats[loc] + mod
      end
    end
  end

  local armor = raw.Armor_Protections
  if type(armor) == "table" then
    for _, v in pairs(armor) do
      stats.armor = stats.armor + (tonumber(v) or 0)
    end
  end

  if type(raw.Resistencias) == "table" then stats.resistCount = #raw.Resistencias end
  if type(raw.Inmunidades) == "table" then stats.immuneCount = #raw.Inmunidades end
  if type(raw.Vulnerabilidades) == "table" then stats.vulnCount = #raw.Vulnerabilidades end

  return stats
end

function eqInv.scoreSaves(modifier, weight)
  -- En Petria los saves/protecciones son mejores mientras mas negativos.
  -- Por eso un modifier negativo suma, uno positivo resta.
  modifier = tonumber(modifier) or 0
  weight = tonumber(weight) or 1
  return (-modifier) * weight
end

eqInv.powerPercentThresholds = {
  [0]=0, [1]=8, [2]=23, [3]=39, [4]=55, [5]=71, [6]=88, [7]=105, [8]=122, [9]=140,
  [10]=158, [11]=176, [12]=195, [13]=215, [14]=235, [15]=255, [16]=276, [17]=297,
  [18]=319, [19]=341, [20]=364, [21]=387, [22]=411, [23]=436, [24]=461, [25]=487,
  [26]=514, [27]=541, [28]=569, [29]=598, [30]=628, [31]=659, [32]=690, [33]=723,
  [34]=787, [35]=892, [36]=997, [37]=1108, [38]=1219, [39]=1339, [40]=1459
}

function eqInv.powerPctFromPoints(points)
  points = tonumber(points) or 0
  local pct = 0
  for p = 0, 40 do
    local req = eqInv.powerPercentThresholds[p]
    if req and points >= req then pct = p end
  end
  return pct
end

function eqInv.powerPointsForPct(pct)
  pct = tonumber(pct) or 0
  if pct < 0 then pct = 0 end
  if pct > 40 then pct = 40 end
  return eqInv.powerPercentThresholds[math.floor(pct)] or 0
end

function eqInv.powerLevelCapPct(level)
  level = tonumber(level) or 0
  if level <= 5 then return 9 end
  if level <= 10 then return 10 end
  if level <= 14 then return 11 end
  if level <= 19 then return 12 end
  if level <= 23 then return 13 end
  if level <= 28 then return 14 end
  if level <= 33 then return 15 end
  if level <= 37 then return 16 end
  if level <= 42 then return 17 end
  if level <= 46 then return 18 end
  if level <= 51 then return 19 end
  if level <= 55 then return 20 end
  if level <= 60 then return 21 end
  if level <= 64 then return 22 end
  if level <= 69 then return 23 end
  if level <= 74 then return 24 end
  if level <= 78 then return 25 end
  if level <= 83 then return 26 end
  if level <= 87 then return 27 end
  if level <= 92 then return 28 end
  if level <= 97 then return 29 end
  if level <= 101 then return 30 end
  if level <= 106 then return 31 end
  if level <= 110 then return 32 end
  return 33
end

function eqInv.itemPowerRawCap(level)
  level = tonumber(level) or 0
  if level <= 5 then return 7 end
  if level <= 10 then return 8 end
  if level <= 14 then return 9 end
  if level <= 19 then return 10 end
  if level <= 23 then return 11 end
  if level <= 28 then return 12 end
  if level <= 33 then return 13 end
  if level <= 37 then return 14 end
  if level <= 42 then return 15 end
  if level <= 46 then return 16 end
  if level <= 51 then return 17 end
  if level <= 55 then return 18 end
  if level <= 60 then return 19 end
  if level <= 64 then return 21 end
  if level <= 69 then return 22 end
  if level <= 74 then return 23 end
  if level <= 78 then return 25 end
  if level <= 83 then return 26 end
  if level <= 87 then return 27 end
  if level <= 92 then return 29 end
  if level <= 97 then return 30 end
  if level <= 101 then return 32 end
  if level <= 106 then return 33 end
  if level <= 110 then return 35 end
  return 36
end

function eqInv.effectiveItemPower(rawPower, itemLevel)
  rawPower = tonumber(rawPower) or 0
  if rawPower <= 0 then return 0 end
  local cap = eqInv.itemPowerRawCap(itemLevel)
  if rawPower > cap then return cap end
  return rawPower
end

function eqInv.powerSummaryForLevel(level)
  level = tonumber(level)
  if not level then
    level = eqInv.getGMCPLevel()
  end
  level = tonumber(level) or 0
  local capPct = eqInv.powerLevelCapPct(level)
  local capPoints = eqInv.powerPointsForPct(capPct)
  local itemCap = eqInv.itemPowerRawCap(level)
  return level, capPct, capPoints, itemCap
end

function eqInv.scoreItem(item, mode)
  mode = eqInv.norm(mode or eqInv.config.recommendMode or "subir")
  if mode == "level" or mode == "levelear" or mode == "xp" or mode == "exp" then mode = "subir" end
  if mode == "pvp" then mode = "pk" end
  if mode == "damage" or mode == "dano" or mode == "daño" then mode = "danio" end
  if mode == "tanque" or mode == "tank" then mode = "defensa" end
  if mode == "mago" or mode == "hechicero" or mode == "spell" or mode == "spells" then mode = "caster" end
  if mode == "heal" or mode == "healer" or mode == "curar" or mode == "sanar" or mode == "hsp" then mode = "healer" end

  local s = eqInv.collectItemStats(item)
  local effSP = eqInv.effectiveItemPower(s.spellpower, item.nivel)
  local effHSP = eqInv.effectiveItemPower(s.healpower, item.nivel)
  local spPct = eqInv.powerPctFromPoints(effSP)
  local hspPct = eqInv.powerPctFromPoints(effHSP)
  local score = 0

  if mode == "pk" then
    score = score
      + s.damroll * 8
      + s.hitroll * 7
      + effSP * 4
      + spPct * 10
      + effHSP * 2
      + s.destreza * 6
      + s.constitucion * 5
      + math.floor(s.hp / 10) * 3
      + eqInv.scoreSaves(s.saves, 5)
      + math.floor(s.armor / 40)
      + s.resistCount * 8
      + s.immuneCount * 14
      - s.vulnCount * 10
  elseif mode == "defensa" then
    score = score
      + s.constitucion * 8
      + math.floor(s.hp / 10) * 5
      + effHSP * 3
      + hspPct * 8
      + math.floor(s.armor / 20)
      + eqInv.scoreSaves(s.saves, 7)
      + s.resistCount * 10
      + s.immuneCount * 18
      - s.vulnCount * 12
  elseif mode == "caster" then
    score = score
      + s.inteligencia * 8
      + s.sabiduria * 6
      + math.floor(s.mana / 10) * 5
      + effSP * 8
      + spPct * 18
      + effHSP * 2
      + s.constitucion * 3
      + math.floor(s.hp / 15) * 2
      + eqInv.scoreSaves(s.saves, 4)
      + s.resistCount * 5
  elseif mode == "healer" then
    score = score
      + s.sabiduria * 9
      + s.inteligencia * 5
      + math.floor(s.mana / 10) * 5
      + effHSP * 9
      + hspPct * 20
      + effSP * 2
      + s.constitucion * 4
      + math.floor(s.hp / 12) * 3
      + eqInv.scoreSaves(s.saves, 4)
      + s.resistCount * 6
  elseif mode == "danio" then
    score = score
      + s.damroll * 10
      + s.hitroll * 8
      + effSP * 5
      + spPct * 12
      + s.fuerza * 7
      + s.destreza * 6
      + math.floor(s.hp / 20)
  elseif mode == "balance" or mode == "balanced" then
    score = score
      + s.fuerza * 4
      + s.inteligencia * 3
      + s.sabiduria * 4
      + s.destreza * 4
      + s.constitucion * 5
      + math.floor(s.hp / 12) * 3
      + math.floor(s.mana / 15) * 2
      + effSP * 4
      + effHSP * 4
      + spPct * 8
      + hspPct * 8
      + s.hitroll * 4
      + s.damroll * 4
      + eqInv.scoreSaves(s.saves, 4)
      + math.floor(s.armor / 35)
      + s.resistCount * 6
      + s.immuneCount * 10
      - s.vulnCount * 8
  else
    -- subir de nivel: supervivencia + crecimiento futuro + acierto/daño razonable.
    score = score
      + s.constitucion * 8
      + s.sabiduria * 7
      + s.inteligencia * 6
      + s.destreza * 4
      + s.fuerza * 3
      + math.floor(s.hp / 10) * 4
      + math.floor(s.mana / 10) * 3
      + effSP * 3
      + effHSP * 3
      + spPct * 6
      + hspPct * 6
      + s.hitroll * 4
      + s.damroll * 4
      + eqInv.scoreSaves(s.saves, 3)
      + math.floor(s.armor / 50)
      + s.resistCount * 5
      + s.immuneCount * 8
      - s.vulnCount * 6
  end

  if s.flags:find("anti", 1, true) then score = score - 3 end
  if s.flags:find("nodrop", 1, true) then score = score - 2 end

  return math.floor(score), mode
end

function eqInv.compareItemsForMode(a, b, mode)
  local sa = eqInv.scoreItem(a, mode)
  local sb = eqInv.scoreItem(b, mode)

  if sa == sb then
    if (a.nivel or 0) == (b.nivel or 0) then return (a.nombre or "") < (b.nombre or "") end
    return (a.nivel or 0) > (b.nivel or 0)
  end

  return sa > sb
end

function eqInv.sortByRecommendation(results, mode)
  table.sort(results, function(a, b)
    return eqInv.compareItemsForMode(a, b, mode)
  end)
end

function eqInv.sortByLevel(results)
  table.sort(results, function(a, b)
    if (a.nivel or 0) == (b.nivel or 0) then
      if (a.nombre or "") == (b.nombre or "") then return (a.vnum or 0) < (b.vnum or 0) end
      return (a.nombre or "") < (b.nombre or "")
    end
    return (a.nivel or 0) > (b.nivel or 0)
  end)
end

function eqInv.sortByName(results)
  table.sort(results, function(a, b)
    if eqInv.norm(a.nombre or "") == eqInv.norm(b.nombre or "") then
      if (a.nivel or 0) == (b.nivel or 0) then return (a.vnum or 0) < (b.vnum or 0) end
      return (a.nivel or 0) > (b.nivel or 0)
    end
    return eqInv.norm(a.nombre or "") < eqInv.norm(b.nombre or "")
  end)
end

function eqInv.sortDisplayResults(results)
  local mode = eqInv.norm(eqInv.config.displaySortMode or "nivel")
  if mode == "pts" or mode == "puntos" or mode == "score" then
    eqInv.sortByRecommendation(results, eqInv.config.recommendMode)
  elseif mode == "nombre" or mode == "name" then
    eqInv.sortByName(results)
  else
    eqInv.sortByLevel(results)
  end
end

function eqInv.setDisplaySortMode(mode)
  mode = eqInv.norm(mode or "")
  if mode == "" then
    eqInv.echo("Orden actual: " .. tostring(eqInv.config.displaySortMode or "nivel"))
    echo("Cambiar orden: eqorden nivel | pts | nombre\n")
    return
  end

  if mode == "level" then mode = "nivel" end
  if mode == "puntos" or mode == "score" then mode = "pts" end
  if mode == "name" then mode = "nombre" end

  if mode ~= "nivel" and mode ~= "pts" and mode ~= "nombre" then
    eqInv.warn("Uso: eqorden nivel | pts | nombre")
    return
  end

  eqInv.config.displaySortMode = mode
  eqInv.echo("Orden visual: " .. mode)
end

function eqInv.recommendLabel()
  local mode = eqInv.norm(eqInv.config.recommendMode or "subir")
  if mode == "pk" then return "PK" end
  if mode == "defensa" then return "Defensa" end
  if mode == "caster" then return "Caster/SP" end
  if mode == "healer" then return "Healer/HSP" end
  if mode == "danio" then return "Daño" end
  if mode == "balance" or mode == "balanced" then return "Balance" end
  return "Subir"
end

function eqInv.printModeHint()
  cecho("<grey>Modo:<reset> <white>" .. eqInv.recommendLabel() .. "<reset> <grey>| Orden:<reset> <white>" .. tostring(eqInv.config.displaySortMode or "nivel") .. "<reset> <grey>| cambiar:<reset> eqmodo ... | eqorden nivel|pts|nombre\n")
end

function eqInv.setRecommendMode(mode)
  mode = eqInv.norm(mode or "")
  if mode == "level" or mode == "levelear" or mode == "xp" or mode == "exp" then mode = "subir" end
  if mode == "pvp" then mode = "pk" end
  if mode == "damage" or mode == "dano" or mode == "daño" then mode = "danio" end
  if mode == "tanque" or mode == "tank" then mode = "defensa" end
  if mode == "mago" or mode == "hechicero" or mode == "spell" or mode == "spells" or mode == "sp" then mode = "caster" end
  if mode == "heal" or mode == "healer" or mode == "curar" or mode == "sanar" or mode == "hsp" then mode = "healer" end
  if mode == "balanced" then mode = "balance" end

  local valid = {
    subir = true,
    pk = true,
    defensa = true,
    caster = true,
    healer = true,
    danio = true,
    balance = true
  }

  if not valid[mode] then
    eqInv.warn("Uso: eqmodo subir | pk | defensa | caster | healer | danio | balance")
    return
  end

  eqInv.config.recommendMode = mode
  eqInv.echo("Modo de recomendacion: " .. eqInv.recommendLabel())
end

function eqInv.showPowerInfo(arg)
  arg = eqInv.trim(arg or "")
  local level = tonumber(arg)
  local source = "manual"
  if not level then
    level, source = eqInv.getGMCPLevel()
  end
  if not level then
    eqInv.warn("No pude detectar nivel GMCP. Usa: eqpower 14")
    return
  end

  local lvl, capPct, capPoints, itemCap = eqInv.powerSummaryForLevel(level)
  cecho("<cyan>[EQSearch]<reset> SpellPower/HealPower para nivel " .. tostring(lvl) .. "\n")
  echo("Cap de % por nivel: " .. tostring(capPct) .. "%\n")
  echo("Puntos requeridos para ese cap: " .. tostring(capPoints) .. "\n")
  echo("Tope bruto por objeto de ese nivel: " .. tostring(itemCap) .. " puntos\n")
  echo("Nota: SP aumenta daño de spells de ataque; HSP aumenta curacion/regeneracion/succiones/mana.\n")
end


-- ------------------------------------------------------------
-- Tabla agrupada por Vestir
-- ------------------------------------------------------------
function eqInv.groupLabel(item)
  local vestir = eqInv.trim(item.vestir_text or "")
  if vestir ~= "" then return vestir end
  if (item._tipo_norm or eqInv.norm(item.tipo)) == "light" then return "Luz / Tipo light" end
  return "Sin Vestir"
end

function eqInv.groupOrder(label)
  local n = eqInv.norm(label)
  if n:find("luz", 1, true) or n:find("light", 1, true) then return 10 end
  if n:find("finger", 1, true) or n:find("dedo", 1, true) then return 20 end
  if n:find("neck", 1, true) or n:find("cuello", 1, true) then return 30 end
  if n:find("body", 1, true) or n:find("cuerpo", 1, true) then return 40 end
  if n:find("head", 1, true) or n:find("cabeza", 1, true) then return 50 end
  if n:find("legs", 1, true) or n:find("piernas", 1, true) then return 60 end
  if n:find("feet", 1, true) or n:find("pies", 1, true) then return 70 end
  if n:find("hands", 1, true) or n:find("manos", 1, true) then return 80 end
  if n:find("arms", 1, true) or n:find("brazos", 1, true) then return 90 end
  if n:find("shield", 1, true) or n:find("escudo", 1, true) or n:find("rodela", 1, true) then return 100 end
  if n:find("about", 1, true) or n:find("back", 1, true) or n:find("espalda", 1, true) or n:find("sobre", 1, true) then return 110 end
  if n:find("waist", 1, true) or n:find("cintura", 1, true) then return 120 end
  if n:find("wrist", 1, true) or n:find("muneca", 1, true) or n:find("antebrazo", 1, true) then return 130 end
  if n:find("wield", 1, true) or n:find("blandir", 1, true) then return 140 end
  if n:find("hold", 1, true) or n:find("sostener", 1, true) then return 150 end
  if n:find("float", 1, true) or n:find("flotar", 1, true) or n:find("flotando", 1, true) then return 160 end
  return 999
end

function eqInv.groupResultsByWear(results)
  local map, groups = {}, {}
  for _, item in ipairs(results or {}) do
    local label = eqInv.groupLabel(item)
    if not map[label] then
      map[label] = { label = label, items = {} }
      table.insert(groups, map[label])
    end
    table.insert(map[label].items, item)
  end

  table.sort(groups, function(a, b)
    local oa, ob = eqInv.groupOrder(a.label), eqInv.groupOrder(b.label)
    if oa == ob then return a.label < b.label end
    return oa < ob
  end)

  for _, g in ipairs(groups) do
    eqInv.sortDisplayResults(g.items)
  end

  return groups
end


function eqInv.cleanCellText(s)
  s = eqInv.safeString(s)
  s = s:gsub("\r", " "):gsub("\n", " ")
  s = s:gsub("%s+", " ")
  return eqInv.trim(s)
end

function eqInv.boxWidth()
  return tonumber(eqInv.config.boxWidth) or 84
end

function eqInv.boxContentWidth()
  -- Borde izquierdo: "| " ocupa 2 caracteres.
  -- No usamos borde derecho para evitar descuadre visual por Unicode, colores o wrap de Mudlet.
  return eqInv.boxWidth() - 2
end

function eqInv.boxLine(ch)
  ch = ch or "-"
  return "+" .. string.rep(ch, eqInv.boxWidth() - 1)
end

function eqInv.boxTextLine(text)
  text = eqInv.cleanCellText(text)
  return "| " .. text
end

function eqInv.wrapText(text, width)
  text = eqInv.cleanCellText(text)
  width = tonumber(width) or 80
  local lines = {}

  if text == "" then return { "" } end

  while #text > width do
    local cut = width
    local sub = text:sub(1, width)
    local lastSpace = sub:match("^.*()%s+")
    if lastSpace and lastSpace > 20 then
      cut = lastSpace - 1
    end
    table.insert(lines, eqInv.trim(text:sub(1, cut)))
    text = eqInv.trim(text:sub(cut + 1))
  end

  if text ~= "" then table.insert(lines, text) end
  return lines
end

function eqInv.printBoxWrapped(label, text)
  local prefix = label .. ": "
  local width = eqInv.boxContentWidth() - #prefix
  if width < 24 then width = eqInv.boxContentWidth() end

  local lines = eqInv.wrapText(text, width)
  if #lines == 0 then lines = { "" } end

  eqInv.out(eqInv.boxTextLine(prefix .. lines[1]), eqInv.config.baseTextColor)

  if #lines > 1 then
    local pad = string.rep(" ", #prefix)
    for i = 2, #lines do
      eqInv.out(eqInv.boxTextLine(pad .. lines[i]), eqInv.config.baseTextColor)
    end
  end
end

function eqInv.itemHeaderParts(item)
  local nivel = tostring(item.nivel or 0)
  local peso = tostring(item.peso or 0)
  local pts = tostring(eqInv.scoreItem(item, eqInv.config.recommendMode))
  local tipo = eqInv.cleanCellText(item.tipo or "")
  local vnum = tostring(item.vnum or "?")

  return "VNUM " .. vnum .. " | Nivel " .. nivel .. " | Peso " .. peso .. " | Pts " .. pts .. " | Tipo " .. tipo
end

function eqInv.rawItemTable(item)
  if type(item) ~= "table" then return {} end
  if type(item._raw_table) == "table" then return item._raw_table end

  local raw = item.raw_json or ""
  if raw ~= "" and yajl and yajl.to_value then
    local ok, decoded = pcall(yajl.to_value, raw)
    if ok and type(decoded) == "table" then
      item._raw_table = decoded
      return decoded
    end
  end

  return {}
end

function eqInv.formatArmorProtections(prot)
  if type(prot) ~= "table" then return "" end
  local out = {}
  local order = {
    { "Pierce", "Pierce" },
    { "Blunt", "Blunt" },
    { "Slash", "Slash" },
    { "Magic", "Magic" }
  }

  for _, pair in ipairs(order) do
    local key, label = pair[1], pair[2]
    local v = prot[key] or prot[key:lower()]
    if v ~= nil then table.insert(out, label .. " " .. tostring(v)) end
  end

  return table.concat(out, ", ")
end

function eqInv.formatExtraDataDetails(extra)
  if type(extra) ~= "table" then return "" end

  local out = {}

  local weaponType = extra["Weapon Type"] or extra.weaponType or extra.weapon_type
  local weaponFlags = extra["Weapon Flags"] or extra.weaponFlags or extra.weapon_flags
  local cargas = extra["Cargas"] or extra.cargas or extra.charges
  local spell = extra["Spell"] or extra.spell

  if weaponType ~= nil then table.insert(out, "Weapon Type: " .. eqInv.safeString(weaponType)) end
  if weaponFlags ~= nil then table.insert(out, "Weapon Flags: " .. eqInv.safeString(weaponFlags)) end
  if cargas ~= nil then table.insert(out, "Cargas: " .. eqInv.safeString(cargas)) end
  if spell ~= nil then table.insert(out, "Spell: " .. eqInv.safeString(spell)) end

  local known = {
    ["Weapon Type"] = true,
    ["Weapon Flags"] = true,
    ["Cargas"] = true,
    ["Spell"] = true,
    weaponType = true,
    weaponFlags = true,
    weapon_type = true,
    weapon_flags = true,
    cargas = true,
    charges = true,
    spell = true
  }

  for k, v in pairs(extra) do
    if not known[k] then
      table.insert(out, tostring(k) .. ": " .. eqInv.safeString(v))
    end
  end

  return table.concat(out, " | ")
end

function eqInv.formatItemDetails(item)
  local raw = eqInv.rawItemTable(item)
  local out = {}

  local damageDice = raw.Damage_Dice or raw.damage_dice or item.damage_dice
  local damageAvg = raw.Damage_Avg or raw.damage_avg or item.damage_avg

  if eqInv.hasValue(damageDice) and eqInv.norm(damageDice) ~= "null" then
    table.insert(out, "Daño: " .. eqInv.safeString(damageDice))
  end

  if damageAvg ~= nil and eqInv.safeString(damageAvg) ~= "" and eqInv.norm(damageAvg) ~= "null" then
    table.insert(out, "Avg: " .. eqInv.safeString(damageAvg))
  end

  local armor = raw.Armor_Protections or raw.armor_protections
  local armorText = eqInv.formatArmorProtections(armor)
  if armorText ~= "" then
    table.insert(out, "Protecciones: " .. armorText)
  end

  local spells = raw.Spells or raw.spells
  local spellsText = eqInv.formatSpells(spells)
  if eqInv.hasValue(spellsText) then
    table.insert(out, "Spells: " .. spellsText)
  end

  local extra = raw.Extra_Data or raw.extra_data
  if type(extra) == "table" then
    local extraText = eqInv.formatExtraDataDetails(extra)
    if extraText ~= "" then table.insert(out, extraText) end
  end

  return table.concat(out, " | ")
end

function eqInv.printPrettyItemBox(item)
  local nombre = eqInv.cleanCellText(item.nombre or "?")
  local afecta = eqInv.cleanCellText(item.afectaciones_text or "")
  local detalles = eqInv.cleanCellText(eqInv.formatItemDetails(item))
  local lugar = eqInv.cleanCellText(eqInv.formatLugar(item))

  if afecta == "" then afecta = "-" end
  if detalles == "" then detalles = nil end
  if lugar == "" then lugar = "-" end

  -- No imprime borde superior/inferior aquí.
  -- El grupo controla los separadores para evitar líneas dobles:
  -- +----------------
  -- +----------------
  eqInv.out(eqInv.boxTextLine(eqInv.itemHeaderParts(item)), eqInv.colorByLevel(item.nivel))
  eqInv.printBoxWrapped("Nombre", nombre)
  eqInv.printBoxWrapped("Afecta", afecta)
  if detalles then eqInv.printBoxWrapped("Detalle", detalles) end
  eqInv.printBoxWrapped("Lugar ", lugar)
end

-- Compatibilidad: el modo agrupado usa cajas; estas funciones quedan por si se reutilizan.
function eqInv.formatItemCompactLines(item)
  local header = eqInv.itemHeaderParts(item)
  local nombre = "Nombre: " .. eqInv.cleanCellText(item.nombre or "?")
  local afecta = "Afecta: " .. eqInv.cleanCellText(item.afectaciones_text or "-")
  local detalles = eqInv.cleanCellText(eqInv.formatItemDetails(item))
  local lugar = "Lugar : " .. eqInv.cleanCellText(eqInv.formatLugar(item))
  local third = afecta
  if detalles ~= "" then third = third .. " | Detalle: " .. detalles end

  return eqInv.shorten(header, eqInv.boxContentWidth()),
         eqInv.shorten(nombre, eqInv.boxContentWidth()),
         eqInv.shorten(third .. " | " .. lugar, eqInv.boxContentWidth())
end

function eqInv.printCompactItem(item)
  eqInv.printPrettyItemBox(item)
end

function eqInv.formatItemTableRow(item)
  local c = eqInv.config.tableColumns
  local nivel = eqInv.padLeft(tostring(item.nivel or 0), c.nivel)
  local peso = eqInv.padLeft(tostring(item.peso or 0), c.peso) -- Sin prefijo p.
  local score = eqInv.padLeft(tostring(eqInv.scoreItem(item, eqInv.config.recommendMode)), c.score)
  local tipo = eqInv.padRight(item.tipo or "", c.tipo)
  local nombre = eqInv.padRight(item.nombre or "?", c.nombre)
  local afecta = item.afectaciones_text or ""
  if afecta == "" then afecta = "-" end
  afecta = eqInv.padRight(afecta, c.afecta)

  local lugar = eqInv.padRight(eqInv.formatLugar(item), c.lugar)

  return nivel .. "  " .. peso .. "  " .. score .. "  " .. tipo .. "  " .. nombre .. "  " .. afecta .. "  " .. lugar
end

function eqInv.printTableHeader()
  local c = eqInv.config.tableColumns
  local header = eqInv.padLeft("Nivel", c.nivel) .. "  " ..
                 eqInv.padLeft("Peso", c.peso) .. "  " ..
                 eqInv.padLeft("Pts", c.score) .. "  " ..
                 eqInv.padRight("Tipo", c.tipo) .. "  " ..
                 eqInv.padRight("Nombre", c.nombre) .. "  " ..
                 eqInv.padRight("Afecta", c.afecta) .. "  " ..
                 eqInv.padRight("Lugar", c.lugar)
  eqInv.out(header, "white")
  eqInv.out(eqInv.repeatChar("-", #header), "grey")
end

function eqInv.printFlatTable(results, max)
  eqInv.printTableHeader()
  for i = 1, max do eqInv.out(eqInv.formatItemTableRow(results[i]), eqInv.colorByLevel(results[i].nivel)) end
end

function eqInv.printGroupedTable(results, limit)
  local groups = eqInv.groupResultsByWear(results)
  local groupCount = 0
  local printed = 0
  local broadSearch = #groups > 1

  local perGroupLimit = limit
  if broadSearch then
    perGroupLimit = eqInv.config.groupedItemLimit or 3
  end

  for _, group in ipairs(groups) do
    if broadSearch and groupCount >= (eqInv.config.groupLimit or 25) then break end
    groupCount = groupCount + 1

    echo("\n")
    eqInv.out(eqInv.boxLine("="), eqInv.config.borderColor)
    eqInv.out(eqInv.boxTextLine("Grupo: " .. group.label .. "  (" .. tostring(#group.items) .. ")"), eqInv.config.headerColor)
    eqInv.out(eqInv.boxLine("="), eqInv.config.borderColor)

    local maxItems = math.min(perGroupLimit, #group.items)
    if maxItems > 0 then
      eqInv.out(eqInv.boxLine("-"), eqInv.config.borderColor)
    end

    for i = 1, maxItems do
      printed = printed + 1
      eqInv.printPrettyItemBox(group.items[i])
      eqInv.out(eqInv.boxLine("-"), eqInv.config.borderColor)
    end

    if #group.items > maxItems then
      eqInv.warn("Grupo " .. group.label .. ": " .. tostring(maxItems) .. "/" .. tostring(#group.items) .. ". Filtra mas, por ejemplo: eqlista 10-14 " .. group.label)
    end
  end

  if broadSearch then
    cecho("<grey>Resumen:<reset> " .. tostring(#results) .. " items en " .. tostring(#groups) .. " grupo(s). Mostrando hasta " .. tostring(perGroupLimit) .. " por grupo.\n")
  else
    cecho("<grey>Resumen:<reset> " .. tostring(printed) .. " item(s) mostrado(s).\n")
  end
end

function eqInv.printResults(results, title, limit)
  limit = limit or eqInv.config.resultLimit
  cecho("<cyan>[EQSearch]<reset> " .. title .. " " .. tostring(#results) .. " resultado(s) <grey>[modo: " .. eqInv.recommendLabel() .. "]<reset>\n")

  if #results == 0 then
    echo("Nada.\n")
    return
  end

  local max = math.min(limit, #results)

  eqInv.printModeHint()

  if eqInv.config.outputMode == "paragraph" then
    for i = 1, max do eqInv.out(eqInv.formatItem(results[i]), eqInv.colorByLevel(results[i].nivel)) end
    if #results > max then
      eqInv.warn("Mostrando " .. tostring(max) .. " de " .. tostring(#results) .. ". Usa una busqueda mas especifica.")
    end
  elseif eqInv.config.outputMode == "table" then
    eqInv.printFlatTable(results, max)
    if #results > max then
      eqInv.warn("Mostrando " .. tostring(max) .. " de " .. tostring(#results) .. ". Usa una busqueda mas especifica.")
    end
  else
    eqInv.printGroupedTable(results, limit)
  end
end

function eqInv.parseTextSearchLevel(q)
  -- Sintaxis literal con filtro opcional:
  --   eqbusca texto a buscar + 14
  --   eqbusca texto a buscar + 10-14
  --
  -- Todo lo que queda antes del ultimo "+" se toma como texto literal.
  q = eqInv.trim(q or "")

  local text, a, b = q:match("^(.*)%s*%+%s*(%d+)%s*%-%s*(%d+)%s*$")
  if text and a and b then
    text = eqInv.trim(text)
    if text ~= "" then
      a, b = tonumber(a), tonumber(b)
      if a > b then a, b = b, a end
      return text, a, b, true
    end
  end

  local text2, n = q:match("^(.*)%s*%+%s*(%d+)%s*$")
  if text2 and n then
    text2 = eqInv.trim(text2)
    if text2 ~= "" then
      n = tonumber(n)
      return text2, n, n, true
    end
  end

  return q, nil, nil, false
end

function eqInv.searchText(q)
  if not eqInv.ensureReady() then return end
  q = eqInv.trim(q or "")
  if q == "" then
    eqInv.warn("Uso: eqbusca <nombre o descripcion>  |  eqsearch <nombre o descripcion>")
    eqInv.warn("Filtro opcional: eqbusca <texto> + 14  |  eqbusca <texto> + 10-14")
    eqInv.warn("Para filtros por nivel/slot/set usa: eqlista")
    return
  end

  local searchText, minLevel, maxLevel, hasLevelFilter = eqInv.parseTextSearchLevel(q)

  local results = {}
  for _, item in ipairs(eqInv.cache.items) do
    local ok = eqInv.containsText((item.nombre or "") .. " " .. (item.desc_corta or ""), searchText)
    if ok and hasLevelFilter then
      ok = eqInv.itemInLevelRange(item, minLevel, maxLevel)
    end
    if ok then table.insert(results, item) end
  end

  eqInv.sortDisplayResults(results)

  local title = "Busca nombre/descripcion: " .. searchText
  if hasLevelFilter then
    if tonumber(minLevel) == tonumber(maxLevel) then
      title = title .. " + nivel " .. tostring(maxLevel)
    else
      title = title .. " + nivel " .. tostring(minLevel) .. "-" .. tostring(maxLevel)
    end
  end

  eqInv.printResults(results, title)
end

function eqInv.textAlias(input)
  eqInv.searchText(input or "")
end

function eqInv.parseSearchLevelArg(input)
  -- Para busquedas normales:
  --   eqsearch 14        => solo nivel 14
  --   eqsearch 14 luz    => solo nivel 14 y filtro luz
  --   eqsearch 10-14     => rango 10 a 14
  -- Para eqfaltante se sigue usando parseLevelArg(), porque ahí conviene <= nivel.
  input = eqInv.trim(input or "")
  local a, b, rest = input:match("^(%d+)%s*%-%s*(%d+)%s*(.*)$")
  if a and b then
    a, b = tonumber(a), tonumber(b)
    if a > b then a, b = b, a end
    return a, b, eqInv.trim(rest)
  end

  local n, rest2 = input:match("^(%d+)%s*(.*)$")
  if n then
    n = tonumber(n)
    return n, n, eqInv.trim(rest2)
  end

  return nil, nil, input
end

function eqInv.parseNaturalSearch(input)
  -- Soporta:
  --   eqsearch 14              => nivel exacto 14
  --   eqsearch 14 luz          => nivel exacto 14 + filtro luz
  --   eqsearch 10-14 escudo    => rango 10-14 + filtro escudo
  --   eqsearch luz 14          => filtro luz + nivel exacto 14
  --   eqsearch luz 6-14        => filtro luz + rango 6-14
  --   eqsearch luz             => filtro/slot luz, todos los niveles
  --   eqsearch light           => filtro/slot light, todos los niveles
  input = eqInv.trim(input or "")
  if input == "" then return nil end

  local minLevel, maxLevel, filter = eqInv.parseSearchLevelArg(input)
  if minLevel ~= nil and maxLevel ~= nil then
    return { kind = "level", minLevel = minLevel, maxLevel = maxLevel, filter = filter }
  end

  local left, a, b = input:match("^(.-)%s+(%d+)%s*%-%s*(%d+)%s*$")
  if left and a and b then
    a, b = tonumber(a), tonumber(b)
    if a > b then a, b = b, a end
    return { kind = "level", minLevel = a, maxLevel = b, filter = eqInv.trim(left) }
  end

  local left2, n = input:match("^(.-)%s+(%d+)%s*$")
  if left2 and n then
    n = tonumber(n)
    return { kind = "level", minLevel = n, maxLevel = n, filter = eqInv.trim(left2) }
  end

  -- Si el texto completo es un alias de slot, buscar por slot/tipo, no por nombre.
  if eqInv.getSlotAlias(input) then
    return { kind = "wear", minLevel = nil, maxLevel = nil, filter = input }
  end

  return { kind = "text", query = input }
end

function eqInv.searchWear(filter)
  if not eqInv.ensureReady() then return end
  local results = eqInv.findItems({ wear = filter })
  eqInv.sortDisplayResults(results)
  eqInv.printResults(results, "Slot/tipo: " .. filter)
end

function eqInv.showModeHelp()
  eqInv.echo("Modo actual: " .. eqInv.recommendLabel())
  echo("Cambiar modo: eqmodo subir | pk | defensa | caster | healer | danio | balance\n")
end

function eqInv.searchRange(minLevel, maxLevel, filter)
  if not eqInv.ensureReady() then return end
  local results = eqInv.findItems({ minLevel = minLevel, maxLevel = maxLevel, wear = filter })
  eqInv.sortDisplayResults(results)
  local title
  if tonumber(minLevel) == tonumber(maxLevel) then
    title = "Nivel " .. tostring(maxLevel)
  else
    title = "Nivel " .. tostring(minLevel) .. "-" .. tostring(maxLevel)
  end
  if filter and filter ~= "" then title = title .. " / " .. filter end
  eqInv.printResults(results, title)
end

function eqInv.searchSet(q)
  if not eqInv.ensureReady() then return end
  local results = eqInv.findItems({ setQuery = q })
  eqInv.printResults(results, "Set: " .. q)
end

-- ------------------------------------------------------------
-- Indices visibles / ayuda
-- ------------------------------------------------------------
function eqInv.sortedCountLines(counts)
  local arr = {}
  for k, v in pairs(counts or {}) do table.insert(arr, { name = k, count = v }) end
  table.sort(arr, function(a, b)
    if a.count == b.count then return a.name < b.name end
    return a.count > b.count
  end)
  return arr
end

function eqInv.showCounts(title, counts)
  if not eqInv.ensureReady() then return end
  cecho("<cyan>" .. title .. "<reset>\n")
  for _, r in ipairs(eqInv.sortedCountLines(counts)) do
    echo(string.format("%-24s %s\n", r.name, tostring(r.count)))
  end
end

function eqInv.showTipos()
  eqInv.showCounts("Tipos indexados", eqInv.cache.typeCounts)
end

function eqInv.showVestir()
  eqInv.showCounts("Vestir indexado", eqInv.cache.wearCounts)
  cecho("<cyan>Alias de slots conocidos<reset>\n")
  local aliases = {}
  for k, _ in pairs(eqInv.slotAliases) do table.insert(aliases, k) end
  table.sort(aliases)
  echo(table.concat(aliases, ", ") .. "\n")
end

function eqInv.showFlags()
  eqInv.showCounts("Flags indexados", eqInv.cache.flagCounts)
end

function eqInv.showSets()
  eqInv.showCounts("Sets indexados", eqInv.cache.setCounts)
end

function eqInv.help()
  cecho("<cyan>EQSearch Petria - ayuda<reset>\n")
  echo("eqsync [url]                    Descarga, borra DB anterior e indexa el JSON.\n")
  echo("\n")
  echo("BUSQUEDA LITERAL POR NOMBRE/DESCRIPCION:\n")
  echo("eqbusca varita                  Busca 'varita' en nombre o descripcion.\n")
  echo("eqsearch varita                 Alias de eqbusca.\n")
  echo("eqbusca luz 14                  Busca literalmente 'luz' y '14' en nombre/descripcion.\n")
  echo("eqbusca luz + 14                Busca 'luz' y filtra items exactamente nivel 14.\n")
  echo("\n")
  echo("LISTADO ESTRUCTURADO POR NIVEL/SLOT/SET:\n")
  echo("eqlista 14                      Items exactamente de nivel 14.\n")
  echo("eqlista 10-14                   Items nivel 10 al 14, agrupados por Vestir.\n")
  echo("eqlista 14 luz                  Items exactamente nivel 14 compatibles con luz.\n")
  echo("eqlista luz 14                  Igual que eqlista 14 luz.\n")
  echo("eqlista luz                     Todos los items compatibles con luz.\n")
  echo("eqlista 10-14 escudo            Items nivel 10 al 14 que se visten como escudo/rodela/escudo.\n")
  echo("eqlista set                     Lista todos los sets indexados.\n")
  echo("eqlista set dragon              Busca items cuyo Set contenga 'dragon'.\n")
  echo("eqlista tipos                   Lista tipos indexados.\n")
  echo("eqlista vestir                  Lista valores Vestir indexados y alias de slots.\n")
  echo("eqlista flags                   Lista flags indexados.\n")
  echo("eqlista formato grouped         Agrupa por Vestir/slot en bloques compactos.\n")
  echo("eqlista formato table           Tabla plana, sin columna Vestir.\n")
  echo("eqlista formato paragraph       Parrafo minimalista.\n")
  echo("eqlista modo subir              Recomienda para subir nivel: CON/SAB/INT/HP/Mana.\n")
  echo("eqlista modo pk                 Recomienda para PK: Damroll/Hitroll/DEX/HP/Saves.\n")
  echo("eqlista modo defensa            Recomienda defensa: HP/CON/protecciones/saves/resistencias.\n")
  echo("eqlista modo caster             Recomienda caster: INT/Mana/SpellPower/saves.\n")
  echo("eqlista modo healer             Recomienda healer: SAB/Mana/HealPower/saves.\n")
  echo("\n")
  echo("OTROS:\n")
  echo("eqvnum 1100                     Muestra un item especifico por VNUM.\n")
  echo("eqpower [nivel]                 Muestra cap de SP/HSP y tope bruto por objeto.\n")
  echo("eqmodo                          Muestra modo actual y modos disponibles.\n")
  echo("eqmodo subir|pk|defensa|caster  Atajo para cambiar modo de recomendacion.\n")
  echo("eqorden nivel|pts|nombre        Cambia orden visual de eqbusca/eqlista.\n")
  echo("Los codigos de color de Petria como {R, {G, {Y y {x se renderizan en la salida.\n")
  echo("Armas muestran daño, promedio, flags/tipo de arma; armaduras muestran protecciones.\n")
  echo("eqfaltante                      Usa nivel GMCP, ignora emblema y muestra 3 sugerencias por slot.\n")
  echo("eqfaltantes                     Igual que eqfaltante.\n")
  echo("eqfaltante 14                   Override manual: busca sugerencias <= nivel 14.\n")
  echo("eqlevel 14                      Nivel por defecto si GMCP no trae nivel.\n")
end

function eqInv.setOutputMode(mode)
  mode = eqInv.norm(mode)
  if mode == "tabla" then mode = "table" end
  if mode == "grupo" or mode == "grouped" or mode == "group" or mode == "agrupado" then mode = "groupedTable" end
  if mode == "parrafo" or mode == "paragraphs" then mode = "paragraph" end
  if mode ~= "table" and mode ~= "paragraph" and mode ~= "groupedTable" then
    eqInv.warn("Uso: eqsearch formato grouped  |  eqsearch formato table  |  eqsearch formato paragraph")
    return
  end
  eqInv.config.outputMode = mode
  eqInv.echo("Formato de salida: " .. mode)
end

-- ------------------------------------------------------------
-- Captura de slots faltantes desde el MUD
-- ------------------------------------------------------------
function eqInv.cleanupMissingTriggers()
  if not eqInv.missingCapture or not eqInv.missingCapture.triggers then return end
  for _, id in pairs(eqInv.missingCapture.triggers) do eqInv.safeKillTrigger(id) end
  eqInv.missingCapture.triggers = {}
end

function eqInv.captureMissing(arg)
  if not eqInv.ensureReady() then return end
  arg = eqInv.trim(arg)

  local minLevel, maxLevel = eqInv.parseLevelArg(arg)
  local gmcpPath = nil

  if not maxLevel then
    maxLevel, gmcpPath = eqInv.getGMCPLevel()
    if maxLevel then
      minLevel = 0
      eqInv.echo("Nivel detectado por GMCP: " .. tostring(maxLevel) .. " (" .. tostring(gmcpPath or "?") .. ")")
    elseif eqInv.config.defaultLevel then
      minLevel, maxLevel = 0, eqInv.config.defaultLevel
      eqInv.warn("No pude leer nivel desde GMCP. Usando nivel por defecto: " .. tostring(maxLevel))
    else
      eqInv.warn("No pude leer nivel desde GMCP. Usa eqlevel 14 o ejecuta eqfaltante 14 como override manual.")
    end
  end

  eqInv.cleanupMissingTriggers()
  eqInv.missingCapture = { slots = {}, minLevel = minLevel, maxLevel = maxLevel, gmcpLevel = maxLevel, gmcpPath = gmcpPath, done = false, triggers = {} }
  local st = eqInv.missingCapture

  st.triggers.slot = tempRegexTrigger([[^<\s*(.*?)\s*>\s+<\s*Vacio\s*>]], function()
    local slot = eqInv.trim(matches[2] or "")
    if slot ~= "" and not eqInv.isIgnoredMissingSlot(slot) then table.insert(eqInv.missingCapture.slots, slot) end
  end)

  st.triggers.done = tempRegexTrigger([[^Te faltan\s+(\d+)\s+piezas\s+de\s+(\d+)\.]], function()
    eqInv.timers.finishMissing = tempTimer(0.2, eqInv.finishMissingCapture)
  end, 1)

  eqInv.timers.finishMissingFallback = tempTimer(2.0, eqInv.finishMissingCapture)
  eqInv.echo("Consultando equipo faltante...")
  sendAll("equipo faltante", "equipo faltante inventario", false)
end

function eqInv.finishMissingCapture()
  local st = eqInv.missingCapture
  if not st or st.done then return end
  st.done = true
  eqInv.cleanupMissingTriggers()
  if eqInv.timers then
    eqInv.safeKillTimer(eqInv.timers.finishMissing)
    eqInv.safeKillTimer(eqInv.timers.finishMissingFallback)
    eqInv.timers.finishMissing = nil
    eqInv.timers.finishMissingFallback = nil
  end

  local seen, slots = {}, {}
  for _, s in ipairs(st.slots or {}) do
    local n = eqInv.norm(s)
    if n ~= "" and not seen[n] then
      seen[n] = true
      table.insert(slots, s)
    end
  end

  if #slots == 0 then
    eqInv.warn("No capture slots vacios. Revisa si el texto del MUD cambio o sube el timer.")
    return
  end

  local rangeTxt = "todos los niveles"
  if st.maxLevel then rangeTxt = "nivel <= " .. tostring(st.maxLevel) end
  cecho("<cyan>Slots faltantes detectados<reset> (" .. rangeTxt .. "): " .. table.concat(slots, ", ") .. "\n")

  for _, slot in ipairs(slots) do
    local suggestions, total, duplicatesRemoved = eqInv.findTopSuggestionsForSlot(slot, st.maxLevel, eqInv.config.missingSlotLimit)
    local title = "Slot: " .. slot
    if st.maxLevel then title = title .. " | 3 sugerencias <= nivel " .. tostring(st.maxLevel) end
    eqInv.printResults(suggestions, title, eqInv.config.missingSlotLimit)
    if total and total > #suggestions then
      eqInv.warn("Hay " .. tostring(total) .. " candidato(s) unicos para " .. slot .. "; mostrando las mejores " .. tostring(#suggestions) .. ".")
    end
    if duplicatesRemoved and duplicatesRemoved > 0 then
      eqInv.warn("Se omitieron " .. tostring(duplicatesRemoved) .. " duplicado(s) visuales para " .. slot .. ".")
    end
  end
end


function eqInv.searchVnum(vnum)
  if not eqInv.ensureReady() then return end
  vnum = tonumber(vnum)
  if not vnum then
    eqInv.warn("Uso: eqvnum 1100")
    return
  end

  local item = eqInv.cache.byVnum[vnum]
  if not item then
    eqInv.warn("No encontre item con VNUM " .. tostring(vnum))
    return
  end

  eqInv.printResults({ item }, "VNUM " .. tostring(vnum), 1)
end

-- ------------------------------------------------------------
-- Aliases
-- ------------------------------------------------------------
function eqInv.alias(input)
  input = eqInv.trim(input or "")
  if input == "" or input == "help" or input == "ayuda" then eqInv.help(); return end

  local cmd, rest = input:match("^(%S+)%s*(.*)$")
  cmd = eqInv.norm(cmd or "")
  rest = eqInv.trim(rest or "")

  if cmd == "sync" or cmd == "update" or cmd == "url" then eqInv.sync(rest); return end
  if cmd == "tipos" or cmd == "types" then eqInv.showTipos(); return end
  if cmd == "sets" then eqInv.showSets(); return end
  if cmd == "vestir" or cmd == "slots" then eqInv.showVestir(); return end
  if cmd == "flags" then eqInv.showFlags(); return end
  if cmd == "formato" or cmd == "format" then eqInv.setOutputMode(rest); return end
  if cmd == "modo" or cmd == "mode" or cmd == "recomendar" then
    if rest == "" then eqInv.showModeHelp()
    else eqInv.setRecommendMode(rest) end
    return
  end
  if cmd == "orden" or cmd == "sort" then eqInv.setDisplaySortMode(rest); return end
  if cmd == "power" or cmd == "spellpower" or cmd == "healpower" then eqInv.showPowerInfo(rest); return end
  if cmd == "faltante" or cmd == "faltantes" or cmd == "missing" then eqInv.captureMissing(rest); return end
  if cmd == "set" then
    if rest == "" then eqInv.showSets()
    else eqInv.searchSet(rest) end
    return
  end

  local parsed = eqInv.parseNaturalSearch(input)
  if parsed and parsed.kind == "level" then
    eqInv.searchRange(parsed.minLevel, parsed.maxLevel, parsed.filter)
    return
  elseif parsed and parsed.kind == "wear" then
    eqInv.searchWear(parsed.filter)
    return
  elseif parsed and parsed.kind == "text" then
    eqInv.searchText(parsed.query)
    return
  end

  eqInv.searchText(input)
end

function eqInv.setDefaultLevel(n)
  n = tonumber(n)
  if not n then eqInv.warn("Uso: eqlevel 14"); return end
  eqInv.config.defaultLevel = n
  eqInv.echo("Nivel por defecto definido: " .. tostring(n))
end

function eqInv.installAliases()
  -- Antes de instalar, mata cualquier alias existente registrado por este modulo.
  for _, id in pairs(eqInv.aliasIds or {}) do eqInv.safeKillAlias(id) end
  eqInv.aliasIds = {}

  -- eqsearch/eqbusca: busqueda literal por nombre/descripcion.
  eqInv.aliasIds.searchText = tempAlias([[^eqsearch(?:\s+(.*))?$]], function() eqInv.textAlias(matches[2] or "") end)
  eqInv.aliasIds.busca = tempAlias([[^eqbusca(?:\s+(.*))?$]], function() eqInv.textAlias(matches[2] or "") end)

  -- eqlista: listado estructurado por nivel, slot, set, tipos, flags, etc.
  eqInv.aliasIds.lista = tempAlias([[^eqlista(?:\s+(.*))?$]], function() eqInv.alias(matches[2] or "") end)

  eqInv.aliasIds.sync = tempAlias([[^eqsync(?:\s+(.+))?$]], function() eqInv.sync(matches[2] or "") end)
  eqInv.aliasIds.faltantes = tempAlias([[^eqfaltantes(?:\s+(.*))?$]], function() eqInv.captureMissing(matches[2] or "") end)
  eqInv.aliasIds.faltante = tempAlias([[^eqfaltante(?:\s+(.*))?$]], function() eqInv.captureMissing(matches[2] or "") end)
  eqInv.aliasIds.level = tempAlias([[^eqlevel\s+(\d+)\s*$]], function() eqInv.setDefaultLevel(matches[2]) end)
  eqInv.aliasIds.format = tempAlias([[^eqformat\s+(grouped|group|grupo|agrupado|table|tabla|paragraph|paragraphs|parrafo)\s*$]], function() eqInv.setOutputMode(matches[2]) end)
  eqInv.aliasIds.mode = tempAlias([[^eqmodo\s+(subir|level|levelear|xp|exp|pk|pvp|defensa|tanque|tank|caster|mago|hechicero|spell|spells|sp|healer|heal|curar|sanar|hsp|danio|dano|daño|damage|balance|balanced)\s*$]], function() eqInv.setRecommendMode(matches[2]) end)
  eqInv.aliasIds.modeHelp = tempAlias([[^eqmodo\s*$]], function() eqInv.showModeHelp() end)
  eqInv.aliasIds.orden = tempAlias([[^eqorden(?:\s+(nivel|level|pts|puntos|score|nombre|name))?\s*$]], function() eqInv.setDisplaySortMode(matches[2] or "") end)
  eqInv.aliasIds.power = tempAlias([[^eqpower(?:\s+(\d+))?$]], function() eqInv.showPowerInfo(matches[2] or "") end)
  eqInv.aliasIds.vnum = tempAlias([[^eqvnum\s+(\d+)\s*$]], function() eqInv.searchVnum(matches[2]) end)
end

function eqInv.init()
  eqInv.ensureDB()
  eqInv.registerDownloadHandlers()
  eqInv.installAliases()
  eqInv.loadCacheFromDB()
  eqInv.echo("Modulo listo. Usa: eqsync  |  eqlista help  |  eqbusca <texto>")
end

eqInv.init()
