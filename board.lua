local grid_utils = require("grid_utils")

local emptyGrid     = grid_utils.emptyGrid
local emptyBoolGrid = grid_utils.emptyBoolGrid
local copyGrid      = grid_utils.copyGrid

local DEFAULT_N          = 5
local DEFAULT_DIFFICULTY = "easy"

-- Fraction of non-endpoint cells revealed as clues
local GIVEN_RATIOS = { easy = 0.40, medium = 0.25, hard = 0.15 }

-- 4-directional adjacency (orthogonal only — the key difference from Hidato)
local DIRS = {
    { -1, 0 },
    {  1, 0 },
    {  0, -1 },
    {  0,  1 },
}

-- ---------------------------------------------------------------------------
-- Hamiltonian path generation via DFS (orthogonal)
-- ---------------------------------------------------------------------------

-- Node budget per start attempt: bounds worst-case latency if the Warnsdorff
-- heuristic backtracks badly on a given start (see hidato.koplugin's board.lua
-- for the sibling bug this generator originally shared: the old success
-- check `step > total` was unreachable since dfs is never called past
-- step==total, so the search could never terminate successfully).
local NODE_BUDGET_PER_START = 20000

local function generatePath(n)
    local total   = n * n
    local visited = emptyBoolGrid(n)
    local path    = {}
    local pos     = emptyGrid(n)
    local nodes   = 0

    local function dfs(r, c, step)
        nodes = nodes + 1
        if nodes > NODE_BUDGET_PER_START then return false end
        visited[r][c] = true
        pos[r][c]     = step
        path[step]    = { r, c }

        if step == total then return true end

        -- Warnsdorff heuristic: sort by fewest onward moves
        local moves = {}
        for _, d in ipairs(DIRS) do
            local nr, nc = r + d[1], c + d[2]
            if nr >= 1 and nr <= n and nc >= 1 and nc <= n and not visited[nr][nc] then
                local fwd = 0
                for _, d2 in ipairs(DIRS) do
                    local nr2, nc2 = nr + d2[1], nc + d2[2]
                    if nr2 >= 1 and nr2 <= n and nc2 >= 1 and nc2 <= n
                            and not visited[nr2][nc2] and not (nr2 == r and nc2 == c) then
                        fwd = fwd + 1
                    end
                end
                moves[#moves + 1] = { nr, nc, fwd }
            end
        end
        table.sort(moves, function(a, b) return a[3] < b[3] end)

        for _, mv in ipairs(moves) do
            if dfs(mv[1], mv[2], step + 1) then return true end
        end

        -- Backtrack
        visited[r][c] = false
        pos[r][c]     = 0
        path[step]    = nil
        return false
    end

    -- Try up to 50 random starting cells
    local starts = {}
    for r = 1, n do
        for c = 1, n do
            starts[#starts + 1] = { r, c }
        end
    end
    for i = #starts, 2, -1 do
        local j = math.random(i)
        starts[i], starts[j] = starts[j], starts[i]
    end

    for attempt = 1, math.min(50, #starts) do
        local sr, sc = starts[attempt][1], starts[attempt][2]
        if dfs(sr, sc, 1) then
            return pos, path
        end
        visited = emptyBoolGrid(n)
        pos     = emptyGrid(n)
        path    = {}
        nodes   = 0
    end

    -- Fallback: snake pattern (always has a valid orthogonal Hamiltonian path)
    pos  = emptyGrid(n)
    path = {}
    for r = 1, n do
        for c = 1, n do
            -- Odd rows go left-to-right, even rows go right-to-left (snake)
            local actual_c = (r % 2 == 1) and c or (n - c + 1)
            local v = (r - 1) * n + c
            pos[r][actual_c] = v
            path[v] = { r, actual_c }
        end
    end
    return pos, path
end

-- ---------------------------------------------------------------------------
-- Uniqueness check
-- ---------------------------------------------------------------------------

-- Counts Hamiltonian-path completions (up to `limit`) consistent with the
-- given fixed cells, placing numbers 1..n*n in path order (each must land on
-- an orthogonally-adjacent unoccupied cell, or the pre-fixed cell if given).
-- Returns (solutions_found, exhausted); exhausted=true means node_budget was
-- hit before the search concluded, so the count isn't proof. Mirrors
-- sudokukiller.koplugin/board.lua's countCageSolutions.
local NODE_BUDGET_UNIQUENESS = 200000

local function countCompletions(puzzle, given, n, limit, node_budget)
    local total = n * n
    local cell_of_num = {}
    local num_of_cell = {}
    for r = 1, n do num_of_cell[r] = {} end

    local solutions, nodes, exhausted = 0, 0, false

    local function search(num)
        if solutions >= limit or exhausted then return end
        nodes = nodes + 1
        if nodes > node_budget then exhausted = true; return end
        if num > total then solutions = solutions + 1; return end

        local given_pos = nil
        if num == 1 then
            for r = 1, n do
                for c = 1, n do
                    if given[r][c] and puzzle[r][c] == 1 then given_pos = { r, c }; break end
                end
                if given_pos then break end
            end
            if given_pos then
                cell_of_num[1] = given_pos
                num_of_cell[given_pos[1]][given_pos[2]] = 1
                search(2)
                num_of_cell[given_pos[1]][given_pos[2]] = nil
            else
                for r = 1, n do
                    for c = 1, n do
                        if not num_of_cell[r][c] then
                            cell_of_num[1] = { r, c }
                            num_of_cell[r][c] = 1
                            search(2)
                            num_of_cell[r][c] = nil
                            if solutions >= limit or exhausted then return end
                        end
                    end
                end
            end
            return
        end

        for r = 1, n do
            for c = 1, n do
                if given[r][c] and puzzle[r][c] == num then given_pos = { r, c }; break end
            end
            if given_pos then break end
        end

        local prev = cell_of_num[num - 1]
        local candidates = {}
        for _, d in ipairs(DIRS) do
            local nr, nc = prev[1] + d[1], prev[2] + d[2]
            if nr >= 1 and nr <= n and nc >= 1 and nc <= n and not num_of_cell[nr][nc] then
                candidates[#candidates + 1] = { nr, nc }
            end
        end
        if given_pos then
            local ok = false
            for _, cand in ipairs(candidates) do
                if cand[1] == given_pos[1] and cand[2] == given_pos[2] then ok = true; break end
            end
            if ok then
                cell_of_num[num] = given_pos
                num_of_cell[given_pos[1]][given_pos[2]] = num
                search(num + 1)
                num_of_cell[given_pos[1]][given_pos[2]] = nil
            end
        else
            for _, cand in ipairs(candidates) do
                if not given[cand[1]][cand[2]] then
                    cell_of_num[num] = cand
                    num_of_cell[cand[1]][cand[2]] = num
                    search(num + 1)
                    num_of_cell[cand[1]][cand[2]] = nil
                    if solutions >= limit or exhausted then return end
                end
            end
        end
    end

    search(1)
    return solutions, exhausted
end

-- ---------------------------------------------------------------------------
-- NumbrixBoard
-- ---------------------------------------------------------------------------

local NumbrixBoard = {}
NumbrixBoard.__index = NumbrixBoard

function NumbrixBoard:new(opts)
    opts = opts or {}
    local obj = setmetatable({
        n           = opts.n or DEFAULT_N,
        difficulty  = opts.difficulty or DEFAULT_DIFFICULTY,
        solution    = nil,
        puzzle      = nil,
        user        = nil,
        given       = nil,
        wrong_marks = nil,
        sel_r       = nil,
        sel_c       = nil,
    }, self)
    obj:generate(obj.difficulty)
    return obj
end

-- ---------------------------------------------------------------------------
-- Generate
-- ---------------------------------------------------------------------------

function NumbrixBoard:generate(difficulty)
    self.difficulty = difficulty or self.difficulty
    local n         = self.n
    local total     = n * n

    local sol, path = generatePath(n)
    self.solution = sol

    local given_ratio = GIVEN_RATIOS[self.difficulty] or 0.25

    -- Start fully revealed, then dig cells one at a time (like sudoku-
    -- common's hole-digging), verifying with countCompletions after each
    -- tentative removal and putting the cell back if that broke uniqueness.
    -- Unlike the old "shuffle positions, keep top ratio%" approach (which
    -- never checked whether the remaining clues still pin down a single
    -- path), this guarantees every generated puzzle has exactly one
    -- solution. Endpoints (1 and n*n) always stay given -- removing either
    -- is never attempted.
    local puzzle = emptyGrid(n)
    local given  = emptyBoolGrid(n)
    for k = 1, total do
        local r, c = path[k][1], path[k][2]
        puzzle[r][c] = k
        given[r][c]  = true
    end

    local intermediate = {}
    for k = 2, total - 1 do
        intermediate[#intermediate + 1] = k
    end
    for i = #intermediate, 2, -1 do
        local j = math.random(i)
        intermediate[i], intermediate[j] = intermediate[j], intermediate[i]
    end

    local num_extra   = math.floor((total - 2) * given_ratio)
    local target_hide = (total - 2) - num_extra
    local hidden      = 0
    for _, k in ipairs(intermediate) do
        if hidden >= target_hide then break end
        local r, c = path[k][1], path[k][2]
        local saved = puzzle[r][c]
        puzzle[r][c] = 0
        given[r][c]  = false
        local solutions, exhausted = countCompletions(puzzle, given, n, 2, NODE_BUDGET_UNIQUENESS)
        if not exhausted and solutions == 1 then
            hidden = hidden + 1
        else
            puzzle[r][c] = saved
            given[r][c]  = true
        end
    end

    self.puzzle      = puzzle
    self.given       = given
    self.user        = emptyGrid(n)
    self.wrong_marks = emptyBoolGrid(n)
    self.sel_r       = nil
    self.sel_c       = nil
end

-- ---------------------------------------------------------------------------
-- Cell access
-- ---------------------------------------------------------------------------

function NumbrixBoard:isGiven(r, c)
    return self.given[r] and self.given[r][c] == true
end

function NumbrixBoard:getWorkingValue(r, c)
    if self:isGiven(r, c) then
        return self.puzzle[r][c]
    end
    return self.user[r][c]
end

function NumbrixBoard:getDisplayValue(r, c)
    return self:getWorkingValue(r, c)
end

function NumbrixBoard:selectCell(r, c)
    self.sel_r = r
    self.sel_c = c
end

function NumbrixBoard:setCell(r, c, v)
    if self:isGiven(r, c) then return false, "given" end
    local total = self.n * self.n
    if v < 1 or v > total then return false, "range" end
    self.user[r][c]        = v
    self.wrong_marks[r][c] = false
    return true
end

function NumbrixBoard:clearCell(r, c)
    if self:isGiven(r, c) then return false, "given" end
    self.user[r][c]        = 0
    self.wrong_marks[r][c] = false
    return true
end

-- ---------------------------------------------------------------------------
-- Validation
-- ---------------------------------------------------------------------------

function NumbrixBoard:checkConflicts()
    local n = self.n
    for r = 1, n do
        for c = 1, n do
            local v = self:getWorkingValue(r, c)
            self.wrong_marks[r][c] = (v ~= 0 and v ~= self.solution[r][c])
        end
    end
end

function NumbrixBoard:isSolved()
    local n = self.n
    for r = 1, n do
        for c = 1, n do
            if self:getWorkingValue(r, c) ~= self.solution[r][c] then
                return false
            end
        end
    end
    return true
end

function NumbrixBoard:getRemainingCells()
    local n   = self.n
    local cnt = 0
    for r = 1, n do
        for c = 1, n do
            if self:getWorkingValue(r, c) == 0 then cnt = cnt + 1 end
        end
    end
    return cnt
end

-- ---------------------------------------------------------------------------
-- Serialization
-- ---------------------------------------------------------------------------

function NumbrixBoard:serialize()
    local n = self.n
    local given_out = emptyBoolGrid(n)
    for r = 1, n do
        for c = 1, n do
            given_out[r][c] = self.given[r][c] and 1 or 0
        end
    end
    local wrong_out = emptyBoolGrid(n)
    for r = 1, n do
        for c = 1, n do
            wrong_out[r][c] = self.wrong_marks[r][c] and 1 or 0
        end
    end
    return {
        n           = n,
        difficulty  = self.difficulty,
        solution    = copyGrid(self.solution, n),
        puzzle      = copyGrid(self.puzzle, n),
        user        = copyGrid(self.user, n),
        given       = given_out,
        wrong_marks = wrong_out,
    }
end

function NumbrixBoard:load(data)
    if type(data) ~= "table" or not data.solution then return false end
    local n = data.n or DEFAULT_N
    self.n          = n
    self.difficulty = data.difficulty or DEFAULT_DIFFICULTY
    self.solution   = copyGrid(data.solution, n)
    self.puzzle     = copyGrid(data.puzzle or {}, n)
    self.user       = copyGrid(data.user or {}, n)

    self.given = emptyBoolGrid(n)
    if data.given then
        for r = 1, n do
            for c = 1, n do
                local v = data.given[r] and data.given[r][c]
                self.given[r][c] = (v == true or v == 1)
            end
        end
    end

    self.wrong_marks = emptyBoolGrid(n)
    if data.wrong_marks then
        for r = 1, n do
            for c = 1, n do
                local v = data.wrong_marks[r] and data.wrong_marks[r][c]
                self.wrong_marks[r][c] = (v == true or v == 1)
            end
        end
    end

    self.sel_r = nil
    self.sel_c = nil
    return true
end

NumbrixBoard.DIRS = DIRS

return NumbrixBoard
