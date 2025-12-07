-- LuaRules/ceg_lookup.lua Made by Steel.
-- BAR-friendly CEG lookup helper.
-- Scans effects/*.lua and builds tables of available CEGs.

local CEGLookup = {}

local EFFECTS_DIR = "effects"

local function scanEffects()
  local byName   = {}
  local byFile   = {}
  local nameList = {}

  -- NOTE: if this ever misses subdirectories, you can try:
  --   VFS.DirList(EFFECTS_DIR, "*.lua", VFS.RAW_FIRST, true)
  local files = VFS.DirList(EFFECTS_DIR, "*.lua") or {}

  for _, path in ipairs(files) do
    local short = path:match("([^/]+)%.lua$") or path

    local ok, defs = pcall(VFS.Include, path)
    if ok and type(defs) == "table" then
      byFile[short] = byFile[short] or {}
      for cegName, def in pairs(defs) do
        if type(cegName) == "string" and not byName[cegName] then
          byName[cegName] = {
            file      = path,
            shortFile = short,
          }
          table.insert(byFile[short], cegName)
          table.insert(nameList, cegName)
        end
      end
    elseif Spring and Spring.Echo then
      Spring.Echo(string.format("[ceg_lookup] Failed to include %s: %s", path, tostring(defs)))
    end
  end

  table.sort(nameList)
  for _, list in pairs(byFile) do
    table.sort(list)
  end

  return {
    byName   = byName,
    byFile   = byFile,
    nameList = nameList,
  }
end

local cache = scanEffects()

function CEGLookup.GetAllNames()
  return cache.nameList
end

function CEGLookup.GetByFile()
  return cache.byFile
end

function CEGLookup.Resolve(name)
  return cache.byName[name]
end

function CEGLookup.Reload()
  cache = scanEffects()
  return cache
end

return CEGLookup
