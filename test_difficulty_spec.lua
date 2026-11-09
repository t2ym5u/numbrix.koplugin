-- Difficulty guarantees for Numbrix (see docs/dev/TESTING.md, "Difficulty
-- specs"): every size x level has one solution (exhaustive count) and is
-- finished by the game's own no-trial solver (logic.lua) at the level's
-- tier, Medium and Hard need more than Easy's reach + singles, clue counts
-- fall Easy > Medium > Hard on average (Hard's clues a subset of Medium's),
-- a seed gives the same puzzle, and generation is quick and never reads
-- the clock.
local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"

package.preload["gettext"] = function()
    return setmetatable({}, { __call = function(_, s) return s end })
end
package.path = DIR .. "common/?.lua;" .. DIR .. "?.lua;" .. package.path

-- Runs fn with os.clock/os.time/os.date counted; returns how many times
-- they were read. The play timer (game-common timer.lua, started when a new
-- round begins) is not part of the generator and is left out.
local function clockReads(fn)
    local oc, ot, od = os.clock, os.time, os.date
    local reads = 0
    local function count()
        local src = debug.getinfo(3, "S").source
        if not src:find("timer%.lua$") then reads = reads + 1 end
    end
    os.clock = function(...) count(); return oc(...) end
    os.time  = function(...) count(); return ot(...) end
    os.date  = function(...) count(); return od(...) end
    local ok, err = pcall(fn)
    os.clock, os.time, os.date = oc, ot, od
    if not ok then error(err, 0) end
    return reads
end

local SEEDS = 30

describe("Numbrix difficulty", function()
    local Board, Logic

    setup(function()
        Board = require("board")
        Logic = dofile(DIR .. "logic.lua")
    end)

    local function shown(b)
        local grid, count = {}, 0
        for r = 1, b.n do
            grid[r] = {}
            for c = 1, b.n do
                grid[r][c] = b.given[r][c] and b.puzzle[r][c] or 0
                if grid[r][c] ~= 0 then count = count + 1 end
            end
        end
        return grid, count
    end

    local function gen(n, diff, seed)
        math.randomseed(seed)
        local b = Board:new{ n = n, empty = true }
        b:generate(diff)
        return b
    end

    -- moved from test_board_spec.lua
    it("leaves every generated puzzle with exactly one solution", function()
        for _, n in ipairs({ 5, 6 }) do
            for _, d in ipairs({ "easy", "medium", "hard" }) do
                for seed = 1, 15 do
                    math.randomseed(seed)
                    local b = Board:new{ n = n, difficulty = d }
                    local count, exhausted = Board._countCompletions(
                        b.puzzle, b.given, n, 2, 1e7)
                    assert.is_false(exhausted)
                    assert.are.equal(1, count)
                end
            end
        end
    end)

    -- moved from test_board_spec.lua
    it("generates 5x5 puzzles quickly (some starts used to burn a whole search budget)", function()
        local t = os.clock()
        for seed = 1, 60 do
            math.randomseed(seed)
            Board:new{ n = 5, difficulty = "hard" }
        end
        assert.is_true(os.clock() - t < 3, "60 puzzles took " .. (os.clock() - t) .. " s")
    end)

    -- moved from test_board_spec.lua
    it("every level is solved by logic alone, with the level's rules", function()
        for _, n in ipairs({ 5, 6 }) do
            for _, diff in ipairs({ "easy", "medium", "hard" }) do
                local tier = ({ easy = 1, medium = 2, hard = 3 })[diff]
                for seed = 1, SEEDS do
                    local b = gen(n, diff, seed)
                    local grid = shown(b)
                    local where = ("n=%d %s seed %d"):format(n, diff, seed)
                    local ok, vals = Logic.solve(grid, n, tier)
                    assert.is_true(ok, where)
                    for r = 1, n do
                        for c = 1, n do
                            assert.are.equal(b.solution[r][c], vals[(r - 1) * n + c], where)
                        end
                    end
                    -- Medium and Hard really need more than reach + singles.
                    if diff ~= "easy" then
                        assert.is_false((Logic.solve(grid, n, 1)), where)
                    end
                end
            end
        end
    end)

    -- moved from test_board_spec.lua
    it("Medium and Hard differ, Hard showing a subset of Medium's clues", function()
        for _, n in ipairs({ 5, 6 }) do
            local sums = { easy = 0, medium = 0, hard = 0 }
            for seed = 1, SEEDS do
                local e, m, h = gen(n, "easy", seed), gen(n, "medium", seed), gen(n, "hard", seed)
                local _, ce = shown(e)
                local _, cm = shown(m)
                local _, ch = shown(h)
                sums.easy, sums.medium, sums.hard = sums.easy + ce, sums.medium + cm, sums.hard + ch
                assert.is_true(ch < cm, ("n=%d seed %d: Hard %d clues, Medium %d"):format(n, seed, ch, cm))
                for r = 1, n do
                    for c = 1, n do
                        if h.given[r][c] then assert.is_true(m.given[r][c]) end
                    end
                end
            end
            assert.is_true(sums.easy > sums.medium and sums.medium > sums.hard,
                ("n=%d clue totals %d / %d / %d"):format(n, sums.easy, sums.medium, sums.hard))
        end
    end)

    -- moved from test_board_spec.lua
    it("the same seed gives the same puzzle", function()
        for _, n in ipairs({ 5, 6 }) do
            for _, diff in ipairs({ "easy", "medium", "hard" }) do
                for seed = 1, 5 do
                    local a, b = gen(n, diff, seed), gen(n, diff, seed)
                    assert.are.same(a.solution, b.solution)
                    assert.are.same(a.given, b.given)
                end
            end
        end
    end)

    -- moved from test_board_spec.lua
    it("generates quickly at every size and level", function()
        for _, n in ipairs({ 5, 6 }) do
            for _, diff in ipairs({ "easy", "medium", "hard" }) do
                local worst = 0
                for seed = 1, SEEDS do
                    math.randomseed(seed)
                    local b = Board:new{ n = n, empty = true }
                    local t0 = os.clock()
                    b:generate(diff)
                    worst = math.max(worst, os.clock() - t0)
                end
                -- generous: ~0.025 s worst on a desktop
                assert.is_true(worst < 0.5, ("n=%d %s took %.3f s"):format(n, diff, worst))
            end
        end
    end)

    it("generation never reads the clock", function()
        for _, n in ipairs({ 5, 6 }) do
            for _, diff in ipairs({ "easy", "medium", "hard" }) do
                local reads = clockReads(function() gen(n, diff, 404 + n) end)
                assert.are.equal(0, reads, ("n=%d %s read the clock"):format(n, diff))
            end
        end
    end)
end)
