-- Keep native dialog lookup identity separate from translated display text.
local KeyBinding = {}
local installed = false

function KeyBinding.install(option, syncState)
    if installed or not MainOptions or not MainOptions.addModOptionsPanel
            or not ISSetKeybindDialog or not ISSetKeybindDialog.onDefault then return end

    local buildPanel = MainOptions.addModOptionsPanel
    MainOptions.addModOptionsPanel = function(self, ...)
        local result = buildPanel(self, ...)
        local row = option.element
        if row and row.txt and row.btn and row.btn.isModBind and row.btn.internal == option.name then
            row.txt:setName(option.name)
            row.txt:setTranslation(getText(option.name))
        end
        if syncState then syncState() end
        return result
    end

    -- Vanilla's Mod Options default branch searches translated label names,
    -- while assignment, Clear and conflict handling require the raw identity.
    local defaultBinding = ISSetKeybindDialog.onDefault
    ISSetKeybindDialog.onDefault = function(self, ...)
        if self.isModBind and self.keybindName == option.name then
            local row = option.element
            if row and row.defaultKeyCode and row.defaultKeyCode > 0 then
                return MainOptions.keyPressHandler(row.defaultKeyCode)
            end
            return self:onClear()
        end
        return defaultBinding(self, ...)
    end
    installed = true
end

return KeyBinding
