local Compatibility = {}
local installedClass
local installedPage
local activePicker
local pickerOwner
local suppressEscape = false
local applyKeys = { "outlineRange", "walkingRange", "vehicleRange", "baseColor", "targetColor" }

local function copyColor(color)
    return { r = color.r, g = color.g, b = color.b, a = color.a }
end

function Compatibility.install(modId, picker, colorData, persistColor)
    local screenClass = ModOptionsScreen
    local page = PZAPI.ModOptions:getOptions(modId)
    if screenClass == nil or page == nil or type(screenClass.onModColorPick) ~= "function" then return end
    if installedPage ~= page then
        local previousApply = page.apply
        page.apply = function(self, ...)
            if previousApply ~= nil then previousApply(self, ...) end
            local screen = ModOptionsScreen ~= nil and ModOptionsScreen.instance or nil
            if screen == nil or not screen:isReallyVisible() then return end
            -- The manager commits pending values before this page-level callback.
            -- Replay only our backend callbacks, never another page's options.
            for _, key in ipairs(applyKeys) do
                local option = self:getOption(key)
                if option ~= nil and option.onChangeApply ~= nil then
                    option:onChangeApply(option:getValue())
                end
            end
        end
        installedPage = page
    end
    if installedClass == screenClass then return end
    local previousPick = screenClass.onModColorPick
    screenClass.onModColorPick = function(screen, button)
        local option = button ~= nil and button.option or nil
        local data = option ~= nil and colorData[option.id] or nil
        if data == nil or page:getOption(option.id) ~= option then
            return previousPick(screen, button)
        end
        pickerOwner = screen
        activePicker = picker.open({
            titleKey = data.titleKey,
            defaultColor = data.defaultColor,
            getColor = function()
                return copyColor(option.pendingColor or button.backgroundColor or option:getValue())
            end,
            setColor = function(color)
                option.pendingColor = copyColor(color)
                button.backgroundColor = copyColor(color)
                screen.optionsChanged = true
            end,
            saveColor = function(color)
                if option.onChangeApply ~= nil then option:onChangeApply(color)
                else option:setValue(color) end
                if persistColor(modId, option.id, option:getValue()) == false then return false end
                option.pendingColor = nil
                button.backgroundColor = copyColor(option:getValue())
                return true
            end,
            isOwnerVisible = function()
                return ModOptionsScreen.instance == screen and screen:isReallyVisible()
            end,
        })
        return activePicker
    end
    local previousKeyRelease = screenClass.onKeyRelease
    screenClass.onKeyRelease = function(screen, key, ...)
        if screen == pickerOwner then
            if key == Keyboard.KEY_ESCAPE and suppressEscape then return true end
            if activePicker ~= nil and picker.getInstance() == activePicker then
                if key == Keyboard.KEY_RETURN then return true end
                if key == Keyboard.KEY_ESCAPE then
                    -- Mod Manager also sends a synthetic release on key press.
                    if isKeyDown == nil or not isKeyDown(key) then
                        activePicker:onClose()
                        suppressEscape = true
                        local function restore()
                            Events.OnTick.Remove(restore)
                            suppressEscape = false
                        end
                        Events.OnTick.Add(restore)
                    end
                    return true
                end
            end
        end
        return previousKeyRelease(screen, key, ...)
    end
    installedClass = screenClass
end

return Compatibility
