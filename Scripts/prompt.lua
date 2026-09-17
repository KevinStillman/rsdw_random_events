-- Persistent on-screen prompt ("Press F for Random Event"), shown/hidden
-- by encounter.lua's proximity poll while the player is near a spawned
-- event NPC. Separate from notify.lua's auto-hiding toast - built the
-- same way (raw UMG via StaticConstructObject), but this one just toggles
-- visibility on command instead of showing for a fixed duration.
local UEHelpers = require("UEHelpers")
local Config = require("config")

local Prompt = {}

local Visibility_HIDDEN = 2
local Visibility_SELF_HIT_TEST_INVISIBLE = 4
local HAlign_Center = 2

local panelCanvas = nil
local panelBorder = nil
local bodyText = nil
local currentlyVisible = false

local function log(msg)
    print("[RSDWRandomEvents] " .. msg .. "\n")
end

local function isValid(o)
    return o and o.IsValid and o:IsValid()
end

local function ensurePanel()
    if isValid(panelBorder) then return true end

    local ok_gi, game_instance = pcall(UEHelpers.GetGameInstance)
    if not ok_gi or not isValid(game_instance) then
        log("prompt.ensurePanel: GetGameInstance failed")
        return false
    end

    local user_widget_cls  = StaticFindObject("/Script/UMG.UserWidget")
    local widget_tree_cls  = StaticFindObject("/Script/UMG.WidgetTree")
    local canvas_panel_cls = StaticFindObject("/Script/UMG.CanvasPanel")
    local border_cls       = StaticFindObject("/Script/UMG.Border")
    local text_block_cls   = StaticFindObject("/Script/UMG.TextBlock")
    local size_box_cls     = StaticFindObject("/Script/UMG.SizeBox")
    if not (user_widget_cls and widget_tree_cls and canvas_panel_cls and border_cls
            and text_block_cls and size_box_cls) then
        log("prompt.ensurePanel: required UMG classes not found")
        return false
    end

    local hud = StaticConstructObject(user_widget_cls, game_instance, FName("RSDWRandomEventsPrompt"))
    hud.WidgetTree = StaticConstructObject(widget_tree_cls, hud, FName("RSDWRandomEventsPromptTree"))

    local canvas = StaticConstructObject(canvas_panel_cls, hud.WidgetTree, FName("RSDWRandomEventsPromptCanvas"))
    hud.WidgetTree.RootWidget = canvas

    local sizeBox = StaticConstructObject(size_box_cls, canvas, FName("RSDWRandomEventsPromptSize"))
    sizeBox:SetWidthOverride(Config.PromptWidth)

    local border = StaticConstructObject(border_cls, sizeBox, FName("RSDWRandomEventsPromptBorder"))
    border:SetBrushColor(Config.PromptBackgroundColor)
    border:SetPadding({
        Left = Config.PromptPadding,
        Top = Config.PromptPadding,
        Right = Config.PromptPadding,
        Bottom = Config.PromptPadding,
    })
    sizeBox:SetContent(border)

    local body = StaticConstructObject(text_block_cls, border, FName("RSDWRandomEventsPromptText"))
    body.Font.Size = Config.PromptFontSize
    body:SetColorAndOpacity({ SpecifiedColor = Config.PromptTextColor, ColorUseRule = 0 })
    -- AutoWrapText must be off for WrapTextAt to actually be used - when
    -- it's on, Slate always uses its own (unreliable at construction
    -- time) auto-computed width instead, ignoring WrapTextAt entirely
    -- regardless of its value. See notify.lua for the fuller explanation.
    body:SetAutoWrapText(false)
    body.WrapTextAt = Config.PromptWidth - (2 * Config.PromptPadding)
    body:SetJustification(HAlign_Center)
    border:SetContent(body)

    local slot = canvas:AddChildToCanvas(sizeBox)
    slot:SetAutoSize(true)
    slot:SetAnchors({ Minimum = { X = Config.PromptX, Y = Config.PromptY }, Maximum = { X = Config.PromptX, Y = Config.PromptY } })
    slot:SetAlignment({ X = 0.5, Y = 0.5 })

    canvas.Visibility = Visibility_HIDDEN

    hud:AddToViewport(55)

    panelCanvas = canvas
    panelBorder = border
    bodyText = body
    return true
end

-- Shows or hides the prompt with `text` (only used the first time it's
-- shown after construction/text changes - cheap to call every poll tick
-- regardless, it no-ops if nothing changed).
function Prompt.SetVisible(visible, text)
    ExecuteInGameThread(function()
        if not ensurePanel() then return end
        if visible and text and isValid(bodyText) then
            pcall(function() bodyText:SetText(FText(text)) end)
        end
        if visible == currentlyVisible then return end
        currentlyVisible = visible
        local vis = visible and Visibility_SELF_HIT_TEST_INVISIBLE or Visibility_HIDDEN
        pcall(function() panelCanvas:SetVisibility(vis) end)
    end)
end

return Prompt
