local options = PZAPI.ModOptions:create("B42WoodCutterTreeOutline", "Wood Cutter Tree Outline")
local outlineRange = options:addSlider("outlineRange", "IGUI_WoodCutter_OutlineRange", 0, 10, 1, 5)
options:addDescription("IGUI_WoodCutter_OutlineRangeHelp")
local alwaysShow = options:addTickBox("alwaysShow", "IGUI_WoodCutter_AlwaysShow", false)
options:addDescription("IGUI_WoodCutter_AlwaysShowHelp")
local showInVehicle = options:addTickBox("showInVehicle", "IGUI_WoodCutter_ShowInVehicle", false)
options:addDescription("IGUI_WoodCutter_ShowInVehicleHelp")

local function applyRange(value)
    value = tonumber(value) or 5
    if value ~= value or value == math.huge or value == -math.huge then value = 5 end
    value = math.max(0, math.min(10, math.floor(value + 0.5)))
    outlineRange:setValue(value)
    if WoodCutterTreeOutline and WoodCutterTreeOutline.setOutlineRange then
        WoodCutterTreeOutline.setOutlineRange(value)
    end
end

local function applyModes()
    if WoodCutterTreeOutline then
        if WoodCutterTreeOutline.setAlwaysShow then
            WoodCutterTreeOutline.setAlwaysShow(alwaysShow:getValue() == true)
        end
        if WoodCutterTreeOutline.setShowInVehicle then
            WoodCutterTreeOutline.setShowInVehicle(showInVehicle:getValue() == true)
        end
    end
end

-- Read only our own persisted value at boot. Vanilla owns saving; avoid a global
-- ModOptions load/save while other pages may still be registering.
local function loadOptions()
    if getFileReader then
        local reader = getFileReader("ModOptions.ini", false)
        if reader then
            while true do
                local line = reader:readLine()
                if not line then break end
                local kind, id, value = string.match(line, "^(%w+)|B42WoodCutterTreeOutline|([^|]+)|([^|]+)$")
                if kind == "slider" and id == "outlineRange" then
                    outlineRange.value = tonumber(value) or 5
                elseif kind == "tickbox" and (value == "true" or value == "false") then
                    if id == "alwaysShow" then alwaysShow.value = value == "true" end
                    if id == "showInVehicle" then showInVehicle.value = value == "true" end
                end
            end
            reader:close()
        end
    end
    applyRange(outlineRange:getValue())
    applyModes()
end

outlineRange.onChangeApply = function(self, value) applyRange(value) end
alwaysShow.onChangeApply = function(self, value) self:setValue(value == true); applyModes() end
showInVehicle.onChangeApply = function(self, value) self:setValue(value == true); applyModes() end
Events.OnGameBoot.Add(loadOptions)

local function updateOutline(player)
    if WoodCutterTreeOutline and WoodCutterTreeOutline.update then
        WoodCutterTreeOutline.update(player)
    end
end

local function clearOutline()
    if WoodCutterTreeOutline and WoodCutterTreeOutline.reset then
        WoodCutterTreeOutline.reset()
    end
end

local function startOutline()
    clearOutline()
    applyRange(outlineRange:getValue())
    applyModes()
end

Events.OnPlayerUpdate.Add(updateOutline)
Events.OnMainMenuEnter.Add(clearOutline)
Events.OnGameStart.Add(startOutline)
