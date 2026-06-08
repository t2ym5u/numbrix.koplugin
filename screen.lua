local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local ButtonTable     = require("ui/widget/buttontable")
local Device          = require("device")
local FrameContainer  = require("ui/widget/container/framecontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local Size            = require("ui/size")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local _               = require("gettext")
local T               = require("ffi/util").template

local ScreenBase         = require("screen_base")
local MenuHelper         = require("menu_helper")
local NumbrixBoard       = lrequire("board")
local NumbrixBoardWidget = lrequire("board_widget")

local DeviceScreen = Device.screen

local GRID_SIZES = { 5, 6 }

local NumbrixScreen = ScreenBase:extend{}

function NumbrixScreen:init()
    local state = self.plugin:loadState()
    local n     = self.plugin:getSetting("grid_n", 5)
    self.board  = NumbrixBoard:new{ n = n }
    if not self.board:load(state) then
        self.board:generate(self.plugin:getSetting("difficulty", "easy"))
    end
    self.selected      = nil
    self.pending_digit = nil
    ScreenBase.init(self)
end

function NumbrixScreen:serializeState()
    return self.board:serialize()
end

function NumbrixScreen:buildLayout()
    local sw           = DeviceScreen:getWidth()
    local is_landscape = self:isLandscape()

    self.board_widget = NumbrixBoardWidget:new{
        board          = self.board,
        onCellSelected = function(r, c) self:onCellSelected(r, c) end,
    }
    if self.selected then
        self.board_widget:setSelected(self.selected.r, self.selected.c)
    end

    local board_frame = FrameContainer:new{
        padding = Size.padding.large,
        margin  = Size.margin.default,
        self.board_widget,
    }

    local board_frame_size  = self.board_widget.size + (Size.padding.large + Size.margin.default) * 2
    local right_panel_width = sw - board_frame_size - Size.span.horizontal_default
    local button_width = is_landscape
        and math.max(right_panel_width - Size.span.horizontal_default, 100)
        or  math.floor(sw * 0.9)

    local top_buttons = ButtonTable:new{
        shrink_unneeded_width = true,
        width   = button_width,
        buttons = {{
            { text = _("New"),      callback = function() self:onNewGame() end },
            { id = "size_button",   text = self:getSizeButtonText(),
              callback = function() self:openSizeMenu() end },
            { id = "diff_button",   text = self:getDiffButtonText(),
              callback = function() self:openDifficultyMenu() end },
            self:makeCloseButtonConfig(),
        }},
    }
    self.size_button = top_buttons:getButtonById("size_button")
    self.diff_button = top_buttons:getButtonById("diff_button")

    local n     = self.board.n
    local total = n * n

    local digit_row1 = {}
    for d = 1, 5 do
        local dv = d
        digit_row1[#digit_row1 + 1] = {
            text = tostring(dv),
            callback = function() self:onDigitKey(dv) end,
        }
    end
    local digit_row2 = {}
    for d = 6, 9 do
        local dv = d
        digit_row2[#digit_row2 + 1] = {
            text = tostring(dv),
            callback = function() self:onDigitKey(dv) end,
        }
    end
    digit_row2[#digit_row2 + 1] = {
        text = "0",
        callback = function() self:onDigitKey(0) end,
    }
    local digit_buttons = ButtonTable:new{
        shrink_unneeded_width = true,
        width   = button_width,
        buttons = { digit_row1, digit_row2 },
    }

    local bottom_buttons = ButtonTable:new{
        shrink_unneeded_width = true,
        width   = button_width,
        buttons = {{
            { text = _("Erase"), callback = function() self:onErase() end },
            { text = _("Check"), callback = function() self:onCheck() end },
        }},
    }

    if is_landscape then
        local right_panel = VerticalGroup:new{
            align = "center",
            top_buttons,
            VerticalSpan:new{ width = Size.span.vertical_large },
            self.status_text,
            VerticalSpan:new{ width = Size.span.vertical_large },
            digit_buttons,
            VerticalSpan:new{ width = Size.span.vertical_large },
            bottom_buttons,
        }
        self.layout = HorizontalGroup:new{
            align  = "center",
            board_frame,
            HorizontalSpan:new{ width = Size.span.horizontal_default },
            right_panel,
        }
    else
        self.layout = VerticalGroup:new{
            align = "center",
            VerticalSpan:new{ width = Size.span.vertical_large },
            top_buttons,
            VerticalSpan:new{ width = Size.span.vertical_large },
            board_frame,
            VerticalSpan:new{ width = Size.span.vertical_large },
            self.status_text,
            VerticalSpan:new{ width = Size.span.vertical_large },
            digit_buttons,
            VerticalSpan:new{ width = Size.span.vertical_large },
            bottom_buttons,
            VerticalSpan:new{ width = Size.span.vertical_large },
        }
    end
    self[1] = self.layout
    self:updateStatus()
end

function NumbrixScreen:onCellSelected(r, c)
    self.selected      = { r = r, c = c }
    self.pending_digit = nil
    self.board_widget:setSelected(r, c)
    self.board_widget:refresh()
    self:updateStatus()
end

function NumbrixScreen:onDigitKey(d)
    if not self.selected then
        self:updateStatus(_("Tap a cell first."))
        return
    end
    local r, c = self.selected.r, self.selected.c
    local total = self.board.n * self.board.n

    if total <= 9 then
        if d == 0 then return end
        self:_commitValue(r, c, d)
    else
        if self.pending_digit == nil then
            if d == 0 then return end
            self.pending_digit = d
            self:updateStatus(T(_("Entering: %1 (tap another digit or Erase)"), d))
        else
            local v = self.pending_digit * 10 + d
            self.pending_digit = nil
            if v < 1 or v > total then
                self:updateStatus(T(_("Value %1 out of range (1-%2)."), v, total))
                return
            end
            self:_commitValue(r, c, v)
        end
    end
end

function NumbrixScreen:_commitValue(r, c, v)
    local total = self.board.n * self.board.n
    if v < 1 or v > total then
        self:updateStatus(T(_("Value %1 out of range (1-%2)."), v, total))
        return
    end
    local ok, err = self.board:setCell(r, c, v)
    if ok then
        self.plugin:saveState(self.board:serialize())
        if self.board:isSolved() then
            self:updateStatus(_("Congratulations! Puzzle solved!"))
        else
            self:updateStatus()
        end
    else
        self:updateStatus(err == "given" and _("Cannot edit a given cell.") or nil)
    end
    self.board_widget:refresh()
end

function NumbrixScreen:onErase()
    self.pending_digit = nil
    if not self.selected then return end
    local r, c = self.selected.r, self.selected.c
    local ok, err = self.board:clearCell(r, c)
    if ok then
        self.plugin:saveState(self.board:serialize())
    elseif err == "given" then
        self:updateStatus(_("Cannot edit a given cell."))
        return
    end
    self.board_widget:refresh()
    self:updateStatus()
end

function NumbrixScreen:onNewGame()
    local diff = self.plugin:getSetting("difficulty", "easy")
    local n    = self.plugin:getSetting("grid_n", 5)
    self.board = NumbrixBoard:new{ n = n }
    self.board:generate(diff)
    self.selected      = nil
    self.pending_digit = nil
    self.plugin:saveState(self.board:serialize())
    self:buildLayout()
    UIManager:setDirty(self, function() return "ui", self.dimen end)
end

function NumbrixScreen:onCheck()
    self.board:checkConflicts()
    self.board_widget:refresh()
    local remaining = self.board:getRemainingCells()
    if remaining > 0 then
        self:updateStatus(T(_("Check done. %1 cell(s) remaining."), remaining))
    elseif self.board:isSolved() then
        self:updateStatus(_("Congratulations! Puzzle solved!"))
    else
        self:updateStatus(_("Some cells are incorrect."))
    end
end

function NumbrixScreen:openSizeMenu()
    local sizes = {}
    for _, sz in ipairs(GRID_SIZES) do
        sizes[#sizes + 1] = { id = sz, text = sz .. "\xC3\x97" .. sz }
    end
    MenuHelper.openSizeMenu{
        title     = _("Select grid size"),
        sizes     = sizes,
        current   = self.plugin:getSetting("grid_n", 5),
        parent    = self,
        on_select = function(sz)
            if sz ~= self.board.n then
                self.plugin:saveSetting("grid_n", sz)
                self:onNewGame()
            end
        end,
    }
end

function NumbrixScreen:openDifficultyMenu()
    MenuHelper.openDifficultyMenu{
        current   = self.plugin:getSetting("difficulty", "easy"),
        parent    = self,
        on_select = function(id)
            self.plugin:saveSetting("difficulty", id)
            if self.diff_button then
                self.diff_button:setText(self:getDiffButtonText(), self.diff_button.width)
            end
            self:onNewGame()
        end,
    }
end

function NumbrixScreen:updateStatus(msg)
    local status
    if msg then
        status = msg
    elseif self.board:isSolved() then
        status = _("Congratulations! Puzzle solved!")
    else
        local remaining = self.board:getRemainingCells()
        local n         = self.board.n
        local diff      = self.plugin:getSetting("difficulty", "easy")
        local label     = MenuHelper.DIFFICULTY_LABELS[diff] or diff
        status = T(_("%1\xC3\x97%2 (1\xE2\x80\x93%3) \xC2\xB7 %4 \xC2\xB7 Empty: %5"),
            n, n, n * n, label, remaining)
    end
    ScreenBase.updateStatus(self, status)
end

function NumbrixScreen:getSizeButtonText()
    local n = self.board.n
    return T(_("Size: %1"), n .. "\xC3\x97" .. n)
end

function NumbrixScreen:getDiffButtonText()
    local diff  = self.plugin:getSetting("difficulty", "easy")
    local label = MenuHelper.DIFFICULTY_LABELS[diff] or diff
    return T(_("Diff: %1"), label)
end

return NumbrixScreen
