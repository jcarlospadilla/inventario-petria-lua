-- PetriaEQSearch hotfix rev13
-- Corrige: LuaSQL: table items has no column named _set_norm
-- Uso: ejecutar despues de cargar PetriaEQSearch y antes de eqsync.

if type(eqInv) ~= "table" then
  cecho("<red>[EQHotfix]<reset> eqInv no existe. Instala/carga PetriaEQSearch primero.\n")
  return
end

eqInv.version = "2026.05.30-rev13-hotfix"

function eqInv.dbItemRow(row)
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
  eqInv.echo("Hotfix rev13 aplicado. Usa: eqsearch help")
end

cecho("<green>[EQHotfix]<reset> rev13 aplicado: db:add ya no recibe campos internos _set_norm/_tipo_norm/etc. Ejecuta eqsync nuevamente.\n")
