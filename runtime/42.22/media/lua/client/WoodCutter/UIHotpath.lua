local Hotpath = {}

local TOGGLE_ON = { r = 0, g = 200 / 255, b = 0, a = 1 }
local TOGGLE_OFF = { r = 115 / 255, g = 115 / 255, b = 115 / 255, a = 1 }
local BLACK = { r = 0, g = 0, b = 0, a = 1 }
Hotpath.WHITE = { r = 1, g = 1, b = 1, a = 1 }
local function refreshLabelMetrics(label)
    local text = label.translation or label.name
    local manager = getTextManager()
    label.hiResTextHeight = math.max(manager:MeasureFont(label.font),
            manager:MeasureStringY(label.font, text))
end

local function cachedLabelPrerender(label)
    local text = label.translation or label.name
    if label.textColor then
        label.r = label.textColor.r
        label.g = label.textColor.g
        label.b = label.textColor.b
        label.a = label.textColor.a
    end

    local y = (label.height - label.hiResTextHeight) / 2
    if label.center then
        label:drawTextCentre(text, 0, y, label.r, label.g, label.b, label.a, label.font)
    else
        label:drawText(text, 0, y, label.r, label.g, label.b, label.a, label.font)
    end
    if label.joypadFocused and label.joypadTexture then
        local textureY = label.height / 2 - 16
        label:drawTextureScaled(label.joypadTexture, -42, textureY, 32, 32, 1, 1, 1, 1)
    end
    if label.tooltip ~= nil or label.tooltipUI ~= nil then label:updateTooltip() end
end

function Hotpath.installLabel(label)
    if label.hiResCachedLabel then return label end
    label.hiResCachedLabel = true
    local baseSetName = label.setName
    label.setName = function(control, name)
        if control.name == name then return end
        baseSetName(control, name)
        refreshLabelMetrics(control)
    end
    local baseSetFont = label.setFont
    if baseSetFont ~= nil then
        label.setFont = function(control, font)
            if control.font == font then return end
            baseSetFont(control, font)
            refreshLabelMetrics(control)
        end
    end
    refreshLabelMetrics(label)
    label.prerender = cachedLabelPrerender
    return label
end

local function refreshButtonMetrics(button)
    local title = button.title or ""
    if title == "" then
        button.hiResTextWidth = 0
        button.hiResTextHeight = 0
        return
    end
    local manager = getTextManager()
    button.hiResTextWidth = manager:MeasureStringX(button.font, title)
    button.hiResTextHeight = manager:MeasureStringY(button.font, title)
end

local function cachedTextButtonRender(button)
    if button.image ~= nil then
        local alpha = button.textureColor.a
        if button.blinkImage then
            if button.blinkImageAlpha == nil then
                button.blinkImageAlpha = 1
                button.blinkImageAlphaIncrease = false
            end
            local delta = 0.1 * (UIManager.getMillisSinceLastRender() / 33.3)
            if button.blinkImageAlphaIncrease then
                button.blinkImageAlpha = math.min(1, button.blinkImageAlpha + delta)
                if button.blinkImageAlpha == 1 then button.blinkImageAlphaIncrease = false end
            else
                button.blinkImageAlpha = math.max(0, button.blinkImageAlpha - delta)
                if button.blinkImageAlpha == 0 then button.blinkImageAlphaIncrease = true end
            end
            alpha = button.blinkImageAlpha
        end
        if button.forcedWidthImage and button.forcedHeightImage then
            button:drawTextureScaledAspect(button.image,
                    button.width / 2 - button.forcedWidthImage / 2,
                    button.height / 2 - button.forcedHeightImage / 2,
                    button.forcedWidthImage, button.forcedHeightImage, alpha,
                    button.textureColor.r, button.textureColor.g, button.textureColor.b)
        elseif button.hiResImageWidth <= button.width and button.hiResImageHeight <= button.height then
            button:drawTexture(button.image, button.width / 2 - button.hiResImageWidth / 2,
                    button.height / 2 - button.hiResImageHeight / 2, alpha,
                    button.textureColor.r, button.textureColor.g, button.textureColor.b)
        else
            button:drawTextureScaledAspect(button.image, 0, 0, button.width, button.height, alpha,
                    button.textureColor.r, button.textureColor.g, button.textureColor.b)
        end
    end

    local textWidth = button.hiResTextWidth
    local x = button.width / 2 - textWidth / 2
    if (button.isJoypad and button.joypadTexture) or button.iconTexture then
        local textureWidth = button.joypadTextureWH
        local textureX = math.max(5, x - 5 - textureWidth)
        x = textureX + textureWidth + 5
        button:drawTextureScaled(button.joypadTexture or button.iconTexture, textureX,
                button.height / 2 - textureWidth / 2, textureWidth, textureWidth, 1, 1, 1, 1)
    end
    if button.titleLeft then x = button.hiResTitleLeftPadding or 3 end
    if textWidth > 0 then
        local y = button.height / 2 - button.hiResTextHeight / 2 + button.yoffset
        if button.enable then
            button:drawText(button.title, x, y, button.textColor.r, button.textColor.g,
                    button.textColor.b, button.textColor.a, button.font)
        elseif button.displayBackground and not button.isJoypad and button.joypadFocused then
            button:drawText(button.title, x, y, 0, 0, 0, 1, button.font)
        else
            button:drawText(button.title, x, y, 0.3, 0.3, 0.3, 1, button.font)
        end
    end
    if button.overlayText then
        button:drawTextRight(button.overlayText, button.width, button.height - 10,
                1, 1, 1, 0.5, UIFont.Small)
    end
    if button.mouseOver and button.onmouseover then
        button.onmouseover(button.target, button, button:getMouseX(), button:getMouseY())
    end
    if button.textureOverride then
        if button.hiResTextureOverride ~= button.textureOverride then
            button.hiResTextureOverride = button.textureOverride
            button.hiResTextureOverrideWidth = button.textureOverride:getWidth()
            button.hiResTextureOverrideHeight = button.textureOverride:getHeight()
        end
        button:drawTexture(button.textureOverride,
                button.width / 2 - button.hiResTextureOverrideWidth / 2,
                button.height / 2 - button.hiResTextureOverrideHeight / 2, 1, 1, 1, 1)
    end
end

function Hotpath.installTextButton(button)
    if button.hiResCachedTextButton then return button end
    button.hiResCachedTextButton = true
    local baseSetTitle = button.setTitle
    button.setTitle = function(control, title)
        if control.title == title then return end
        baseSetTitle(control, title)
        refreshButtonMetrics(control)
    end
    local baseSetFont = button.setFont
    if baseSetFont ~= nil then
        button.setFont = function(control, font)
            if control.font == font then return end
            baseSetFont(control, font)
            refreshButtonMetrics(control)
        end
    end
    local baseSetImage = button.setImage
    button.setImage = function(control, image)
        baseSetImage(control, image)
        control.hiResImageWidth = image ~= nil and image:getWidthOrig() or 0
        control.hiResImageHeight = image ~= nil and image:getHeightOrig() or 0
    end
    button.hiResImageWidth = button.image ~= nil and button.image:getWidthOrig() or 0
    button.hiResImageHeight = button.image ~= nil and button.image:getHeightOrig() or 0
    refreshButtonMetrics(button)
    button.render = cachedTextButtonRender
    local baseUpdateTooltip = button.updateTooltip
    button.updateTooltip = function(control)
        if control.tooltip ~= nil or control.tooltipUI ~= nil then
            return baseUpdateTooltip(control)
        end
    end
    return button
end

local function togglePrerender(control)
    local color = control.backgroundColor
    local width = control.width
    local height = control.height
    local borderWidth = control.hiResToggleBorderWidth
    control:drawRect(0, 0, width, height, color.a, color.r, color.g, color.b)
    control:drawRect(0, 0, width, borderWidth, 1, 0, 0, 0)
    control:drawRect(0, height - borderWidth, width, borderWidth, 1, 0, 0, 0)
    control:drawRect(0, borderWidth, borderWidth, height - borderWidth * 2, 1, 0, 0, 0)
    control:drawRect(width - borderWidth, borderWidth, borderWidth,
            height - borderWidth * 2, 1, 0, 0, 0)
    if control.tooltip ~= nil or control.tooltipUI ~= nil then control:updateTooltip() end
end

function Hotpath.styleToggle(button, enabled)
    local color = enabled and TOGGLE_ON or TOGGLE_OFF
    button.backgroundColor = color
    button.backgroundColorMouseOver = color
    button.backgroundColorPressed = color
    button.borderColor = BLACK
    button.hiResToggleBorderWidth = math.min(4, math.floor(math.min(button.width, button.height) / 2))
    button.prerender = togglePrerender
end

local function updateSliderThumb(slider)
    local range = slider.maxValue - slider.minValue
    local fraction = range == 0 and 0 or (slider.currentValue - slider.minValue) / range
    slider.hiResThumbX = slider.sliderBarDim.x + slider.sliderBarDim.w * fraction
end

local function sliderValueMetrics(slider, font)
    local metrics = slider.hiResValueMetrics
    if metrics == nil then
        metrics = {}
        slider.hiResValueMetrics = metrics
    end
    local fontChanged = metrics.font ~= font
    if fontChanged then
        metrics.font = font
        metrics.fontHeight = getTextManager():getFontHeight(font)
    end
    if fontChanged or metrics.width ~= slider.width or metrics.height ~= slider.height then
        metrics.width, metrics.height = slider.width, slider.height
        metrics.x = slider.width / 2
        metrics.y = (slider.height - metrics.fontHeight) / 2
    end
    return metrics
end

local function cachedSliderRender(slider)
    local color = slider.buttonColor
    if slider.doButtons then
        if slider.leftPressed then color = slider.buttonMouseOverColor end
        slider:drawTextureScaled(slider.texBtnLeft, slider.btnLeftDim.x, slider.btnLeftDim.y,
                slider.btnLeftDim.w, slider.btnLeftDim.h, color.a, color.r, color.g, color.b)
        color = slider.rightPressed and slider.buttonMouseOverColor or slider.buttonColor
        slider:drawTextureScaled(slider.texBtnRight, slider.btnRightDim.x, slider.btnRightDim.y,
                slider.btnRightDim.w, slider.btnRightDim.h, color.a, color.r, color.g, color.b)
    end

    local bar = slider.sliderBarDim
    color = slider.sliderBarColor
    slider:drawRect(bar.x, bar.y, bar.w, bar.h, color.a, color.r, color.g, color.b)
    color = slider.sliderBarBorderColor
    slider:drawRectBorder(bar.x, bar.y - 1, bar.w, bar.h + 2, color.a, color.r, color.g, color.b)

    local thumb = slider.sliderDim
    color = slider.dragInside and slider.sliderMouseOverColor or slider.sliderColor
    slider:drawRect(slider.hiResThumbX - thumb.x, thumb.y, thumb.w, thumb.h,
            color.a, color.r, color.g, color.b)
    color = slider.sliderBorderColor
    slider:drawRectBorder(slider.hiResThumbX - thumb.x - 1, thumb.y, thumb.w + 2, thumb.h,
            color.a, color.r, color.g, color.b)

    local valueLabel = slider.hiResValueLabel
    if valueLabel ~= nil then
        local value = valueLabel.getName ~= nil and valueLabel:getName() or valueLabel.name
        if value ~= nil and value ~= "" then
            local font = valueLabel.font or UIFont.Small
            local metrics = sliderValueMetrics(slider, font)
            slider:drawTextCentre(value, metrics.x, metrics.y,
                    valueLabel.r or 1, valueLabel.g or 1,
                    valueLabel.b or 1, valueLabel.a or 1, font)
        end
    end
end

function Hotpath.installSlider(slider)
    if slider.hiResCachedSlider then return slider end
    slider.hiResCachedSlider = true
    local baseSetCurrentValue = slider.setCurrentValue
    slider.setCurrentValue = function(control, value, ignoreOnChange)
        baseSetCurrentValue(control, value, ignoreOnChange)
        updateSliderThumb(control)
    end
    local basePaginate = slider.paginate
    slider.paginate = function(control)
        basePaginate(control)
        updateSliderThumb(control)
    end
    updateSliderThumb(slider)
    slider.render = cachedSliderRender
    return slider
end

function Hotpath.installTransparentDrawCull(control)
    if control.hiResTransparentDrawCull then return control end
    control.hiResTransparentDrawCull = true
    local baseDrawRect = control.drawRect
    control.drawRect = function(element, x, y, width, height, alpha, red, green, blue)
        if alpha <= 0 then return end
        return baseDrawRect(element, x, y, width, height, alpha, red, green, blue)
    end
    return control
end

local function cachedComboPrerender(combo)
    if not combo.disabled then
        combo.fade:setFadeIn(combo.joypadFocused or combo:isMouseOver())
        combo.fade:update()
    end

    local background = combo.backgroundColor
    combo:drawRect(0, 0, combo.width, combo.height, background.a,
            background.r, background.g, background.b)
    local fade = combo.fade:fraction()
    if not combo.expanded and (combo.joypadFocused or fade > 0) then
        local hover = combo.backgroundColorMouseOver
        local alpha = combo.joypadFocused and hover.a or hover.a * 0.5 * fade
        combo:drawRect(0, 0, combo.width, combo.height, alpha, hover.r, hover.g, hover.b)
    end

    local border = combo.borderColor
    local alpha = math.min(border.a + 0.2 * fade, 1)
    if combo.disabled then
        combo:drawRectBorder(0, 0, combo.width, combo.height, alpha, 0.5, 0.5, 0.5)
    else
        combo:drawRectBorder(0, 0, combo.width, combo.height,
                alpha, border.r, border.g, border.b)
    end

    local selectedText = combo.options[combo.selected]
    local text = selectedText ~= nil and combo:getOptionText(combo.selected)
            or combo.noSelectionText
    if text ~= nil then
        local textPadding = combo.hiResTextPadding or 10
        local arrowReserve = combo.hiResArrowReserve or 6
        local stencilX, stencilY, stencilWidth, stencilHeight = combo:clampStencilRectToParent(
                0, 0, combo.width - combo.hiResArrowWidth - arrowReserve, combo.height)
        if combo.disabled then
            combo:drawText(text, textPadding, combo.hiResTextY,
                    0.6, 0.6, 0.6, 1, combo.font)
        else
            local color = combo.textColor
            combo:drawText(text, textPadding, combo.hiResTextY,
                    color.r, color.g, color.b, color.a, combo.font)
        end
        combo:clearStencilRect()
        if combo.doRepaintStencil then
            combo:repaintStencilRect(stencilX, stencilY, stencilWidth, stencilHeight)
        end
    end

    local optionTooltip
    if combo:isMouseOver() and not combo.expanded and combo.getOptionTooltip ~= nil then
        optionTooltip = combo:getOptionTooltip(combo.selected)
    end
    if optionTooltip ~= nil then
        if combo.tooltipUI == nil then
            combo.tooltipUI = ISToolTip:new()
            combo.tooltipUI:setOwner(combo)
            combo.tooltipUI:setVisible(false)
            combo.tooltipUI:setAlwaysOnTop(true)
        end
        if not combo.tooltipUI:getIsVisible() then
            combo.tooltipUI.maxLineWidth = string.contains(optionTooltip, "\n") and 1000 or 300
            combo.tooltipUI:addToUIManager()
            combo.tooltipUI:setVisible(true)
        end
        combo.tooltipUI.description = optionTooltip
        combo.tooltipUI:setX(combo:getMouseX() + 23)
        combo.tooltipUI:setY(combo:getMouseY() + 23)
    elseif combo.tooltipUI and combo.tooltipUI:getIsVisible() then
        combo.tooltipUI:setVisible(false)
        combo.tooltipUI:removeFromUIManager()
    end
    local arrowRightPadding = combo.hiResArrowRightPadding or 3
    if combo.disabled then
        combo:drawTexture(combo.image, combo.width - combo.hiResArrowWidth - arrowRightPadding,
                combo.baseHeight / 2 - combo.hiResArrowHeight / 2, 1, 0.5, 0.5, 0.5)
    else
        combo:drawTexture(combo.image, combo.width - combo.hiResArrowWidth - arrowRightPadding,
                combo.baseHeight / 2 - combo.hiResArrowHeight / 2, 1, 1, 1, 1)
    end
end

function Hotpath.installCombo(combo)
    if combo.hiResCachedCombo then return combo end
    combo.hiResCachedCombo = true
    combo.hiResArrowWidth = combo.image:getWidthOrig()
    combo.hiResArrowHeight = combo.image:getHeight()
    combo.hiResTextY = (combo.height - getTextManager():getFontHeight(combo.font)) / 2
    local function refreshTextY(control)
        control.hiResTextY = (control.height - getTextManager():getFontHeight(control.font)) / 2
    end
    local baseSetHeight = combo.setHeight
    combo.setHeight = function(control, height)
        baseSetHeight(control, height)
        refreshTextY(control)
    end
    local baseSetFont = combo.setFont
    if baseSetFont ~= nil then
        combo.setFont = function(control, font)
            baseSetFont(control, font)
            refreshTextY(control)
        end
    end
    combo.prerender = cachedComboPrerender
    return combo
end

function Hotpath.bodyPrerender(panel)
    local color = panel.backgroundColor
    panel:drawRectStatic(0, 0, panel.width, panel.height, color.a, color.r, color.g, color.b)
end

Hotpath.METRICS = {
    header = { before = 5, after = 5 },
    section = { before = 5, after = 5 },
    body = { before = 5, after = 1 },
    label = { primitives = 1, textMeasurementsBefore = 2, textMeasurementsAfter = 0 },
    textButton = { primitives = 6, textMeasurementsBefore = 2, textMeasurementsAfter = 0 },
    toggle = { before = 18, after = 6, textMeasurementsBefore = 2, textMeasurementsAfter = 0 },
    comboIdle = { before = 8, after = 7, javaMetricCallsBefore = 4, javaMetricCallsAfter = 0 },
    slider = { primitives = 12, positionCalculationsBefore = 1, positionCalculationsAfter = 0 },
}

Hotpath.STATE_CHANGE_METRICS = {
    toggleStyleTables = { before = 4, after = 0 },
    colorRefreshTemporaryTables = { before = 1, after = 0 },
    skinCatalogResolutionsPerOpen = { before = 5, after = 1 },
    screenSizeResolutionsPerOpen = { before = 5, after = 1 },
}

function Hotpath.measureVisibleFrame(visible)
    local before = 0
    local after = 0
    local repeatedBefore = 0
    local repeatedAfter = 0
    local function add(name, count)
        local metric = Hotpath.METRICS[name]
        count = count or 0
        before = before + count * (metric.before or metric.primitives)
        after = after + count * (metric.after or metric.primitives)
        repeatedBefore = repeatedBefore + count * ((metric.textMeasurementsBefore or 0)
                + (metric.positionCalculationsBefore or 0)
                + (metric.javaMetricCallsBefore or 0))
        repeatedAfter = repeatedAfter + count * ((metric.textMeasurementsAfter or 0)
                + (metric.positionCalculationsAfter or 0)
                + (metric.javaMetricCallsAfter or 0))
    end
    add("header", visible.header)
    add("section", visible.section)
    add("body", visible.body)
    add("label", visible.label)
    add("textButton", visible.textButton)
    add("toggle", visible.toggle)
    add("comboIdle", visible.comboIdle)
    add("slider", visible.slider)
    return {
        primitivesBefore = before,
        primitivesAfter = after,
        repeatedCalculationsBefore = repeatedBefore,
        repeatedCalculationsAfter = repeatedAfter,
    }
end

return Hotpath
