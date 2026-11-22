local options = PZAPI.ModOptions:create("B42WoodCutterTreeOutline", "Wood Cutter Tree Outline")
local outlineRange = options:addSlider("outlineRange", "IGUI_WoodCutter_OutlineRange", 0, 10, 1, 5)
options:addDescription("IGUI_WoodCutter_OutlineRangeHelp")
local walkingRange = options:addSlider("walkingRange", "IGUI_WoodCutter_WalkingRange", 0, 10, 1, 0)
options:addDescription("IGUI_WoodCutter_WalkingRangeHelp")
local vehicleRange = options:addSlider("vehicleRange", "IGUI_WoodCutter_VehicleRange", 0, 20, 1, 0)
options:addDescription("IGUI_WoodCutter_VehicleRangeHelp")

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
            elseif legacyEntry(line) then
                old[id] = value == "true"
                migrate = true
            end
        end
        reader:close()
    end
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
    applyRanges()
end
Events.OnPlayerUpdate.Add(updateOutline)
Events.OnMainMenuEnter.Add(clearOutline)
Events.OnGameStart.Add(startOutline)
