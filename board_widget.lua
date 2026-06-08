local Blitbuffer = require("ffi/blitbuffer")
local Geom       = require("ui/geometry")
local RenderText = require("ui/rendertext")
local Size       = require("ui/size")

local gwb            = require("grid_widget_base")
local GridWidgetBase = gwb.GridWidgetBase
local drawLine       = gwb.drawLine

-- ---------------------------------------------------------------------------
-- Colour palette
-- ---------------------------------------------------------------------------

local C_BG        = Blitbuffer.COLOR_WHITE
local C_SEL       = Blitbuffer.COLOR_GRAY_D
local C_GIVEN_BG  = Blitbuffer.COLOR_GRAY_E
local C_WRONG     = Blitbuffer.COLOR_GRAY_B
local C_LINE      = Blitbuffer.COLOR_BLACK
local C_GIVEN_FG  = Blitbuffer.COLOR_BLACK
local C_USER_FG   = Blitbuffer.COLOR_GRAY_2

-- ---------------------------------------------------------------------------
-- NumbrixBoardWidget
-- ---------------------------------------------------------------------------

local NumbrixBoardWidget = GridWidgetBase:extend{
    board = nil,
}

function NumbrixBoardWidget:init()
    local n       = self.board and self.board.n or 5
    self.cols     = n
    self.rows     = n
    self.size_ratio = 0.82
    GridWidgetBase.init(self)
    self._n = n
end

function NumbrixBoardWidget:onCellTap(row, col)
    if self.onCellSelected then
        self.onCellSelected(row, col)
    end
end

-- ---------------------------------------------------------------------------
-- paintTo
-- ---------------------------------------------------------------------------

function NumbrixBoardWidget:paintTo(bb, x, y)
    if not self.board then return end
    self.paint_rect = Geom:new{ x = x, y = y, w = self.dimen.w, h = self.dimen.h }

    local n    = self._n
    local cell = self.cell_w

    -- White background
    bb:paintRect(x, y, self.dimen.w, self.dimen.h, C_BG)

    -- -----------------------------------------------------------------------
    -- Cell backgrounds
    -- -----------------------------------------------------------------------
    for r = 1, n do
        for c = 1, n do
            local cx = x + math.floor((c - 1) * cell)
            local cy = y + math.floor((r - 1) * cell)
            local cw = math.ceil(cell)
            local ch = math.ceil(cell)

            if self.selected and self.selected.r == r and self.selected.c == c then
                bb:paintRect(cx, cy, cw, ch, C_SEL)
            elseif self.board.wrong_marks[r][c] then
                bb:paintRect(cx, cy, cw, ch, C_WRONG)
            elseif self.board:isGiven(r, c) then
                bb:paintRect(cx, cy, cw, ch, C_GIVEN_BG)
            end
        end
    end

    -- -----------------------------------------------------------------------
    -- Grid lines
    -- -----------------------------------------------------------------------
    local thin  = Size.line.thin  or 1
    local thick = Size.line.thick or 2

    for i = 0, n do
        local lw = (i == 0 or i == n) and thick or thin
        drawLine(bb, x + math.floor(i * cell), y, lw, self.dimen.h, C_LINE)
        drawLine(bb, x, y + math.floor(i * cell), self.dimen.w, lw, C_LINE)
    end

    -- -----------------------------------------------------------------------
    -- Cell values
    -- -----------------------------------------------------------------------
    local cell_padding = self.number_padding or 2
    local cell_inner   = math.max(1, math.floor(cell - 2 * cell_padding))

    for r = 1, n do
        for c = 1, n do
            local v = self.board:getDisplayValue(r, c)
            if v ~= 0 then
                local cx    = x + math.floor((c - 1) * cell)
                local cy    = y + math.floor((r - 1) * cell)
                local text  = tostring(v)
                local color = self.board:isGiven(r, c) and C_GIVEN_FG or C_USER_FG
                local m     = RenderText:sizeUtf8Text(0, cell_inner, self.number_face, text, true, false)
                local base  = cy + cell_padding + math.floor((cell_inner + m.y_top - m.y_bottom) / 2)
                local tx    = cx + cell_padding + math.floor((cell_inner - m.x) / 2)
                RenderText:renderUtf8Text(bb, tx, base, self.number_face, text, true, false, color)
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Selection
-- ---------------------------------------------------------------------------

function NumbrixBoardWidget:setSelected(r, c)
    self.selected = r and c and { r = r, c = c } or nil
end

return NumbrixBoardWidget
