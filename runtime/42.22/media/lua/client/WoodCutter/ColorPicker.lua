-- Adapted Hi-Res-Clock RGBA/HSV picker with owned reset and persistence controls.
pcall(require, "ISUI/ISPanel")
pcall(require, "ISUI/ISButton")
pcall(require, "ISUI/ISLabel")
pcall(require, "RadioCom/ISUIRadio/ISSliderPanel")
pcall(require, "ISUI/ISTextEntryBox")

local ColorPicker = {}
local Hotpath = require("WoodCutter/UIHotpath")

local Frame = ISPanel:derive("WoodCutterColorPickerFrame")
local Window = ISPanel:derive("WoodCutterColorPickerWindow")
local activeFrame = nil
local activeWindow = nil
local originalModColorPick = nil
local installed = false

local OPTION_DATA = {
    baseColor = {titleKey = "IGUI_WoodCutter_BaseColor", defaultColor = {r=128/255,g=128/255,b=128/255,a=1}},
    targetColor = {titleKey = "IGUI_WoodCutter_TargetColor", defaultColor = {r=0,g=1,b=0,a=1}},
}
local OPTION_TITLES = {}
local CHANNELS = {
    { key = "r", label = "R" },
    { key = "g", label = "G" },
    { key = "b", label = "B" },
    { key = "a", label = "A" },
}

local FOUR_K_SCREEN_REFERENCE_HEIGHT = 2160
local FOUR_K_SMALL_FONT_REFERENCE_HEIGHT = 38
local REFERENCE_OUTER_PADDING = 14
local REFERENCE_CHANNEL_LABEL_WIDTH = 20
local REFERENCE_CONTROL_HORIZONTAL_GAP = 24
local REFERENCE_SLIDER_WIDTH = 230
local REFERENCE_ENTRY_WIDTH = 58
local REFERENCE_ENTRY_COLOR_GAP = 22
local REFERENCE_COLOR_BOX_SIZE = 206
local REFERENCE_HUE_BAR_GAP = 12
local REFERENCE_HUE_BAR_WIDTH = 22
local REFERENCE_HUE_RIGHT_SPACE = 20
local REFERENCE_SWATCH_Y = 12
local REFERENCE_SWATCH_WIDTH = 70
local REFERENCE_SWATCH_HEIGHT = 38
local REFERENCE_SWATCH_COLOR_GAP = 12
local REFERENCE_BUTTON_HEIGHT = 30
local REFERENCE_REVERT_BUTTON_WIDTH = 170
local REFERENCE_CLOSE_BUTTON_WIDTH = 130
local REFERENCE_PICKER_X_OFFSET = 314
local REFERENCE_CONTROL_HEIGHT = 24
local REFERENCE_ENTRY_HEIGHT = 42
local REFERENCE_COLOR_INSET = 1
local REFERENCE_CURSOR_OUTER_SIZE = 13
local REFERENCE_CURSOR_INNER_SIZE = 11
local REFERENCE_CURSOR_FILL_SIZE = 7
local REFERENCE_HUE_MARKER_OUTER_PADDING = 3
local REFERENCE_HUE_MARKER_INNER_PADDING = 2
local REFERENCE_HUE_MARKER_OUTER_HEIGHT = 7
local REFERENCE_HUE_MARKER_INNER_HEIGHT = 5
local REFERENCE_SLIDER_BUTTON_WIDTH = 10
local REFERENCE_SLIDER_BUTTON_SPACING = 5
local REFERENCE_SLIDER_BAR_HEIGHT = 2
local REFERENCE_SLIDER_THUMB_WIDTH = 5
local COLOR_BOX_CELLS = 48
local HUE_BAR_STEPS = 36
local REVERT_BORDER_COLOR = { r = 0.9, g = 0.15, b = 0.15, a = 1 }
local buttonMetricsCache = nil

local function clamp01(value, fallback)
    local number = tonumber(value) or fallback or 0
    if number > 1 then
        number = number / 255
    end
    if number < 0 then
        return 0
    end
    if number > 1 then
        return 1
    end
    return number
end

local function colorByte(value)
    local number = math.floor(clamp01(value, 0) * 255 + 0.5)
    if number < 0 then
        return 0
    end
    if number > 255 then
        return 255
    end
    return number
end

local function safeText(key, fallback)
    if getText ~= nil then
        local text = getText(key)
        if text ~= nil and text ~= "" and text ~= key then
            return text
        end
    end
    return fallback or tostring(key)
end

local function optionTitle(config)
    local data = OPTION_TITLES[config.titleKey]
    local key = data ~= nil and data.key or config.titleKey
    local fallback = config.title or (data ~= nil and data.fallback) or "Color"
    return safeText(key, fallback)
end

local function colorCopy(color)
    color = color or {}
    return {
        r = clamp01(color.r, 1),
        g = clamp01(color.g, 1),
        b = clamp01(color.b, 1),
        a = clamp01(color.a, 1),
    }
end

-- Save only the confirmed color; unrelated pending options must stay pending.
local function saveColor(modId, optionKey, color)
    if getFileReader == nil or getFileWriter == nil then return false end
    local prefix = "colorpicker|" .. modId .. "|" .. optionKey .. "|"
    local lines = {}
    local reader = getFileReader("ModOptions.ini", false)
    if reader ~= nil then
        while true do
            local line = reader:readLine()
            if line == nil then break end
            if string.sub(line, 1, #prefix) ~= prefix then lines[#lines + 1] = line end
        end
        reader:close()
    end
    local writer = getFileWriter("ModOptions.ini", false, false)
    if writer == nil then return false end
    for _, line in ipairs(lines) do writer:write(line .. "\r\n") end
    writer:write(prefix .. color.r .. " " .. color.g .. " " .. color.b .. " " .. color.a .. "\r\n")
    writer:close()
    local other = PZAPI.ModOptions.OtherOptions
    if other ~= nil then
        for index = #other, 1, -1 do
            if string.sub(other[index], 1, #prefix) == prefix then table.remove(other, index) end
        end
    end
    return true
end

local function rgbToHsv(color)
    local r = clamp01(color.r, 0)
    local g = clamp01(color.g, 0)
    local b = clamp01(color.b, 0)
    local maxValue = math.max(r, g, b)
    local minValue = math.min(r, g, b)
    local delta = maxValue - minValue
    local hue = 0

    if delta ~= 0 then
        if maxValue == r then
            hue = ((g - b) / delta) % 6
        elseif maxValue == g then
            hue = ((b - r) / delta) + 2
        else
            hue = ((r - g) / delta) + 4
        end
        hue = hue / 6
        if hue < 0 then
            hue = hue + 1
        end
    end

    local saturation = maxValue == 0 and 0 or delta / maxValue
    return hue, saturation, maxValue
end

local function hsvToRgb(hue, saturation, value)
    hue = clamp01(hue, 0)
    saturation = clamp01(saturation, 0)
    value = clamp01(value, 0)

    if saturation <= 0 then
        return value, value, value
    end

    local h = hue * 6
    local i = math.floor(h)
    local f = h - i
    local p = value * (1 - saturation)
    local q = value * (1 - saturation * f)
    local t = value * (1 - saturation * (1 - f))
    i = i % 6

    if i == 0 then
        return value, t, p
    elseif i == 1 then
        return q, value, p
    elseif i == 2 then
        return p, value, t
    elseif i == 3 then
        return p, q, value
    elseif i == 4 then
        return t, p, value
    end
    return value, p, q
end

local HUE_BAR_RED = {}
local HUE_BAR_GREEN = {}
local HUE_BAR_BLUE = {}
for index = 0, HUE_BAR_STEPS - 1 do
    local hue = 1 - (index / (HUE_BAR_STEPS - 1))
    local r, g, b = hsvToRgb(hue, 1, 1)
    HUE_BAR_RED[index + 1] = r
    HUE_BAR_GREEN[index + 1] = g
    HUE_BAR_BLUE[index + 1] = b
end

local function getButtonOptionKey(button, modId)
    if button == nil or type(button.optionID) ~= "string" then
        return nil
    end

    local prefix = tostring(modId) .. "."
    if string.sub(button.optionID, 1, string.len(prefix)) ~= prefix then
        return nil
    end
    return string.sub(button.optionID, string.len(prefix) + 1)
end

local function updateGameOption(button, color)
    if button == nil or MainOptions == nil or MainOptions.instance == nil or MainOptions.instance.gameOptions == nil then
        return
    end

    local gameOptions = MainOptions.instance.gameOptions
    local gameOption = gameOptions:get(button.optionID)
    if gameOption ~= nil then
        gameOptions:onChange(gameOption)
        if gameOption.onChange ~= nil then
            gameOption:onChange(color)
        end
    end
end

local function screenSize()
    local core = getCore ~= nil and getCore() or nil
    local screenWidth = core ~= nil and core.getScreenWidth ~= nil and core:getScreenWidth() or 1920
    local screenHeight = core ~= nil and core.getScreenHeight ~= nil and core:getScreenHeight() or 1080
    return screenWidth, screenHeight
end

local function fontHeight(font)
    local manager = getTextManager ~= nil and getTextManager() or nil
    return manager ~= nil and manager.getFontHeight ~= nil and manager:getFontHeight(font)
            or FOUR_K_SMALL_FONT_REFERENCE_HEIGHT
end

local function rounded(value)
    return math.floor((tonumber(value) or 0) + 0.5)
end

local function responsiveMetric(reference, scale, minimum)
    return math.max(minimum or 1, rounded(reference * scale))
end

local function resolveLayoutScale(screenScale, smallFontHeight)
    local fontScale = math.max(0.1,
            (tonumber(smallFontHeight) or FOUR_K_SMALL_FONT_REFERENCE_HEIGHT)
                    / FOUR_K_SMALL_FONT_REFERENCE_HEIGHT)
    if screenScale > 1 then return math.max(fontScale, screenScale) end
    return fontScale
end

local function resolveMetrics()
    local screenWidth, screenHeight = screenSize()
    local screenScale = math.max(0.1,
            (tonumber(screenHeight) or FOUR_K_SCREEN_REFERENCE_HEIGHT)
                    / FOUR_K_SCREEN_REFERENCE_HEIGHT)
    local smallFontHeight = fontHeight(UIFont.Small)
    local scale = resolveLayoutScale(screenScale, smallFontHeight)
    local outerPadding = responsiveMetric(REFERENCE_OUTER_PADDING, scale)
    local labelWidth = responsiveMetric(REFERENCE_CHANNEL_LABEL_WIDTH, scale)
    local controlGap = responsiveMetric(REFERENCE_CONTROL_HORIZONTAL_GAP, scale)
    local sliderWidth = responsiveMetric(REFERENCE_SLIDER_WIDTH, scale)
    local entryWidth = responsiveMetric(REFERENCE_ENTRY_WIDTH, scale)
    local entryColorGap = responsiveMetric(REFERENCE_ENTRY_COLOR_GAP, scale)
    local colorBoxSize = responsiveMetric(REFERENCE_COLOR_BOX_SIZE, scale)
    local hueBarGap = responsiveMetric(REFERENCE_HUE_BAR_GAP, scale)
    local hueBarWidth = responsiveMetric(REFERENCE_HUE_BAR_WIDTH, scale)
    local labelX = outerPadding
    local sliderX = labelX + labelWidth + controlGap
    local entryX = sliderX + sliderWidth + controlGap
    local colorBoxX = entryX + entryWidth + entryColorGap
    local hueBarX = colorBoxX + colorBoxSize + hueBarGap
    local pickerWidth = hueBarX + hueBarWidth
            + responsiveMetric(REFERENCE_HUE_RIGHT_SPACE, scale)
    local swatchY = responsiveMetric(REFERENCE_SWATCH_Y, scale)
    local swatchHeight = responsiveMetric(REFERENCE_SWATCH_HEIGHT, scale)
    local colorBoxY = swatchY + swatchHeight
            + responsiveMetric(REFERENCE_SWATCH_COLOR_GAP, scale)
    local buttonHeight = responsiveMetric(REFERENCE_BUTTON_HEIGHT, scale)
    local revertText = safeText("IGUI_WoodCutter_RevertColor", "Revert Color")
    local resetText = safeText("IGUI_WorldMapEditor_Reset",
            safeText("UI_optionscreen_KeybindDefault", "Reset"))
    local applyText = safeText("UI_btn_apply", "Apply")
    local cached = buttonMetricsCache
    if cached == nil or cached.scale ~= scale or cached.revertText ~= revertText
            or cached.resetText ~= resetText or cached.applyText ~= applyText then
        local manager = getTextManager ~= nil and getTextManager() or nil
        local function buttonWidth(text, reference)
            local width = manager ~= nil and manager:MeasureStringX(UIFont.Small, text) or 0
            return math.max(responsiveMetric(reference, scale), width + outerPadding * 2)
        end
        cached = {scale = scale, revertText = revertText, resetText = resetText, applyText = applyText,
            revertWidth = buttonWidth(revertText, REFERENCE_REVERT_BUTTON_WIDTH),
            resetWidth = buttonWidth(resetText, REFERENCE_CLOSE_BUTTON_WIDTH),
            applyWidth = buttonWidth(applyText, REFERENCE_CLOSE_BUTTON_WIDTH)}
        buttonMetricsCache = cached
    end
    pickerWidth = math.max(pickerWidth, cached.revertWidth + cached.resetWidth + cached.applyWidth
            + outerPadding * 4)
    local buttonY = colorBoxY + colorBoxSize + outerPadding
    local pickerHeight = buttonY + buttonHeight + outerPadding
    local colorInset = responsiveMetric(REFERENCE_COLOR_INSET, scale)
    local colorInnerSize = math.max(1, colorBoxSize - colorInset * 2)
    local sliderThumbWidth = responsiveMetric(REFERENCE_SLIDER_THUMB_WIDTH, scale)
    return {
        scale = scale,
        screenScale = screenScale,
        screenWidth = screenWidth,
        screenHeight = screenHeight,
        signature = tostring(screenWidth) .. ":" .. tostring(screenHeight)
                .. ":" .. tostring(smallFontHeight),
        smallFontHeight = smallFontHeight,
        outerPadding = outerPadding,
        channelLabelX = labelX,
        channelLabelWidth = labelWidth,
        controlGap = controlGap,
        controlHeight = responsiveMetric(REFERENCE_CONTROL_HEIGHT, scale),
        entryHeight = responsiveMetric(REFERENCE_ENTRY_HEIGHT, scale),
        sliderX = sliderX,
        sliderWidth = sliderWidth,
        sliderButtonWidth = responsiveMetric(REFERENCE_SLIDER_BUTTON_WIDTH, scale),
        sliderButtonSpacing = responsiveMetric(REFERENCE_SLIDER_BUTTON_SPACING, scale),
        sliderBarHeight = responsiveMetric(REFERENCE_SLIDER_BAR_HEIGHT, scale),
        sliderThumbWidth = sliderThumbWidth,
        sliderThumbOffset = math.floor(sliderThumbWidth / 2),
        entryX = entryX,
        entryWidth = entryWidth,
        colorBoxX = colorBoxX,
        colorBoxY = colorBoxY,
        colorBoxSize = colorBoxSize,
        colorInset = colorInset,
        colorInnerSize = colorInnerSize,
        colorCellSize = colorInnerSize / COLOR_BOX_CELLS,
        hueBarX = hueBarX,
        hueBarWidth = hueBarWidth,
        hueStepHeight = colorInnerSize / HUE_BAR_STEPS,
        hueMarkerOuterPadding = responsiveMetric(REFERENCE_HUE_MARKER_OUTER_PADDING, scale),
        hueMarkerInnerPadding = responsiveMetric(REFERENCE_HUE_MARKER_INNER_PADDING, scale),
        hueMarkerOuterHeight = responsiveMetric(REFERENCE_HUE_MARKER_OUTER_HEIGHT, scale),
        hueMarkerInnerHeight = responsiveMetric(REFERENCE_HUE_MARKER_INNER_HEIGHT, scale),
        cursorOuterSize = responsiveMetric(REFERENCE_CURSOR_OUTER_SIZE, scale),
        cursorInnerSize = responsiveMetric(REFERENCE_CURSOR_INNER_SIZE, scale),
        cursorFillSize = responsiveMetric(REFERENCE_CURSOR_FILL_SIZE, scale),
        swatchY = swatchY,
        titleY = swatchY + math.floor((swatchHeight - smallFontHeight) / 2),
        swatchWidth = responsiveMetric(REFERENCE_SWATCH_WIDTH, scale),
        swatchHeight = swatchHeight,
        buttonHeight = buttonHeight,
        buttonY = buttonY,
        revertButtonWidth = cached.revertWidth,
        resetButtonWidth = cached.resetWidth,
        closeButtonWidth = cached.applyWidth,
        revertText = revertText,
        resetText = resetText,
        applyText = applyText,
        pickerWidth = pickerWidth,
        pickerHeight = pickerHeight,
        pickerXOffset = responsiveMetric(REFERENCE_PICKER_X_OFFSET, scale, 0),
    }
end

ColorPicker.calculateLayoutMetrics = resolveMetrics

local function screenCenter(metrics)
    local screenWidth, screenHeight = screenSize()
    local x = math.floor((screenWidth - metrics.pickerWidth) / 2) + metrics.pickerXOffset
    x = math.max(0, math.min(x, screenWidth - metrics.pickerWidth))
    return x, math.floor((screenHeight - metrics.pickerHeight) / 2)
end

local function closeActiveWindow()
    if activeFrame ~= nil then
        if activeFrame.setCapture ~= nil then
            activeFrame:setCapture(false)
        end
        activeFrame:removeFromUIManager()
        activeFrame = nil
        activeWindow = nil
    elseif activeWindow ~= nil then
        if activeWindow.setCapture ~= nil then
            activeWindow:setCapture(false)
        end
        if activeWindow.parent ~= nil and activeWindow.parent.removeChild ~= nil then
            activeWindow.parent:removeChild(activeWindow)
        else
            activeWindow:removeFromUIManager()
        end
        activeWindow = nil
    end
end

function Frame:initialise()
    ISPanel.initialise(self)
end

function Frame:onMouseDown(x, y)
    return true
end

function Frame:onMouseDownOutside(x, y)
    return true
end

function Frame:onMouseUpOutside(x, y)
    return true
end

function Frame:prerender()
end

function Frame:new(x, y, width, height)
    local o = ISPanel.new(self, x, y, width, height)
    setmetatable(o, self)
    self.__index = self
    o.background = false
    o.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    o.moveWithMouse = false
    return o
end

function Window:initialise()
    ISPanel.initialise(self)
end

local function applySliderMetrics(slider, metrics)
    local buttonWidth = metrics.sliderButtonWidth
    local buttonSpacing = metrics.sliderButtonSpacing
    local barHeight = metrics.sliderBarHeight
    local barX = buttonWidth + buttonSpacing
    slider.btnLeftDim = { x = 0, y = 0, w = buttonWidth, h = metrics.controlHeight }
    slider.btnRightDim = {
        x = metrics.sliderWidth - buttonWidth,
        y = 0,
        w = buttonWidth,
        h = metrics.controlHeight,
    }
    slider.sliderBarDim = {
        x = barX,
        y = math.floor((metrics.controlHeight - barHeight) / 2),
        w = math.max(1, metrics.sliderWidth - barX * 2),
        h = barHeight,
    }
    slider.sliderDim = {
        x = metrics.sliderThumbOffset,
        y = 0,
        w = metrics.sliderThumbWidth,
        h = metrics.controlHeight,
    }
end

function Window:createChildren()
    if ISPanel.createChildren ~= nil then
        ISPanel.createChildren(self)
    end

    local metrics = self.metrics or resolveMetrics()
    self.metrics = metrics
    self.sliders = {}
    self.entries = {}
    self.hueImage = getTexture ~= nil and getTexture("media/ui/ColorPicker/ColorPicker_Hue.png") or nil
    self.satImage = getTexture ~= nil and getTexture("media/ui/ColorPicker/ColorPicker_Sat.png") or nil

    local rowHeight = metrics.entryHeight
    if ISTextEntryBox ~= nil then
        for i = 1, #CHANNELS do
            local channel = CHANNELS[i]
            local entry = ISTextEntryBox:new(tostring(colorByte(self.color[channel.key])),
                    metrics.entryX, 0, metrics.entryWidth, metrics.entryHeight)
            entry:initialise()
            entry:instantiate()
            entry:setHeight(metrics.entryHeight)
            entry:setOnlyNumbers(true)
            entry:setMaxTextLength(3)
            entry:setTextRGBA(1, 1, 1, 1)
            entry:setPlaceholderText("")
            entry.backgroundColor = { r = 0, g = 0, b = 0, a = 0.92 }
            entry.borderColor = { r = 0.6, g = 0.6, b = 0.6, a = 1 }
            if entry.setClearButton ~= nil then
                entry:setClearButton(false)
            end
            entry.channel = channel.key
            entry.onTextChangeFunction = Window.onEntryChanged
            entry.target = self
            self.entries[channel.key] = entry
        end
    end

    local rowGap = math.max(0, metrics.colorBoxSize - rowHeight * #CHANNELS) / (#CHANNELS + 1)
    for i = 1, #CHANNELS do
        local channel = CHANNELS[i]
        local rowY = metrics.colorBoxY + math.floor(rowGap * i + rowHeight * (i - 1) + 0.5)
        local controlY = rowY + math.floor((rowHeight - metrics.controlHeight) / 2)
        if ISLabel ~= nil then
            local label = ISLabel:new(metrics.channelLabelX, rowY, rowHeight,
                    channel.label, 1, 1, 1, 1, UIFont.Small, true)
            label:initialise()
            label:instantiate()
            label:setWidth(metrics.channelLabelWidth)
            Hotpath.installLabel(label)
            self:addChild(label)
        end

        local slider = ISSliderPanel:new(metrics.sliderX, controlY,
                metrics.sliderWidth, metrics.controlHeight,
                self, Window.onSliderChange)
        slider:initialise()
        slider:instantiate()
        Hotpath.installSlider(slider)
        slider:setValues(0, 255, 1)
        applySliderMetrics(slider, metrics)
        slider:setCurrentValue(colorByte(self.color[channel.key]), true)
        slider.valueLabel = false
        slider.channel = channel.key
        self:addChild(slider)
        self.sliders[channel.key] = slider

        local entry = self.entries[channel.key]
        if entry ~= nil then
            entry:setHeight(rowHeight)
            entry:setY(rowY)
            self:addChild(entry)
        end
    end

    self.resetButton = ISButton:new(metrics.outerPadding, metrics.buttonY,
            metrics.revertButtonWidth, metrics.buttonHeight,
            metrics.revertText, self, Window.onReset)
    self.resetButton:initialise()
    self.resetButton:instantiate()
    self.resetButton:setWidth(metrics.revertButtonWidth)
    self.resetButton:setHeight(metrics.buttonHeight)
    self.resetButton.borderColor = REVERT_BORDER_COLOR
    Hotpath.installTextButton(self.resetButton)
    self:addChild(self.resetButton)

    self.defaultButton = ISButton:new(metrics.outerPadding * 2 + metrics.revertButtonWidth,
            metrics.buttonY, metrics.resetButtonWidth, metrics.buttonHeight,
            metrics.resetText, self, Window.onDefault)
    self.defaultButton:initialise()
    self.defaultButton:instantiate()
    self.defaultButton:setWidth(metrics.resetButtonWidth)
    self.defaultButton:setHeight(metrics.buttonHeight)
    Hotpath.installTextButton(self.defaultButton)
    self:addChild(self.defaultButton)

    self.closeButton = ISButton:new(self:getWidth() - metrics.outerPadding - metrics.closeButtonWidth,
            metrics.buttonY, metrics.closeButtonWidth, metrics.buttonHeight,
            metrics.applyText, self, Window.onApply)
    self.closeButton:initialise()
    self.closeButton:instantiate()
    self.closeButton:setWidth(metrics.closeButtonWidth)
    self.closeButton:setHeight(metrics.buttonHeight)
    Hotpath.installTextButton(self.closeButton)
    self:addChild(self.closeButton)
    self:updateRenderCache()
end

function Window:getCurrentColor()
    if self.getColor ~= nil then
        return colorCopy(self.getColor())
    end
    return colorCopy(self.defaultColor)
end

function Window:syncControls(skipEntryKey)
    self.updatingControls = true
    for i = 1, #CHANNELS do
        local key = CHANNELS[i].key
        local value = colorByte(self.color[key])
        if self.sliders[key] ~= nil then
            self.sliders[key]:setCurrentValue(value, true)
        end
        if self.entries[key] ~= nil and key ~= skipEntryKey then
            self.entries[key]:setText(tostring(value))
        end
    end
    self.updatingControls = false
end

function Window:applyColor(syncHsv, skipEntryKey)
    if syncHsv then
        self.hue, self.saturation, self.value = rgbToHsv(self.color)
    end
    self:updateRenderCache()
    self:syncControls(skipEntryKey)
    if self.setColor ~= nil then
        self.setColor(colorCopy(self.color))
    end
end

function Window:updateRenderCache()
    local metrics = self.metrics
    local maxOffset = metrics.colorInnerSize - 1
    self.hiResColorCursorX = metrics.colorBoxX + metrics.colorInset
            + maxOffset * self.saturation
    self.hiResColorCursorY = metrics.colorBoxY + metrics.colorInset
            + maxOffset * (1 - self.value)
    self.hiResHueMarkerY = metrics.colorBoxY + metrics.colorInset
            + maxOffset * (1 - self.hue)
    if self.hiResColorSquareHue == self.hue then return end

    self.hiResColorSquareHue = self.hue
    local red = self.hiResColorSquareRed or {}
    local green = self.hiResColorSquareGreen or {}
    local blue = self.hiResColorSquareBlue or {}
    self.hiResColorSquareRed = red
    self.hiResColorSquareGreen = green
    self.hiResColorSquareBlue = blue
    local index = 1
    for sx = 0, COLOR_BOX_CELLS - 1 do
        local saturation = sx / (COLOR_BOX_CELLS - 1)
        for vy = 0, COLOR_BOX_CELLS - 1 do
            local r, g, b = hsvToRgb(self.hue, saturation,
                    1 - (vy / (COLOR_BOX_CELLS - 1)))
            red[index] = r
            green[index] = g
            blue[index] = b
            index = index + 1
        end
    end
end

function Window:setColorFromVisual()
    local r, g, b = hsvToRgb(self.hue, self.saturation, self.value)
    self.color.r = r
    self.color.g = g
    self.color.b = b
    self:applyColor(false)
end

function Window:onSliderChange(value, slider)
    if self.updatingControls or slider == nil then
        return
    end
    self.color[slider.channel] = math.max(0, math.min(tonumber(value) or 0, 255)) / 255
    self:applyColor(slider.channel ~= "a")
end

function Window:onEntryChanged(entry)
    if self.updatingControls or entry == nil then
        return
    end
    local value = tonumber(entry:getInternalText()) or 0
    value = math.max(0, math.min(value, 255))
    self.color[entry.channel] = value / 255
    self:applyColor(entry.channel ~= "a", entry.channel)
end

function Window:setSaturationValueFromMouse(x, y)
    local metrics = self.metrics
    local left = metrics.colorBoxX + metrics.colorInset
    local top = metrics.colorBoxY + metrics.colorInset
    local maxOffset = metrics.colorInnerSize - 1
    x = math.max(left, math.min(x, left + maxOffset))
    y = math.max(top, math.min(y, top + maxOffset))
    self.saturation = (x - left) / maxOffset
    self.value = 1 - ((y - top) / maxOffset)
    self:setColorFromVisual()
end

function Window:setHueFromMouse(y)
    local metrics = self.metrics
    local top = metrics.colorBoxY + metrics.colorInset
    local maxOffset = metrics.colorInnerSize - 1
    y = math.max(top, math.min(y, top + maxOffset))
    self.hue = 1 - ((y - top) / maxOffset)
    self:setColorFromVisual()
end

function Window:onMouseDown(x, y)
    local metrics = self.metrics
    if x >= metrics.colorBoxX and x <= metrics.colorBoxX + metrics.colorBoxSize
            and y >= metrics.colorBoxY and y <= metrics.colorBoxY + metrics.colorBoxSize then
        self.draggingColorBox = true
        self:setSaturationValueFromMouse(x, y)
        return true
    end
    if x >= metrics.hueBarX and x <= metrics.hueBarX + metrics.hueBarWidth
            and y >= metrics.colorBoxY and y <= metrics.colorBoxY + metrics.colorBoxSize then
        self.draggingHueBar = true
        self:setHueFromMouse(y)
        return true
    end
    return true
end

function Window:onMouseMove(dx, dy)
    if self.draggingColorBox then
        self:setSaturationValueFromMouse(self:getMouseX(), self:getMouseY())
        return true
    end
    if self.draggingHueBar then
        self:setHueFromMouse(self:getMouseY())
        return true
    end
    return true
end

function Window:onMouseUp(x, y)
    self.draggingColorBox = false
    self.draggingHueBar = false
    return true
end

function Window:onMouseUpOutside(x, y)
    self.draggingColorBox = false
    self.draggingHueBar = false
    return true
end

function Window:onMouseDownOutside(x, y)
    self.draggingColorBox = false
    self.draggingHueBar = false
    return true
end

function Window:onReset()
    self.color = colorCopy(self.openingColor)
    self.hue, self.saturation, self.value = rgbToHsv(self.color)
    self:applyColor(false)
end

function Window:onClose()
    closeActiveWindow()
end

function Window:onDefault()
    self.color = colorCopy(self.defaultColor)
    self:applyColor(true)
end

function Window:onApply()
    if self.saveColor ~= nil and self.saveColor(colorCopy(self.color)) == false then return end
    self:onClose()
end

function Window:rebuildForMetrics(metrics)
    self.draggingColorBox = false
    self.draggingHueBar = false
    self.metrics = metrics
    self:setWidth(metrics.pickerWidth)
    self:setHeight(metrics.pickerHeight)
    local x, y = screenCenter(metrics)
    self:setX(x)
    self:setY(y)
    self.hiResSwatchX = metrics.pickerWidth - metrics.swatchWidth - metrics.outerPadding
    if activeFrame ~= nil then
        activeFrame:setX(0)
        activeFrame:setY(0)
        activeFrame:setWidth(metrics.screenWidth)
        activeFrame:setHeight(metrics.screenHeight)
    end
    self:clearChildren()
    self:createChildren()
end

function Window:update()
    if ISPanel.update ~= nil then
        ISPanel.update(self)
    end
    if self.isOwnerVisible ~= nil then
        if self.isOwnerVisible() ~= true then
            self:onClose()
            return
        end
    else
        if MainOptions == nil or MainOptions.instance == nil then
            self:onClose()
            return
        end
        if MainOptions.instance.isVisible ~= nil and not MainOptions.instance:isVisible() then
            self:onClose()
            return
        end
    end
    local currentMetrics = resolveMetrics()
    if self.metrics == nil or currentMetrics.signature ~= self.metrics.signature then
        self:rebuildForMetrics(currentMetrics)
    end
    self.readyForOutsideClick = true
end

function Window:drawColorSquare()
    local metrics = self.metrics
    self:drawRectBorder(metrics.colorBoxX, metrics.colorBoxY,
            metrics.colorBoxSize, metrics.colorBoxSize, 1, 1, 1, 1)
    local left = metrics.colorBoxX + metrics.colorInset
    local top = metrics.colorBoxY + metrics.colorInset
    local red = self.hiResColorSquareRed
    local green = self.hiResColorSquareGreen
    local blue = self.hiResColorSquareBlue
    local index = 1
    for sx = 0, COLOR_BOX_CELLS - 1 do
        for vy = 0, COLOR_BOX_CELLS - 1 do
            self:drawRect(left + sx * metrics.colorCellSize, top + vy * metrics.colorCellSize,
                    metrics.colorCellSize + 1, metrics.colorCellSize + 1, 1,
                    red[index], green[index], blue[index])
            index = index + 1
        end
    end

    local cursorX = self.hiResColorCursorX
    local cursorY = self.hiResColorCursorY
    self:drawRectBorder(cursorX - math.floor(metrics.cursorOuterSize / 2),
            cursorY - math.floor(metrics.cursorOuterSize / 2),
            metrics.cursorOuterSize, metrics.cursorOuterSize, 1, 1, 1, 1)
    self:drawRectBorder(cursorX - math.floor(metrics.cursorInnerSize / 2),
            cursorY - math.floor(metrics.cursorInnerSize / 2),
            metrics.cursorInnerSize, metrics.cursorInnerSize, 1, 0, 0, 0)
    self:drawRect(cursorX - math.floor(metrics.cursorFillSize / 2),
            cursorY - math.floor(metrics.cursorFillSize / 2),
            metrics.cursorFillSize, metrics.cursorFillSize,
            1, self.color.r, self.color.g, self.color.b)
end

function Window:drawHueBar()
    local metrics = self.metrics
    self:drawRectBorder(metrics.hueBarX, metrics.colorBoxY,
            metrics.hueBarWidth, metrics.colorBoxSize, 1, 1, 1, 1)
    local top = metrics.colorBoxY + metrics.colorInset
    for i = 0, HUE_BAR_STEPS - 1 do
        self:drawRect(metrics.hueBarX + metrics.colorInset, top + i * metrics.hueStepHeight,
                metrics.hueBarWidth - metrics.colorInset * 2,
                metrics.hueStepHeight + 1, 1,
                HUE_BAR_RED[i + 1], HUE_BAR_GREEN[i + 1], HUE_BAR_BLUE[i + 1])
    end

    local markerY = self.hiResHueMarkerY
    self:drawRectBorder(metrics.hueBarX - metrics.hueMarkerOuterPadding,
            markerY - math.floor(metrics.hueMarkerOuterHeight / 2),
            metrics.hueBarWidth + metrics.hueMarkerOuterPadding * 2,
            metrics.hueMarkerOuterHeight, 1, 1, 1, 1)
    self:drawRectBorder(metrics.hueBarX - metrics.hueMarkerInnerPadding,
            markerY - math.floor(metrics.hueMarkerInnerHeight / 2),
            metrics.hueBarWidth + metrics.hueMarkerInnerPadding * 2,
            metrics.hueMarkerInnerHeight, 1, 0, 0, 0)
end

function Window:prerender()
    ISPanel.prerender(self)
    local metrics = self.metrics
    self:drawTextCentre(self.title, self:getWidth() / 2,
            metrics.titleY, 1, 1, 1, 1, UIFont.Small)

    local swatchX = self.hiResSwatchX
    self:drawRectBorder(swatchX, metrics.swatchY,
            metrics.swatchWidth, metrics.swatchHeight, 1, 1, 1, 1)
    self:drawRect(swatchX + metrics.colorInset, metrics.swatchY + metrics.colorInset,
            metrics.swatchWidth - metrics.colorInset * 2,
            metrics.swatchHeight - metrics.colorInset * 2,
            self.color.a, self.color.r, self.color.g, self.color.b)
    self:drawColorSquare()
    self:drawHueBar()
end

function Window:new(config)
    local metrics = config.metrics or resolveMetrics()
    local width = metrics.pickerWidth
    local height = metrics.pickerHeight
    local x = config.x or 0
    local y = config.y or 0
    local o = ISPanel.new(self, x, y, width, height)
    setmetatable(o, self)
    self.__index = self

    o.background = true
    o.backgroundColor = { r = 0, g = 0, b = 0, a = 0.88 }
    o.borderColor = { r = 0.6, g = 0.6, b = 0.6, a = 1 }
    o.moveWithMouse = false
    o.title = optionTitle(config)
    o.defaultColor = colorCopy(config.defaultColor)
    o.getColor = config.getColor
    o.setColor = config.setColor
    o.saveColor = config.saveColor
    o.isOwnerVisible = config.isOwnerVisible
    o.metrics = metrics
    o.color = colorCopy(config.getColor ~= nil and config.getColor() or config.defaultColor)
    o.openingColor = colorCopy(o.color)
    o.hue, o.saturation, o.value = rgbToHsv(o.color)
    o.hiResSwatchX = width - metrics.swatchWidth - metrics.outerPadding
    o.readyForOutsideClick = false
    return o
end

function ColorPicker.open(config)
    if ISSliderPanel == nil then
        print("WoodCutter: ISSliderPanel is unavailable")
        return
    end

    closeActiveWindow()

    local metrics = resolveMetrics()
    local screenWidth, screenHeight = screenSize()
    local x, y = screenCenter(metrics)
    activeFrame = Frame:new(0, 0, screenWidth, screenHeight)
    activeFrame:initialise()
    activeFrame:instantiate()
    if activeFrame.setAlwaysOnTop ~= nil then
        activeFrame:setAlwaysOnTop(true)
    end
    activeFrame:addToUIManager()
    activeFrame:setVisible(true)
    if activeFrame.setCapture ~= nil then
        activeFrame:setCapture(true)
    end

    config = config or {}
    config.x = x
    config.y = y
    config.metrics = metrics
    activeWindow = Window:new(config)
    activeWindow:initialise()
    activeWindow:instantiate()
    activeWindow:createChildren()
    if activeWindow.setAlwaysOnTop ~= nil then
        activeWindow:setAlwaysOnTop(true)
    end
    activeFrame:addChild(activeWindow)
    activeWindow:setVisible(true)
    activeWindow:bringToTop()
    activeFrame:bringToTop()
end

function ColorPicker.install(modId)
    if installed or MainOptions == nil or MainOptions.onModColorPick == nil then
        return
    end

    originalModColorPick = MainOptions.onModColorPick
    MainOptions.onModColorPick = function(mainOptions, button)
        local optionKey = getButtonOptionKey(button, modId)
        local data = optionKey ~= nil and OPTION_DATA[optionKey] or nil
        if data == nil then
            return originalModColorPick(mainOptions, button)
        end

        ColorPicker.open({
            titleKey = data.titleKey,
            defaultColor = data.defaultColor,
            getColor = function()
                if button.backgroundColor ~= nil then
                    return colorCopy(button.backgroundColor)
                end
                return colorCopy(data.defaultColor)
            end,
            setColor = function(color)
                button.backgroundColor = color
                updateGameOption(button, color)
            end,
            saveColor = function(color)
                local options = PZAPI.ModOptions:getOptions(modId)
                local option = options ~= nil and options:getOption(optionKey) or nil
                if option == nil then return false end
                if option.onChangeApply ~= nil then option:onChangeApply(color)
                else option:setValue(color) end
                button.backgroundColor = option:getValue()
                return saveColor(modId, optionKey, option:getValue())
            end,
        })
    end

    installed = true
end

return ColorPicker
