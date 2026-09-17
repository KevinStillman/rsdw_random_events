-- Toast notification panel: a small UMG border+text popup for event flavor
-- text, built the same way DragonwildsHUD builds its skill panel (raw UMG
-- classes via StaticConstructObject, since Dragonwilds exposes no simpler
-- "show a message" UFUNCTION we've found). One toast at a time; showing a
-- new one while another is visible just replaces the text and resets the
-- hide timer.
local UEHelpers = require("UEHelpers")
local Config = require("config")

local Notify = {}

local Visibility_HIDDEN = 2
local Visibility_SELF_HIT_TEST_INVISIBLE = 4
local HAlign_Center = 2

local panelCanvas = nil
local panelBorder = nil
local titleText = nil
local bodyText = nil
local panelSlot = nil
local hideGeneration = 0 -- bumped on every show; a pending hide only fires if it's still current

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
        log("notify.ensurePanel: GetGameInstance failed")
        return false
    end

    local user_widget_cls  = StaticFindObject("/Script/UMG.UserWidget")
    local widget_tree_cls  = StaticFindObject("/Script/UMG.WidgetTree")
    local canvas_panel_cls = StaticFindObject("/Script/UMG.CanvasPanel")
    local border_cls       = StaticFindObject("/Script/UMG.Border")
    local text_block_cls   = StaticFindObject("/Script/UMG.TextBlock")
    local vertical_box_cls = StaticFindObject("/Script/UMG.VerticalBox")
    local size_box_cls     = StaticFindObject("/Script/UMG.SizeBox")
    if not (user_widget_cls and widget_tree_cls and canvas_panel_cls and border_cls
            and text_block_cls and vertical_box_cls and size_box_cls) then
        log("notify.ensurePanel: required UMG classes not found")
        return false
    end

    local hud = StaticConstructObject(user_widget_cls, game_instance, FName("RSDWRandomEventsToast"))
    hud.WidgetTree = StaticConstructObject(widget_tree_cls, hud, FName("RSDWRandomEventsToastTree"))

    local canvas = StaticConstructObject(canvas_panel_cls, hud.WidgetTree, FName("RSDWRandomEventsToastCanvas"))
    hud.WidgetTree.RootWidget = canvas

    local sizeBox = StaticConstructObject(size_box_cls, canvas, FName("RSDWRandomEventsToastSize"))
    sizeBox:SetWidthOverride(Config.ToastWidth)

    local border = StaticConstructObject(border_cls, sizeBox, FName("RSDWRandomEventsToastBorder"))
    border:SetBrushColor(Config.ToastBackgroundColor)
    border:SetPadding({
        Left = Config.ToastPadding,
        Top = Config.ToastPadding,
        Right = Config.ToastPadding,
        Bottom = Config.ToastPadding,
    })
    sizeBox:SetContent(border)

    local vbox = StaticConstructObject(vertical_box_cls, border, FName("RSDWRandomEventsToastVBox"))
    border:SetContent(vbox)

    local title = StaticConstructObject(text_block_cls, vbox, FName("RSDWRandomEventsToastTitle"))
    title.Font.Size = Config.ToastTitleFontSize
    title:SetColorAndOpacity({ SpecifiedColor = Config.ToastTitleColor, ColorUseRule = 0 })
    title:SetJustification(HAlign_Center)
    local titleSlot = vbox:AddChildToVerticalBox(title)
    titleSlot:SetHorizontalAlignment(HAlign_Center)

    local body = StaticConstructObject(text_block_cls, vbox, FName("RSDWRandomEventsToastBody"))
    body.Font.Size = Config.ToastBodyFontSize
    body:SetColorAndOpacity({ SpecifiedColor = Config.ToastBodyColor, ColorUseRule = 0 })
    -- AutoWrapText measures the container's on-screen width, which isn't
    -- settled yet the first time this panel is built (constructed and
    -- shown in the same frame) - it read as ~0, wrapping after almost
    -- every word instead of filling lines. Explicitly setting WrapTextAt
    -- alone didn't fix it: when AutoWrapText is true, Slate's internal
    -- GetWrapTextAt() always uses the (broken) auto-computed width and
    -- never even looks at WrapTextAt, regardless of its value - confirmed
    -- by screenshot, still one word per line after that "fix". Turning
    -- AutoWrapText off is what actually makes WrapTextAt take effect.
    -- WrapTextAt is a plain property here, not a callable setter -
    -- SetWrapTextAt(...) errored with "attempt to call a TrivialObject
    -- value", which broke toast construction entirely for a while
    -- (every Notify.Show call after the first kept retrying and failing).
    body:SetAutoWrapText(false)
    body.WrapTextAt = Config.ToastWidth - (2 * Config.ToastPadding)
    body:SetJustification(HAlign_Center)
    local bodySlot = vbox:AddChildToVerticalBox(body)
    bodySlot:SetHorizontalAlignment(HAlign_Center)
    bodySlot:SetPadding({ Left = 0, Top = 4, Right = 0, Bottom = 0 })

    local slot = canvas:AddChildToCanvas(sizeBox)
    slot:SetAutoSize(true)
    slot:SetAnchors({ Minimum = { X = Config.ToastX, Y = Config.ToastY }, Maximum = { X = Config.ToastX, Y = Config.ToastY } })
    slot:SetAlignment({ X = 0.5, Y = 0.0 })

    canvas.Visibility = Visibility_HIDDEN

    hud:AddToViewport(60)

    panelCanvas = canvas
    panelBorder = border
    titleText = title
    bodyText = body
    panelSlot = slot
    return true
end

local function setText(widget, text, label)
    if not isValid(widget) then return end
    local ok, err = pcall(function() widget:SetText(FText(text)) end)
    if not ok then log("notify.setText: failed for " .. label .. ": " .. tostring(err)) end
end

-- Shows a toast with `title` and `body` for `durationMs` (defaults to
-- Config.ToastDurationMs). Safe to call from any hooked/async context;
-- actual widget work is deferred to the game thread.
function Notify.Show(title, body, durationMs)
    durationMs = durationMs or Config.ToastDurationMs
    ExecuteInGameThread(function()
        if not ensurePanel() then return end
        setText(titleText, title or "", "title")
        setText(bodyText, body or "", "body")
        pcall(function() panelCanvas:SetVisibility(Visibility_SELF_HIT_TEST_INVISIBLE) end)

        hideGeneration = hideGeneration + 1
        local myGeneration = hideGeneration
        if not LoopAsync then return end
        LoopAsync(durationMs, function()
            if myGeneration ~= hideGeneration then return true end -- superseded by a newer toast
            if isValid(panelCanvas) then
                pcall(function() panelCanvas:SetVisibility(Visibility_HIDDEN) end)
            end
            return true
        end)
    end)
end

return Notify
