local options = PZAPI.ModOptions:create("B42WoodCutterTreeOutline", "Wood Cutter Tree Outline")
local outlineRange = options:addSlider("outlineRange", "IGUI_WoodCutter_OutlineRange", 0, 10, 1, 5)
options:addDescription("IGUI_WoodCutter_OutlineRangeHelp")
local ambientEnabled = options:addTickBox("ambientEnabled", "IGUI_WoodCutter_AmbientEnabled", true, "IGUI_WoodCutter_AmbientEnabledHelp")
-- Persist only this setting so a hotkey cannot save unrelated pending options.
local function saveAmbientEnabled(enabled)
    if not getFileReader or not getFileWriter then return end
    local lines = {}
    local reader = getFileReader("ModOptions.ini", false)
    if reader then
        while true do
            local line = reader:readLine()
            if not line then break end
            if not string.match(line, "^tickbox|B42WoodCutterTreeOutline|ambientEnabled|") then
                lines[#lines+1] = line
            end
        end
        reader:close()
    end
    local writer = getFileWriter("ModOptions.ini", false, false)
    if not writer then return end
    for _, line in ipairs(lines) do writer:write(line .. "\r\n") end
    writer:write("tickbox|B42WoodCutterTreeOutline|ambientEnabled|" .. tostring(enabled) .. "\r\n")
    writer:close()
    local other = PZAPI.ModOptions.OtherOptions
    if other then
        for index = #other, 1, -1 do
            if string.match(other[index], "^tickbox|B42WoodCutterTreeOutline|ambientEnabled|") then
                table.remove(other, index)
            end
        end
    end
end
local function setAmbientEnabled(enabled, persist)
    enabled = enabled == true
    ambientEnabled:setValue(enabled)
    if WoodCutterTreeOutline and WoodCutterTreeOutline.setAmbientEnabled then
        WoodCutterTreeOutline.setAmbientEnabled(enabled)
    end
    if persist ~= false then saveAmbientEnabled(enabled) end
end
local function syncAmbientEnabled()
    if WoodCutterTreeOutline and WoodCutterTreeOutline.getAmbientEnabled then
        ambientEnabled:setValue(WoodCutterTreeOutline.getAmbientEnabled())
    end
end
ambientEnabled.onChange = function(self, enabled) setAmbientEnabled(enabled) end
ambientEnabled.onChangeApply = ambientEnabled.onChange
local walkingRange = options:addSlider("walkingRange", "IGUI_WoodCutter_WalkingRange", 0, 10, 1, 0)
options:addDescription("IGUI_WoodCutter_WalkingRangeHelp")
local vehicleRange = options:addSlider("vehicleRange", "IGUI_WoodCutter_VehicleRange", 0, 20, 1, 0)
options:addDescription("IGUI_WoodCutter_VehicleRangeHelp")

local toggleKey = options:addKeyBind("toggleAmbient", "IGUI_WoodCutter_ToggleAmbient", 0, "IGUI_WoodCutter_ToggleAmbientHelp")

local function installKeyBinding()
    if MainOptions and MainOptions.addModOptionsPanel and ISSetKeybindDialog then
        require("WoodCutter/KeyBinding").install(toggleKey, syncAmbientEnabled)
    end
end
Events.OnGameBoot.Add(installKeyBinding)
Events.OnMainMenuEnter.Add(installKeyBinding)
Events.OnGameStart.Add(installKeyBinding)
local baseColor = options:addColorPicker("baseColor", "IGUI_WoodCutter_BaseColor", 128/255, 128/255, 128/255, 1)
local targetColor = options:addColorPicker("targetColor", "IGUI_WoodCutter_TargetColor", 0, 1, 0, 1)

local function channel(value, fallback)
    value = tonumber(value)
    if not value or value ~= value or value == math.huge or value == -math.huge then return fallback end
    return math.max(0, math.min(1, value))
end
local function applyColors()
    for _, entry in ipairs({{baseColor, 128/255, 128/255, 128/255}, {targetColor, 0, 1, 0}}) do
        local option = entry[1]
        local color = option:getValue() or {}
        option:setValue({r=channel(color.r,entry[2]), g=channel(color.g,entry[3]), b=channel(color.b,entry[4]), a=channel(color.a,1)})
    end
    if WoodCutterTreeOutline then
        local base, target = baseColor:getValue(), targetColor:getValue()
        WoodCutterTreeOutline.setBaseColor(base.r, base.g, base.b, base.a)
        WoodCutterTreeOutline.setTargetColor(target.r, target.g, target.b, target.a)
    end
end
for _, option in ipairs({baseColor, targetColor}) do
    option.onChangeApply = function(self, value) self.color = value; applyColors() end
end
local function installColorPicker()
    if MainOptions and MainOptions.onModColorPick then
        require("WoodCutter/ColorPicker").install("B42WoodCutterTreeOutline")
    end
end
Events.OnGameBoot.Add(installColorPicker)
Events.OnMainMenuEnter.Add(installColorPicker)
Events.OnGameStart.Add(installColorPicker)
local function normalize(value, maximum, fallback)
    value = tonumber(value) or fallback
    if value ~= value or value == math.huge or value == -math.huge then value = fallback end
    return math.max(0, math.min(maximum, math.floor(value + 0.5)))
end
local function applyRanges()
    outlineRange:setValue(normalize(outlineRange:getValue(), 10, 5))
    walkingRange:setValue(normalize(walkingRange:getValue(), 10, 0))
    vehicleRange:setValue(normalize(vehicleRange:getValue(), 20, 0))
    if WoodCutterTreeOutline then
        WoodCutterTreeOutline.setOutlineRange(outlineRange:getValue())
        WoodCutterTreeOutline.setWalkingRange(walkingRange:getValue())
        WoodCutterTreeOutline.setVehicleRange(vehicleRange:getValue())
    end
end
local function legacyEntry(line)
    local kind, id = string.match(line, "^(%w+)|B42WoodCutterTreeOutline|([^|]+)|")
    return kind == "tickbox" and (id == "alwaysShow" or id == "showInVehicle")
end
-- Read and migrate only this category. Never reload/save all registered pages:
-- other mods may not have registered their options at boot yet.
local function loadOptions()
    local lines, old, seen, migrate = {}, {}, {}, false
    local reader = getFileReader and getFileReader("ModOptions.ini", false)
    if reader then
        while true do
            local line = reader:readLine()
            if not line then break end
            lines[#lines+1] = line
            local kind, id, value = string.match(line, "^(%w+)|B42WoodCutterTreeOutline|([^|]+)|([^|]+)$")
            if kind == "slider" and options:getOption(id) then
                options:getOption(id).value = tonumber(value)
                seen[id] = true
            elseif kind == "colorpicker" and (id == "baseColor" or id == "targetColor") then
                local r,g,b,a = string.match(value, "^(%S+)%s+(%S+)%s+(%S+)%s+(%S+)$")
                if r then options:getOption(id).color = {r=tonumber(r),g=tonumber(g),b=tonumber(b),a=tonumber(a)} end
            elseif kind == "keybind" and id == "toggleAmbient" then
                toggleKey:setValue(normalize(value, 255, 0))
            elseif kind == "tickbox" and id == "ambientEnabled" and (value == "true" or value == "false") then
                ambientEnabled:setValue(value == "true")
            elseif legacyEntry(line) then
                old[id] = value == "true"
                migrate = true
            end
        end
        reader:close()
    end
    setAmbientEnabled(ambientEnabled:getValue(), false)
    applyColors()
    local previousRange = normalize(outlineRange:getValue(), 10, 5)
    if not seen.walkingRange then walkingRange.value = old.alwaysShow and previousRange or 0 end
    if not seen.vehicleRange then vehicleRange.value = old.showInVehicle and previousRange or 0 end
    applyRanges()
    if migrate and getFileWriter then
        local writer = getFileWriter("ModOptions.ini", false, false)
        if writer then
            for _, line in ipairs(lines) do
                local kind, id = string.match(line, "^(%w+)|B42WoodCutterTreeOutline|([^|]+)|")
                if not legacyEntry(line) and not (kind == "slider" and options:getOption(id)) then
                    writer:write(line .. "\r\n")
                end
            end
            for _, id in ipairs({"outlineRange", "walkingRange", "vehicleRange"}) do
                writer:write("slider|B42WoodCutterTreeOutline|" .. id .. "|" .. tostring(options:getOption(id):getValue()) .. "\r\n")
            end
            writer:close()
            -- Vanilla may already have cached removed options as unknown entries.
            local other = PZAPI.ModOptions.OtherOptions
            if other then
                for index = #other, 1, -1 do
                    if legacyEntry(other[index]) then table.remove(other, index) end
                end
            end
        end
    end
end
for _, option in ipairs({outlineRange, walkingRange, vehicleRange}) do
    option.onChangeApply = function(self, value) self.value = value; applyRanges() end
end
Events.OnGameBoot.Add(loadOptions)

local function updateOutline(player)
    if WoodCutterTreeOutline and WoodCutterTreeOutline.update then WoodCutterTreeOutline.update(player) end
end
local function clearOutline()
    if WoodCutterTreeOutline and WoodCutterTreeOutline.reset then WoodCutterTreeOutline.reset() end
end
local function startOutline()
    clearOutline()
    setAmbientEnabled(ambientEnabled:getValue(), false)
    applyColors()
    applyRanges()
end
Events.OnPlayerUpdate.Add(updateOutline)
Events.OnMainMenuEnter.Add(clearOutline)
Events.OnGameStart.Add(startOutline)

-- One saved switch for both ambient modes. Zero radii remain authoritative.
local function onKeyPressed(key)
    local binding = tonumber(toggleKey:getValue()) or 0
    if binding == 0 or key ~= binding then return end
    local dialog = MainOptions and MainOptions.setKeybindDialog
    if dialog and dialog.isVisible and dialog:isVisible() then return end
    local player = getSpecificPlayer and getSpecificPlayer(0)
    if not player or not player:isLocalPlayer() or player:isDead() or player:getJoypadBind() ~= -1 then return end
    if WoodCutterTreeOutline and WoodCutterTreeOutline.setAmbientEnabled then
        setAmbientEnabled(not WoodCutterTreeOutline.getAmbientEnabled())
    end
end
Events.OnKeyPressed.Add(onKeyPressed)
