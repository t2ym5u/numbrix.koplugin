local grid_utils = require("grid_utils")
local Hint      = require("hint")

local emptyGrid     = grid_utils.emptyGrid
local emptyBoolGrid = grid_utils.emptyBoolGrid
local copyGrid      = grid_utils.copyGrid

local DEFAULT_N          = 5
local DEFAULT_DIFFICULTY = "easy"

-- logic.lua sits next to this file; load it by path (plugin-own modules
-- share names across plugins, see docs/dev/PITFALLS.md).
local _dir  = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local Logic = assert(loadfile(_dir .. "logic.lua"))()

-- Difficulty ids; generate() says how each one is graded by logic.lua.
local LOGIC_LEVELS = { easy = 1, medium = 2, hard = 3 }
-- Easy keeps at least this share of the clues between 1 and n*n.
local EASY_GIVEN_RATIO = 0.40
-- Medium/Hard: paths tried for one that really needs the level's rule.
local DIG_ATTEMPTS = 6

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

    -- On an odd grid the path alternates checkerboard colours and visits one
    -- more cell of the corner colour ((r + c) even) than of the other, so it
    -- can only start on a corner-colour cell. A start on the other colour
    -- always fails -- after burning the whole node budget -- so skip it. The
    -- search draws no random numbers, so the puzzles are unchanged.
    for attempt = 1, math.min(50, #starts) do
        local sr, sc = starts[attempt][1], starts[attempt][2]
        if n % 2 == 0 or (sr + sc) % 2 == 0 then
            if dfs(sr, sc, 1) then
                return pos, path
            end
            visited = emptyBoolGrid(n)
            pos     = emptyGrid(n)
            path    = {}
            nodes   = 0
        end
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

-- Since 1.6.0 the generator grades with logic.lua instead (a grid it fills
-- by forced steps has exactly one solution); this exhaustive counter stays
-- as the specs' independent uniqueness check.

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

    -- given_at[num] = {r, c} of the given cell holding num: one grid scan
    -- here instead of one per search node.
    local given_at = {}
    for r = 1, n do
        for c = 1, n do
            if given[r][c] and puzzle[r][c] > 0 and not given_at[puzzle[r][c]] then
                given_at[puzzle[r][c]] = { r, c }
            end
        end
    end

    -- next_given[num] = the smallest given number above num. A cell can only
    -- hold num if that given cell is at most (next - num) steps away, which
    -- cuts dead branches early without ever dropping a real solution.
    local next_given = {}
    for k = total - 1, 1, -1 do
        next_given[k] = given_at[k + 1] and (k + 1) or next_given[k + 1]
    end
    local function reachable(r, c, num)
        local m = next_given[num]
        if not m then return true end
        local g = given_at[m]
        return math.abs(r - g[1]) + math.abs(c - g[2]) <= m - num
    end

    local function search(num)
        if solutions >= limit or exhausted then return end
        nodes = nodes + 1
        if nodes > node_budget then exhausted = true; return end
        if num > total then solutions = solutions + 1; return end

        local given_pos = given_at[num]
        if num == 1 then
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
                if not given[cand[1]][cand[2]] and reachable(cand[1], cand[2], num) then
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
    -- opts.empty: the caller loads a save or generates itself, so don't
    -- build a puzzle that would be thrown away.
    if not opts.empty then obj:generate(obj.difficulty) end
    return obj
end

-- ---------------------------------------------------------------------------
-- Generate
-- ---------------------------------------------------------------------------

-- One dig: a random path, then clues removed one at a time in a random
-- order. A clue is removed if logic.lua, allowed rules up to `tier`, still
-- fills the whole grid; otherwise it goes back. 1 and n*n always stay.
-- Every state of the dig is a checked puzzle, so any prefix of the
-- removals is one too. newDig() draws the path and the order; the dig
-- table then holds the puzzle as dug so far and its removals (numbers, in
-- order). Same scheme as hidato.koplugin.
local function newDig(n)
    local total = n * n
    local sol, path = generatePath(n)
    local puzzle = emptyGrid(n)
    for k = 1, total do
        puzzle[path[k][1]][path[k][2]] = k
    end
    local order = {}
    for k = 2, total - 1 do order[#order + 1] = k end
    for i = #order, 2, -1 do
        local j = math.random(i)
        order[i], order[j] = order[j], order[i]
    end
    return { n = n, sol = sol, path = path, puzzle = puzzle, order = order, removals = {} }
end

-- One pass over the clues still shown. Stops once `stop_after` clues are
-- removed in all. Returns how many this pass removed.
local function digPass(dig, tier, stop_after, on_progress)
    local path, puzzle, removals = dig.path, dig.puzzle, dig.removals
    local removed = 0
    for i, k in ipairs(dig.order) do
        if #removals >= stop_after then break end
        if on_progress then on_progress(i / #dig.order) end
        local r, c = path[k][1], path[k][2]
        if puzzle[r][c] ~= 0 then
            puzzle[r][c] = 0
            if Logic.solve(puzzle, dig.n, tier) then
                removals[#removals + 1] = k
                removed = removed + 1
            else
                puzzle[r][c] = k
            end
        end
    end
    return removed
end

-- The puzzle after the first `count` removals of the dig.
local function digPrefix(dig, count)
    local n, path = dig.n, dig.path
    local puzzle = emptyGrid(n)
    for k = 1, n * n do
        puzzle[path[k][1]][path[k][2]] = k
    end
    for i = 1, count do
        local k = dig.removals[i]
        puzzle[path[k][1]][path[k][2]] = 0
    end
    return puzzle
end

-- Levels, all graded by logic.lua (no level ever needs a guess):
--   Easy   dug with tier 1 only (reach + singles), and at least
--          EASY_GIVEN_RATIO of the clues between 1 and n*n stay.
--   Hard   dug with tier 2 (neighbours), then with tier 3 (short segments):
--          the fewest clues; needs the neighbour rule, and the segment rule
--          whenever tier 3 removed something.
--   Medium the same dig stopped halfway between Easy's clue count and the
--          end of tier 2, and never before the first removal tier 1 cannot
--          solve: needs the neighbour rule, shows more clues than Hard
--          (and, mostly, fewer than Easy).
-- (Fewer clues never make a puzzle easier for logic.lua, so "tier 1 can
-- solve it" switches off once along the dig and a binary search finds it.)
-- A dig that tier 1 can still solve at the end, or where Medium would equal
-- Hard, is redone on a new path, a bounded number of times (counted, never
-- timed: the same seed must give the same puzzle on every device). If all
-- fail, the last dig is used anyway; it is still solvable without guessing.
--
-- on_progress (optional): called with a 0..1 fraction while digging, for
-- game-common's GenProgress bar.
function NumbrixBoard:generate(difficulty, on_progress)
    self.difficulty = difficulty or self.difficulty
    local n     = self.n
    local total = n * n
    local diff  = LOGIC_LEVELS[self.difficulty] and self.difficulty or "medium"

    local easy_removals = (total - 2) - math.floor((total - 2) * EASY_GIVEN_RATIO)
    local dig, keep
    if diff == "easy" then
        dig = newDig(n)
        digPass(dig, 1, easy_removals, on_progress)
        keep = #dig.removals
    else
        for attempt = 1, DIG_ATTEMPTS do
            -- Most first attempts succeed: give the first one 80 % of the
            -- bar and each later one 80 % of what is left.
            local from, span = 1 - 0.2 ^ (attempt - 1), 0.8 * 0.2 ^ (attempt - 1)
            local function progress(f)
                if on_progress then on_progress(from + span * f * 0.5) end
            end
            dig = newDig(n)
            digPass(dig, 2, total, progress)
            local m = #dig.removals
            -- First prefix length that tier 1 cannot solve (m + 1: none).
            local lo, hi = 0, m + 1
            if Logic.solve(dig.puzzle, n, 1) then lo = m + 1 end
            while hi - lo > 1 do
                local mid = math.floor((lo + hi) / 2)
                if Logic.solve(digPrefix(dig, mid), n, 1) then lo = mid else hi = mid end
            end
            local first_l2 = lo + 1
            local ok = first_l2 <= m
            local tier3 = 0
            if ok and (diff == "hard" or first_l2 == m) then
                tier3 = digPass(dig, 3, total, function(f) progress(1 + f) end)
            end
            if diff == "hard" then
                keep = #dig.removals
            else
                -- Halfway between Easy's clue count and the end of tier 2,
                -- but never before tier 1 fails nor at the very end.
                local mid = math.floor((easy_removals + m) / 2)
                keep = math.min(math.max(first_l2, math.min(mid, m - 1)), m)
            end
            if ok and (m > first_l2 or tier3 > 0) then break end
        end
    end
    if on_progress then on_progress(1) end
    self.solution = dig.sol
    local path, removals = dig.path, dig.removals

    local puzzle = emptyGrid(n)
    local given  = emptyBoolGrid(n)
    for k = 1, total do
        local r, c = path[k][1], path[k][2]
        puzzle[r][c] = k
        given[r][c]  = true
    end
    for i = 1, keep do
        local k = removals[i]
        local r, c = path[k][1], path[k][2]
        puzzle[r][c] = 0
        given[r][c]  = false
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

Hint.install(NumbrixBoard, {
    getUser     = function(b, r, c) return b.user[r][c] end,
    getSolution = function(b, r, c) return b.solution[r][c] end,
    isGiven     = function(b, r, c) return b:isGiven(r, c) end,
    setCell     = function(b, r, c, v) return b:setCell(r, c, v) end,
    clearCell   = function(b, r, c) return b:clearCell(r, c) end,
})

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

NumbrixBoard._countCompletions = countCompletions   -- for the specs

return NumbrixBoard
