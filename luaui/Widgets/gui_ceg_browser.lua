--------------------------------------------------------------------------------
-- CEG Browser - Lua-only UI (multi-select, multi-spawn)
-- Save as: LuaUI/Widgets/gui_ceg_browser.lua
--------------------------------------------------------------------------------

function widget:GetInfo()
    return {
        name    = "CEG Browser",
        desc    = "Spawn CEGs for testing (with multi-select and multi-spawn)",
        author  = "Steel",
        layer   = 1000,
        enabled = true,
    }
end

function widget:WantsMouse()    return true end
function widget:WantsKeyboard() return true end

--------------------------------------------------------------------------------
-- Engine refs
--------------------------------------------------------------------------------

local spEcho            = Spring.Echo
local spTraceScreenRay  = Spring.TraceScreenRay
local spSendLuaRulesMsg = Spring.SendLuaRulesMsg
local spSendCommands    = Spring.SendCommands
local spGetViewGeometry = Spring.GetViewGeometry
local spGetConfigInt    = Spring.GetConfigInt
local spSetConfigInt    = Spring.SetConfigInt
local spGetMouseState   = Spring.GetMouseState
local spGetModKeyState  = Spring.GetModKeyState

local glColor        = gl.Color
local glRect         = gl.Rect
local glText         = gl.Text
local glLineWidth    = gl.LineWidth
local glBeginEnd     = gl.BeginEnd
local glVertex       = gl.Vertex
local glGetTextWidth = gl.GetTextWidth

local GL_TRIANGLE_FAN   = GL.TRIANGLE_FAN
local GL_TRIANGLE_STRIP = GL.TRIANGLE_STRIP

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function Clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function Snap(x)
    return math.floor(x + 0.5)
end

--------------------------------------------------------------------------------
-- Theme
--------------------------------------------------------------------------------

local theme = {}

theme.window = {
    bg        = {0.03, 0.03, 0.03, 0.92},
    border    = {0.10, 0.10, 0.10, 1.00},
    titleBg   = {0.00, 0.00, 0.00, 0.55},
    titleText = {1.00, 1.00, 1.00, 1.00},
}

theme.button = {
    bg         = {0.18, 0.18, 0.18, 1.00},
    bgActive   = {0.31, 0.63, 0.27, 1.00},
    text       = {0.90, 0.90, 0.90, 1.00},
    textActive = {1.00, 1.00, 1.00, 1.00},
    border     = {0.35, 0.35, 0.35, 1.00},
}

theme.badButton = {
    bg     = {0.40, 0.10, 0.10, 1.00},
    text   = {1.00, 1.00, 1.00, 1.00},
    border = {0.20, 0.02, 0.02, 1.00},
}

theme.alphaBtn = {
    bg       = {0.10, 0.10, 0.10, 0.95},
    bgActive = {0.31, 0.63, 0.27, 1.00},
    text     = {0.88, 0.88, 0.88, 1.00},
    border   = {0.35, 0.35, 0.35, 1.00},
}

theme.tuningPanel = {
    bg     = {0.05, 0.05, 0.05, 0.96},
    border = {0.40, 0.40, 0.40, 1.00},
    text   = {0.90, 0.90, 0.90, 1.00},
}

theme.list = {
    bg         = {0.06, 0.06, 0.06, 1.00},
    rowBg      = {0.19, 0.19, 0.19, 1.00},
    rowBgSel   = {0.31, 0.63, 0.27, 1.00},
    border     = {0.35, 0.35, 0.35, 1.00},
    rowText    = {0.96, 0.96, 0.96, 1.00},
    rowTextSel = {1.00, 1.00, 1.00, 1.00},
}

theme.slider = {
    track = {0.16, 0.16, 0.16, 1.00},
    fill  = {0.31, 0.63, 0.27, 1.00},
    knob  = {0.95, 0.95, 0.95, 1.00},
}

theme.search = {
    bg       = {0.18, 0.18, 0.18, 1.00},
    border   = {0.35, 0.35, 0.35, 1.00},
    text     = {0.95, 0.95, 0.95, 1.00},
    hintText = {0.55, 0.55, 0.55, 1.00},
}

theme.text = {
    normal = {0.95, 0.95, 0.95, 1.00},
    dim    = {0.70, 0.70, 0.70, 1.00},
}

theme.fontSize = {
    title  = 18,
    normal = 12,
    list   = 14,
    button = 14,
}

local PADDING_OUTER        = 10
local CORNER_WINDOW_RADIUS = 6
local CORNER_BUTTON_RADIUS = 4

--------------------------------------------------------------------------------
-- Rounded rect helpers
--------------------------------------------------------------------------------

local function DrawRoundedRectFilled(x0, y0, x1, y1, r)
    x0, y0, x1, y1 = Snap(x0), Snap(y0), Snap(x1), Snap(y1)
    r = math.max(0, math.min(r or 0, math.min((x1-x0)/2, (y1-y0)/2)))
    if r == 0 then
        glRect(x0, y0, x1, y1)
        return
    end
    glRect(x0 + r, y0,     x1 - r, y1)
    glRect(x0,     y0 + r, x1,     y1 - r)

    local function corner(cx, cy, a0, a1)
        local steps = 6
        glBeginEnd(GL_TRIANGLE_FAN, function()
            glVertex(cx, cy)
            for i = 0, steps do
                local a = a0 + (a1 - a0) * (i / steps)
                glVertex(cx + math.cos(a)*r, cy + math.sin(a)*r)
            end
        end)
    end

    corner(x0 + r, y0 + r, math.pi, 1.5*math.pi)
    corner(x1 - r, y0 + r, 1.5*math.pi, 2.0*math.pi)
    corner(x1 - r, y1 - r, 0.0,        0.5*math.pi)
    corner(x0 + r, y1 - r, 0.5*math.pi, math.pi)
end

local function DrawRoundedRectBorder(x0, y0, x1, y1, r, width)
    x0, y0, x1, y1 = Snap(x0), Snap(y0), Snap(x1), Snap(y1)
    r = math.max(0, math.min(r or 0, math.min((x1-x0)/2, (y1-y0)/2)))
    width = width or 1
    glLineWidth(width)
    if r == 0 then
        glBeginEnd(GL_TRIANGLE_STRIP, function()
            glVertex(x0, y0); glVertex(x1, y0)
            glVertex(x0, y1); glVertex(x1, y1)
        end)
        return
    end
    local steps = 12
    glBeginEnd(GL_TRIANGLE_STRIP, function()
        for i = 0, steps do
            local a = math.pi + (math.pi/2)*(i/steps)
            glVertex(x0 + r + math.cos(a)*r, y0 + r + math.sin(a)*r)
        end
        for i = 0, steps do
            local a = 1.5*math.pi + (math.pi/2)*(i/steps)
            glVertex(x1 - r + math.cos(a)*r, y0 + r + math.sin(a)*r)
        end
        for i = 0, steps do
            local a = 0.0 + (math.pi/2)*(i/steps)
            glVertex(x1 - r + math.cos(a)*r, y1 - r + math.sin(a)*r)
        end
        for i = 0, steps do
            local a = 0.5*math.pi + (math.pi/2)*(i/steps)
            glVertex(x0 + r + math.cos(a)*r, y1 - r + math.sin(a)*r)
        end
    end)
end

--------------------------------------------------------------------------------
-- Button drawing helpers
--------------------------------------------------------------------------------

local function DrawButton(x0, y0, x1, y1, label, isActive, isBad, fontSize)
    x0, y0, x1, y1 = Snap(x0), Snap(y0), Snap(x1), Snap(y1)
    fontSize = fontSize or theme.fontSize.normal

    local colSet = isBad and theme.badButton or theme.button
    local bg = isActive and colSet.bgActive or colSet.bg

    glColor(bg[1], bg[2], bg[3], bg[4])
    DrawRoundedRectFilled(x0, y0, x1, y1, CORNER_BUTTON_RADIUS)

    glColor(colSet.border[1], colSet.border[2], colSet.border[3], colSet.border[4])
    DrawRoundedRectBorder(x0, y0, x1, y1, CORNER_BUTTON_RADIUS, 1)

    if label and label ~= "" then
        local textW = glGetTextWidth(label) * fontSize
        local tx = x0 + (x1 - x0 - textW) * 0.5
        local ty = y0 + (y1 - y0 - fontSize) * 0.5 + 1
        local col = isActive and colSet.textActive or colSet.text
        glColor(col[1], col[2], col[3], col[4])
        glText(label, Snap(tx), Snap(ty), fontSize, "o")
    end
end

local function DrawAlphaButton(x0, y0, x1, y1, label, isActive)
    x0, y0, x1, y1 = Snap(x0), Snap(y0), Snap(x1), Snap(y1)
    local t = theme.alphaBtn
    local bg = isActive and t.bgActive or t.bg

    glColor(bg[1], bg[2], bg[3], bg[4])
    DrawRoundedRectFilled(x0, y0, x1, y1, CORNER_BUTTON_RADIUS)

    glColor(t.border[1], t.border[2], t.border[3], t.border[4])
    DrawRoundedRectBorder(x0, y0, x1, y1, CORNER_BUTTON_RADIUS, 1)

    local fs = theme.fontSize.normal
    local textW = glGetTextWidth(label) * fs
    local tx = x0 + (x1 - x0 - textW) * 0.5
    local ty = y0 + (y1 - y0 - fs) * 0.5 + 1

    glColor(t.text[1], t.text[2], t.text[3], t.text[4])
    glText(label, Snap(tx), Snap(ty), fs, "o")
end

--------------------------------------------------------------------------------
-- State & layout
--------------------------------------------------------------------------------

local CFG_WIN_X = "ceg_browser_lua_win_x"
local CFG_WIN_Y = "ceg_browser_lua_win_y"

local vsx, vsy
local winX, winY, winW, winH
local prevWinH
local collapsed = false

local GRID_COLS   = 2
local currentRows = 25
local function ItemsPerPage() return currentRows * GRID_COLS end

local ALPHA_ROWS = {
    {"All","A","B","C","D","E","F","G"},
    {"H","I","J","K","L","M","N"},
    {"O","P","Q","R","S","T","U"},
    {"V","W","X","Y","Z"},
}

local allCEGs      = {}
local filteredCEGs = {}
local pageIndex    = 0

local selectedCEGs = {}   -- map: name -> true
local lastSelected = nil

local letterFilter  = nil
local searchText    = ""
local searchFocused = false

local pattern      = "line"
local spawnCount   = 1
local spacingValue = 20

local tuningVisible = true
local cheatOn       = false
local globallosOn   = false

local draggingWin    = false
local dragOffX       = 0
local dragOffY       = 0
local draggingSlider = nil

local spawnMode = false

local hitBoxes = {
    titleButtons = {},
    alphaButtons = {},
    topButtons   = {},
    reloadBtn    = nil,
    tuningBtn    = nil,
    searchBox    = nil,
    searchClear  = nil,
    patternBtns  = {},
    sliderCount  = nil,
    sliderSpace  = nil,
    listCells    = {},
    pagerPrev    = nil,
    pagerNext    = nil,
}

--------------------------------------------------------------------------------
-- Data loading & filtering
--------------------------------------------------------------------------------

local function LoadAllCEGs()
    local ok, lookup = pcall(VFS.Include, "LuaRules/ceg_lookup.lua")
    if not ok or type(lookup) ~= "table" or type(lookup.GetAllNames) ~= "function" then
        spEcho("[CEG Browser Lua] Failed to load LuaRules/ceg_lookup.lua: " .. tostring(lookup))
        return
    end
    allCEGs = lookup.GetAllNames() or {}
    table.sort(allCEGs)
    spEcho("[CEG Browser Lua] Loaded " .. #allCEGs .. " CEG names.")
end

local function MatchesFilter(name)
    if letterFilter and letterFilter ~= "" then
        if string.lower(string.sub(name, 1, 1)) ~= letterFilter then
            return false
        end
    end
    if searchText ~= "" then
        local n = string.lower(name)
        local f = string.lower(searchText)
        if not string.find(n, f, 1, true) then
            return false
        end
    end
    return true
end

local function RebuildFiltered()
    filteredCEGs = {}
    for i = 1, #allCEGs do
        local n = allCEGs[i]
        if MatchesFilter(n) then
            filteredCEGs[#filteredCEGs+1] = n
        end
    end

    local newSel = {}
    for _,n in ipairs(filteredCEGs) do
        if selectedCEGs[n] then
            newSel[n] = true
        end
    end
    selectedCEGs = newSel
    spawnMode    = next(selectedCEGs) ~= nil

    local maxPage = math.max(0, math.floor((#filteredCEGs - 1) / ItemsPerPage()))
    pageIndex = Clamp(pageIndex, 0, maxPage)
end

--------------------------------------------------------------------------------
-- Spawn messaging
--------------------------------------------------------------------------------

local function SendSpawnCEG(name, wx, wz)
    if not name or name == "" then
        spEcho("[CEG Browser Lua] No CEG selected.")
        return
    end
    local cnt  = Clamp(spawnCount, 1, 100)
    local spac = Clamp(spacingValue, 0, 128)
    local pat  = pattern
    if pat ~= "line" and pat ~= "ring" and pat ~= "scatter" then
        pat = "line"
    end
    local msg = string.format("cegtest:%s:%d:%d:%d:%d:%s", name, wx, wz, cnt, spac, pat)
    spSendLuaRulesMsg(msg)
    spEcho(string.format("[CEG Browser Lua] Spawn %s count=%d spacing=%d pattern=%s",
        name, cnt, spac, pat))
end

local function SendSpawnMultiCEG(names, wx, wz)
    if not names or #names == 0 then
        spEcho("[CEG Browser Lua] No CEGs selected for multi-spawn.")
        return
    end
    local cnt  = Clamp(spawnCount, 1, 100)
    local spac = Clamp(spacingValue, 0, 128)
    local pat  = pattern
    if pat ~= "line" and pat ~= "ring" and pat ~= "scatter" then
        pat = "line"
    end
    local combo = table.concat(names, ",")
    local msg = string.format("cegtest_multi:%s:%d:%d:%d:%d:%s", combo, wx, wz, cnt, spac, pat)
    spSendLuaRulesMsg(msg)
    spEcho(string.format("[CEG Browser Lua] Spawn MULTI {%s} count=%d spacing=%d pattern=%s",
        combo, cnt, spac, pat))
end

--------------------------------------------------------------------------------
-- Init / shutdown
--------------------------------------------------------------------------------

local function ClampWindowPosition()
    vsx, vsy = spGetViewGeometry()
    if not winX or not winY or not winW or not winH then return end
    local maxX = math.max(0, vsx - winW)
    local maxY = math.max(0, vsy - winH - 60)
    winX = Clamp(Snap(winX), 0, maxX)
    winY = Clamp(Snap(winY), 0, maxY)
end

function widget:Initialize()
    vsx, vsy = spGetViewGeometry()
    winW = 420
    winH = 900

    local cfgX = spGetConfigInt(CFG_WIN_X, 1)
    local cfgY = spGetConfigInt(CFG_WIN_Y, 1)
    if cfgX and cfgY and cfgX > 0 and cfgY > 0 then
        winX, winY = cfgX, cfgY
    else
        winX = math.floor((vsx - winW)/2)
        winY = math.floor((vsy - winH)/2)
    end
    ClampWindowPosition()

    LoadAllCEGs()
    RebuildFiltered()
    widgetHandler:RaiseWidget(self)
end

function widget:Shutdown()
    spSetConfigInt(CFG_WIN_X, winX or 0)
    spSetConfigInt(CFG_WIN_Y, winY or 0)
end

--------------------------------------------------------------------------------
-- DrawScreen
--------------------------------------------------------------------------------

local function MouseInWindow(mx, my)
    return mx >= winX and mx <= winX+winW and my >= winY and my <= winY+winH
end

function widget:DrawScreen()
    if Spring.IsGUIHidden() then return end
    if not winX or not winY then return end

    vsx, vsy = spGetViewGeometry()

    local x0 = Snap(winX)
    local y0 = Snap(winY)
    local x1 = Snap(winX + winW)
    local y1 = Snap(winY + winH)

    -- window background
    glColor(theme.window.bg[1], theme.window.bg[2], theme.window.bg[3], theme.window.bg[4])
    DrawRoundedRectFilled(x0, y0, x1, y1, CORNER_WINDOW_RADIUS)
    glColor(theme.window.border[1], theme.window.border[2], theme.window.border[3], theme.window.border[4])
    DrawRoundedRectBorder(x0, y0, x1, y1, CORNER_WINDOW_RADIUS, 1)

    -- title bar
    local titleH = 30
    glColor(theme.window.titleBg[1], theme.window.titleBg[2], theme.window.titleBg[3], theme.window.titleBg[4])
    DrawRoundedRectFilled(x0+1, y1-titleH, x1-1, y1-1, CORNER_WINDOW_RADIUS-1)

    glColor(theme.window.titleText[1], theme.window.titleText[2], theme.window.titleText[3], theme.window.titleText[4])
    glText("CEG Browser", x0 + PADDING_OUTER, y1 - titleH + 8, theme.fontSize.title, "o")

    ----------------------------------------------------------------
    -- Title buttons
    ----------------------------------------------------------------
    local topBtnW, topBtnH = 24, 18
    local topPad = 6
    hitBoxes.titleButtons = {}

    local closeX1 = x1 - topPad
    local closeX0 = closeX1 - topBtnW
    local closeY0 = y1 - titleH + 6
    local closeY1 = closeY0 + topBtnH

    DrawButton(closeX0, closeY0, closeX1, closeY1, "x", false, true, theme.fontSize.normal)
    hitBoxes.titleButtons.close = {id="close", x0=closeX0, y0=closeY0, x1=closeX1, y1=closeY1}

    local iconX1 = closeX0 - 4
    local iconX0 = iconX1 - topBtnW
    local iconY0 = closeY0
    local iconY1 = closeY1

    local iconLabel = collapsed and "+" or "–"   -- expand when collapsed, collapse when expanded
    DrawButton(iconX0, iconY0, iconX1, iconY1, iconLabel, collapsed, false, theme.fontSize.normal)

    hitBoxes.titleButtons.icon = {id="collapse", x0=iconX0, y0=iconY0, x1=iconX1, y1=iconY1}

    ----------------------------------------------------------------
    -- Alphabet (left) + 2x3 command buttons (right)
    ----------------------------------------------------------------
    local alphaBtnH = 20
    local alphaPadY = 4
    local alphaPadX = 3
    local alphaPanelW = 210

    hitBoxes.alphaButtons = {}
    hitBoxes.topButtons   = {}

    local yAlphaTop = y1 - titleH - 8
    local yCursor   = yAlphaTop

    local alphaX0 = x0 + PADDING_OUTER
    local alphaX1 = alphaX0 + alphaPanelW

    for rowIdx, row in ipairs(ALPHA_ROWS) do
        local rowY1 = yCursor
        local rowY0 = rowY1 - alphaBtnH
        local colX  = alphaX0
        for colIdx, label in ipairs(row) do
            local bw = (label == "All") and 30 or 20
            local x2 = colX + bw
            local active
            if label == "All" then
                active = (not letterFilter)
            else
                active = (letterFilter == string.lower(label))
            end
            DrawAlphaButton(colX, rowY0, x2, rowY1, label, active)
            hitBoxes.alphaButtons[#hitBoxes.alphaButtons+1] = {
                id="alpha_"..label, label=label,
                x0=colX, y0=rowY0, x1=x2, y1=rowY1
            }
            colX = x2 + alphaPadX
        end
        yCursor = rowY0 - alphaPadY
    end
    local alphaBottom = yCursor

    ----------------------------------------------------------------
    -- Right-side 2x3 button panel
    ----------------------------------------------------------------
    local cmdGapX = 8
    local cmdX0   = alphaX1 + cmdGapX
    local cmdX1   = x1 - PADDING_OUTER
    local cmdWidthTotal = cmdX1 - cmdX0
    local cmdColGap     = 6
    local cmdBtnW       = (cmdWidthTotal - cmdColGap) / 2
    local cmdBtnH       = 26

    local row1Y1 = yAlphaTop
    local row1Y0 = row1Y1 - cmdBtnH
    local row2Y1 = row1Y0 - 4
    local row2Y0 = row2Y1 - cmdBtnH
    local row3Y1 = row2Y0 - 4
    local row3Y0 = row3Y1 - cmdBtnH

    local c1x0 = cmdX0
    local c1x1 = cmdX0 + cmdBtnW
    local c2x0 = cmdX0 + cmdBtnW + cmdColGap
    local c2x1 = cmdX1

    -- Row 1
    DrawButton(c1x0, row1Y0, c1x1, row1Y1, "cheat", cheatOn, false, theme.fontSize.button)
    DrawButton(c2x0, row1Y0, c2x1, row1Y1, "globallos", globallosOn, false, theme.fontSize.button)
    hitBoxes.topButtons.cheat = {id="cheat", x0=c1x0,y0=row1Y0,x1=c1x1,y1=row1Y1}
    hitBoxes.topButtons.glob  = {id="globallos", x0=c2x0,y0=row1Y0,x1=c2x1,y1=row1Y1}

    -- Row 2
    DrawButton(c1x0, row2Y0, c1x1, row2Y1, "Reload CEGs", false, false, theme.fontSize.button)
    DrawButton(c2x0, row2Y0, c2x1, row2Y1, "Tuning", tuningVisible, false, theme.fontSize.button)
    hitBoxes.reloadBtn = {id="reload", x0=c1x0,y0=row2Y0,x1=c1x1,y1=row2Y1}
    hitBoxes.tuningBtn = {id="tuning", x0=c2x0,y0=row2Y0,x1=c2x1,y1=row2Y1}

    -- Row 3
    DrawButton(c1x0, row3Y0, c1x1, row3Y1, "Reset", false, false, theme.fontSize.button)
    hitBoxes.topButtons.resetSel = {id="resetSel", x0=c1x0,y0=row3Y0,x1=c1x1,y1=row3Y1}
    -- right col (row3, col2) left empty for future

    local cmdBottom  = row3Y0
    local blockBottom = math.min(alphaBottom, cmdBottom)

    ----------------------------------------------------------------
    -- Search row
    ----------------------------------------------------------------
    local searchH  = 22
    local searchW  = 260
    local searchY1 = blockBottom - 8
    local searchY0 = searchY1 - searchH
    local searchX0 = x0 + PADDING_OUTER
    local searchX1 = searchX0 + searchW

    glColor(theme.search.bg[1], theme.search.bg[2], theme.search.bg[3], theme.search.bg[4])
    DrawRoundedRectFilled(searchX0, searchY0, searchX1, searchY1, CORNER_BUTTON_RADIUS)
    glColor(theme.search.border[1], theme.search.border[2], theme.search.border[3], theme.search.border[4])
    DrawRoundedRectBorder(searchX0, searchY0, searchX1, searchY1, CORNER_BUTTON_RADIUS, 1)

    local drawText = searchText
    local col = theme.search.text
    if drawText == "" and not searchFocused then
        drawText = "search CEG name..."
        col = theme.search.hintText
    end
    glColor(col[1], col[2], col[3], col[4])
    glText(drawText, Snap(searchX0 + 8), Snap(searchY0 + 4), theme.fontSize.normal, "o")

    local clrW = 20
    local clrX1 = searchX1 + clrW
    local clrX0 = clrX1 - clrW
    DrawButton(clrX0, searchY0, clrX1, searchY1, "x", false, false, theme.fontSize.normal)
    hitBoxes.searchBox   = {x0=searchX0,y0=searchY0,x1=searchX1,y1=searchY1}
    hitBoxes.searchClear = {id="search_clear",x0=clrX0,y0=searchY0,x1=clrX1,y1=searchY1}

    glColor(theme.text.dim[1], theme.text.dim[2], theme.text.dim[3], theme.text.dim[4])
    glText(string.format("%d CEGs (filtered)", #filteredCEGs),
           Snap(clrX1 + 8), Snap(searchY0 + 4), theme.fontSize.normal, "o")

    if collapsed then
        return
    end

    ----------------------------------------------------------------
    -- Tuning panel
    ----------------------------------------------------------------
    hitBoxes.patternBtns = {}
    hitBoxes.sliderCount = nil
    hitBoxes.sliderSpace = nil

    local tpX0 = x0 + PADDING_OUTER
    local tpX1 = x1 - PADDING_OUTER
    local tpY1 = searchY0 - 10
    local tpY0 = tpY1 - (tuningVisible and 110 or 0)
    local listTop

    if tuningVisible then
        glColor(theme.tuningPanel.bg[1], theme.tuningPanel.bg[2], theme.tuningPanel.bg[3], theme.tuningPanel.bg[4])
        DrawRoundedRectFilled(tpX0, tpY0, tpX1, tpY1, CORNER_WINDOW_RADIUS)
        glColor(theme.tuningPanel.border[1], theme.tuningPanel.border[2], theme.tuningPanel.border[3], theme.tuningPanel.border[4])
        DrawRoundedRectBorder(tpX0, tpY0, tpX1, tpY1, CORNER_WINDOW_RADIUS, 1)

        glColor(theme.tuningPanel.text[1], theme.tuningPanel.text[2], theme.tuningPanel.text[3], theme.tuningPanel.text[4])
        glText("CEG Tuning", Snap(tpX0 + 10), Snap(tpY1 - 22), theme.fontSize.normal, "o")

        local pattY0 = tpY1 - 44
        local pattH  = 22
        local pattW  = 70
        local pattPad= 4
        local pattX  = tpX0 + 90

        glText("Pattern", Snap(tpX0 + 10), Snap(pattY0 + 4), theme.fontSize.normal, "o")

        local patterns = {"line","ring","scatter"}
        for i,name in ipairs(patterns) do
            local xA = pattX + (i-1)*(pattW+pattPad)
            local xB = xA + pattW
            local label = name:gsub("^%l", string.upper)
            DrawButton(xA, pattY0, xB, pattY0+pattH, label, pattern == name, false, theme.fontSize.button)
            hitBoxes.patternBtns[#hitBoxes.patternBtns+1] = {
                id="pattern_"..name,name=name,x0=xA,y0=pattY0,x1=xB,y1=pattY0+pattH
            }
        end

        local labelX       = tpX0 + 10
        local sliderW      = 140
        local function drawSlider(x0s, yMid, val, minVal, maxVal)
            local tY0 = yMid-3
            local tY1 = yMid+3
            local x1s = x0s+sliderW

            glColor(theme.slider.track[1], theme.slider.track[2], theme.slider.track[3], theme.slider.track[4])
            glRect(Snap(x0s), Snap(tY0), Snap(x1s), Snap(tY1))

            local t = Clamp((val-minVal)/(maxVal-minVal),0,1)
            local pos = x0s + t*(sliderW)
            glColor(theme.slider.fill[1], theme.slider.fill[2], theme.slider.fill[3], theme.slider.fill[4])
            glRect(Snap(x0s), Snap(tY0), Snap(pos), Snap(tY1))

            local r = 5
            glColor(theme.slider.knob[1], theme.slider.knob[2], theme.slider.knob[3], theme.slider.knob[4])
            glBeginEnd(GL_TRIANGLE_FAN, function()
                for i=0,12 do
                    local a = (i/12)*2*math.pi
                    glVertex(Snap(pos+math.cos(a)*r), Snap((tY0+tY1)/2+math.sin(a)*r))
                end
            end)
            return {x0=x0s,y0=tY0-4,x1=x1s,y1=tY1+4}
        end

        local countLabelY  = pattY0 - 22
        local countSliderY = countLabelY - 8
        glText("Spawn Count: "..tostring(spawnCount),
            Snap(labelX), Snap(countLabelY+3), theme.fontSize.normal, "o")
        hitBoxes.sliderCount = drawSlider(labelX, countSliderY, spawnCount,   1, 100)

        local spaceLabelY  = countSliderY - 22
        local spaceSliderY = spaceLabelY - 8
        glText("Spacing: "..tostring(spacingValue),
            Snap(labelX), Snap(spaceLabelY+3), theme.fontSize.normal, "o")
        hitBoxes.sliderSpace = drawSlider(labelX, spaceSliderY, spacingValue, 0, 128)

        listTop = tpY0 - 10
    else
        listTop = searchY0 - 30
    end

    ----------------------------------------------------------------
    -- CEG list
    ----------------------------------------------------------------
    local listX0 = x0 + PADDING_OUTER
    local listX1 = x1 - PADDING_OUTER
    local rowH   = 22
    local colPad = 6
    local footerH= 26

    local rows = 25
    currentRows = rows

    local listBottom = y0 + footerH + 4

    glColor(theme.list.bg[1], theme.list.bg[2], theme.list.bg[3], theme.list.bg[4])
    glRect(Snap(listX0), Snap(listTop - rows*rowH - 8), Snap(listX1), Snap(listTop))

    hitBoxes.listCells = {}
    local colW = (listX1 - listX0 - colPad)/2

    local startIdx = pageIndex * ItemsPerPage() + 1
    local endIdx   = math.min(#filteredCEGs, startIdx + ItemsPerPage() - 1)

    local idx = startIdx
    local baseY = listTop - 4

    for row=1,rows do
        local y1r = baseY - (row-1)*rowH
        local y0r = y1r - rowH + 2
        for col=1,GRID_COLS do
            if idx > endIdx then break end
            local xCell0 = listX0 + (col-1)*(colW+colPad)
            local xCell1 = xCell0 + colW
            local name   = filteredCEGs[idx]
            local selected = name and selectedCEGs[name] and true or false
            local bg = selected and theme.list.rowBgSel or theme.list.rowBg
            glColor(bg[1],bg[2],bg[3],bg[4])
            glRect(Snap(xCell0), Snap(y0r), Snap(xCell1), Snap(y1r))

            glColor(theme.list.border[1], theme.list.border[2], theme.list.border[3], theme.list.border[4])
            glRect(Snap(xCell0), Snap(y0r), Snap(xCell1), Snap(y0r+1))

            local txtCol = selected and theme.list.rowTextSel or theme.list.rowText
            glColor(txtCol[1],txtCol[2],txtCol[3],txtCol[4])
            local show = name
            if #show > 28 then show = show:sub(1,26).."..."
            end
            glText(show, Snap(xCell0+6), Snap(y0r+4), theme.fontSize.list, "o")

            hitBoxes.listCells[idx] = {xCell0, y0r, xCell1, y1r, name = name}
            idx = idx+1
            if idx> endIdx then break end
        end
        if idx> endIdx then break end
    end

    ----------------------------------------------------------------
    -- Pager
    ----------------------------------------------------------------
    local pagerH    = 18
    local pagerY0   = y0 + (footerH - pagerH) * 0.5
    local midX      = (listX0 + listX1) * 0.5
    local pPrevX0   = midX - 60
    local pPrevX1   = pPrevX0 + 30
    local pNextX1   = midX + 60
    local pNextX0   = pNextX1 - 30

    DrawButton(pPrevX0, pagerY0, pPrevX1, pagerY0+pagerH, "<", false, false, theme.fontSize.normal)
    DrawButton(pNextX0, pagerY0, pNextX1, pagerY0+pagerH, ">", false, false, theme.fontSize.normal)
    hitBoxes.pagerPrev = {id="page_prev",x0=pPrevX0,y0=pagerY0,x1=pPrevX1,y1=pagerY0+pagerH}
    hitBoxes.pagerNext = {id="page_next",x0=pNextX0,y0=pagerY0,x1=pNextX1,y1=pagerY0+pagerH}

    local totalPages = math.max(1, math.floor((#filteredCEGs - 1)/ItemsPerPage()) + 1)
    local curPage = math.min(totalPages, pageIndex+1)
    glColor(theme.text.normal[1],theme.text.normal[2],theme.text.normal[3],theme.text.normal[4])
    glText(string.format("Page %d / %d", curPage, totalPages),
           Snap(midX - 35), Snap(pagerY0+3), theme.fontSize.normal, "o")
end

--------------------------------------------------------------------------------
-- Mouse handling
--------------------------------------------------------------------------------

function widget:MousePress(mx, my, button)
    if MouseInWindow(mx,my) then
        if button ~= 1 then
            return true
        end

        local tb = hitBoxes.titleButtons or {}
        local close = tb.close
        local icon  = tb.icon

        if close and mx>=close.x0 and mx<=close.x1 and my>=close.y0 and my<=close.y1 then
            widgetHandler:RemoveWidget(self)
            return true
        end
        if icon and mx>=icon.x0 and mx<=icon.x1 and my>=icon.y0 and my<=icon.y1 then
            local topY = winY + winH
            collapsed = not collapsed
            if collapsed then
                prevWinH = winH
                winH = 260
                winY = topY - winH
            else
                if prevWinH then
                    winH = prevWinH
                    winY = topY - winH
                    ClampWindowPosition()
                end
            end
            return true
        end

        local titleH = 30
        if my >= winY+winH-titleH and my <= winY+winH then
            draggingWin = true
            dragOffX = mx-winX
            dragOffY = my-winY
            return true
        end

        local topButtons = hitBoxes.topButtons or {}
        local cheat    = topButtons.cheat
        local glob     = topButtons.glob
        local resetSel = topButtons.resetSel

        if cheat and mx>=cheat.x0 and mx<=cheat.x1 and my>=cheat.y0 and my<=cheat.y1 then
            cheatOn = not cheatOn
            spSendCommands("cheat")
            return true
        end
        if glob and mx>=glob.x0 and mx<=glob.x1 and my>=glob.y0 and my<=glob.y1 then
            globallosOn = not globallosOn
            spSendCommands("globallos")
            return true
        end
        if resetSel and mx>=resetSel.x0 and mx<=resetSel.x1 and my>=resetSel.y0 and my<=resetSel.y1 then
            selectedCEGs = {}
            lastSelected = nil
            spawnMode    = false
            spEcho("[CEG Browser Lua] Selection reset.")
            return true
        end

        local rb = hitBoxes.reloadBtn
        if rb and mx>=rb.x0 and mx<=rb.x1 and my>=rb.y0 and my<=rb.y1 then
            LoadAllCEGs()
            RebuildFiltered()
            return true
        end
        local tbx = hitBoxes.tuningBtn
        if tbx and mx>=tbx.x0 and mx<=tbx.x1 and my>=tbx.y0 and my<=tbx.y1 then
            tuningVisible = not tuningVisible
            return true
        end

        for _,ab in ipairs(hitBoxes.alphaButtons or {}) do
            if mx>=ab.x0 and mx<=ab.x1 and my>=ab.y0 and my<=ab.y1 then
                if ab.label=="All" then
                    letterFilter = nil
                else
                    letterFilter = string.lower(ab.label)
                end
                pageIndex = 0
                RebuildFiltered()
                return true
            end
        end

        local sb = hitBoxes.searchBox
        local sc = hitBoxes.searchClear
        if sc and mx>=sc.x0 and mx<=sc.x1 and my>=sc.y0 and my<=sc.y1 then
            searchText = ""
            RebuildFiltered()
            return true
        end
        if sb and mx>=sb.x0 and mx<=sb.x1 and my>=sb.y0 and my<=sb.y1 then
            searchFocused = true
            return true
        else
            searchFocused = false
        end

        if collapsed then
            return true
        end

        if tuningVisible then
            for _,pb in ipairs(hitBoxes.patternBtns or {}) do
                if mx>=pb.x0 and mx<=pb.x1 and my>=pb.y0 and my<=pb.y1 then
                    pattern = pb.name
                    return true
                end
            end

            local scb = hitBoxes.sliderCount
            local ssb = hitBoxes.sliderSpace
            if scb and mx>=scb.x0 and mx<=scb.x1 and my>=scb.y0 and my<=scb.y1 then
                draggingSlider = "count"
                local t = Clamp((mx - scb.x0)/(scb.x1-scb.x0),0,1)
                spawnCount = Clamp(math.floor(t*100+0.5),1,100)
                return true
            end
            if ssb and mx>=ssb.x0 and mx<=ssb.x1 and my>=ssb.y0 and my<=ssb.y1 then
                draggingSlider = "spacing"
                local t = Clamp((mx - ssb.x0)/(ssb.x1-ssb.x0),0,1)
                spacingValue = Clamp(math.floor(t*128+0.5),0,128)
                return true
            end
        end

        for idx,box in pairs(hitBoxes.listCells or {}) do
            local xA, y0r, xB, y1r = box[1], box[2], box[3], box[4]
            if mx>=xA and mx<=xB and my>=y0r and my<=y1r then
                local name = box.name or filteredCEGs[idx]
                if not name then
                    return true
                end
                local alt, ctrl, meta, shift = spGetModKeyState()
                if ctrl then
                    if selectedCEGs[name] then
                        selectedCEGs[name] = nil
                        if lastSelected == name then
                            lastSelected = nil
                        end
                        spEcho("[CEG Browser Lua] Unselected: " .. name)
                    else
                        selectedCEGs[name] = true
                        lastSelected = name
                        spEcho("[CEG Browser Lua] Selected: " .. name)
                    end
                else
                    selectedCEGs = {}
                    selectedCEGs[name] = true
                    lastSelected = name
                    spEcho("[CEG Browser Lua] Selected (single): " .. name)
                end
                spawnMode = next(selectedCEGs) ~= nil
                return true
            end
        end

        local pr = hitBoxes.pagerPrev
        local ne = hitBoxes.pagerNext
        if pr and mx>=pr.x0 and mx<=pr.x1 and my>=pr.y0 and my<=pr.y1 then
            pageIndex = math.max(0,pageIndex-1)
            return true
        end
        if ne and mx>=ne.x0 and mx<=ne.x1 and my>=ne.y0 and my<=ne.y1 then
            local maxPage = math.max(0, math.floor((#filteredCEGs - 1) / ItemsPerPage()))
            if pageIndex < maxPage then pageIndex = pageIndex + 1 end
            return true
        end

        return true
    end

    if button == 3 and spawnMode then
        spawnMode = false
        return false
    end
    if button ~= 1 or not spawnMode then
        return false
    end

    local list = {}
    for i = 1, #filteredCEGs do
        local n = filteredCEGs[i]
        if selectedCEGs[n] then
            list[#list+1] = n
        end
    end
    if #list == 0 then
        spEcho("[CEG Browser Lua] No CEGs selected.")
        spawnMode = false
        return false
    end

    local typ, pos = spTraceScreenRay(mx, my, true)
    if typ ~= "ground" or not pos then
        spEcho("[CEG Browser Lua] Map click did not hit ground.")
        return false
    end
    local wx = math.floor(pos[1])
    local wz = math.floor(pos[3])

    if #list == 1 then
        SendSpawnCEG(list[1], wx, wz)
    else
        SendSpawnMultiCEG(list, wx, wz)
    end

    return true
end

function widget:MouseMove(mx, my, dx, dy, button)
    if draggingWin then
        winX = mx - dragOffX
        winY = my - dragOffY
        ClampWindowPosition()
        return true
    end

    if draggingSlider and tuningVisible then
        if draggingSlider == "count" and hitBoxes.sliderCount then
            local b = hitBoxes.sliderCount
            local t = Clamp((mx - b.x0)/(b.x1-b.x0),0,1)
            spawnCount = Clamp(math.floor(t*100+0.5),1,100)
            return true
        elseif draggingSlider == "spacing" and hitBoxes.sliderSpace then
            local b = hitBoxes.sliderSpace
            local t = Clamp((mx - b.x0)/(b.x1-b.x0),0,1)
            spacingValue = Clamp(math.floor(t*128+0.5),0,128)
            return true
        end
    end

    return MouseInWindow(mx,my)
end

function widget:MouseRelease(mx, my, button)
    if button == 1 then
        draggingWin   = false
        draggingSlider= nil
    end
    return MouseInWindow(mx,my)
end

--------------------------------------------------------------------------------
-- Keyboard / search text input
--------------------------------------------------------------------------------

function widget:KeyPress(key, mods, isRepeat)
    if key == string.byte("x") and mods.alt and not mods.ctrl and not mods.shift then
        widgetHandler:RemoveWidget(self)
        return true
    end

    if searchFocused then
        if key == 8 then -- backspace
            if #searchText > 0 then
                searchText = searchText:sub(1, #searchText - 1)
                RebuildFiltered()
            end
            return true
        end
        if key == 13 then -- enter
            return true
        end
        return true
    end

    return false
end

function widget:KeyRelease(key, mods)
    if searchFocused then
        return true
    end
    return false
end

function widget:TextInput(ch)
    if not searchFocused then
        return false
    end
    if not ch or ch == "" then
        return true
    end
    if ch < " " then
        return true
    end
    searchText = searchText .. ch
    RebuildFiltered()
    return true
end

--------------------------------------------------------------------------------
-- CLI: /luaui ceglist and /luaui ceg <name>
--------------------------------------------------------------------------------

function widget:TextCommand(cmd)
    if not cmd or cmd == "" then
        return false
    end

    if cmd == "ceglist" then
        if not allCEGs or #allCEGs == 0 then
            LoadAllCEGs()
            RebuildFiltered()
        end
        spEcho("[CEG Browser] First 50 CEGs:")
        for i = 1, math.min(50, #allCEGs) do
            spEcho("  " .. allCEGs[i])
        end
        return true
    end

    if cmd:sub(1,4) == "ceg " then
        local cegName = cmd:sub(5)
        cegName = cegName:match("^%s*(.-)%s*$")
        if cegName == "" then
            spEcho("[CEG Browser Lua] Usage: /luaui ceg <cegName>")
            return true
        end

        local mx, my = spGetMouseState()
        local typ, pos = spTraceScreenRay(mx, my, true)
        if typ ~= "ground" or not pos then
            spEcho("[CEG Browser Lua] /luaui ceg: mouse is not over ground")
            return true
        end

        SendSpawnCEG(cegName, math.floor(pos[1]), math.floor(pos[3]))
        return true
    end

    return false
end
