local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"

package.preload["gettext"] = function()
    return setmetatable({}, { __call = function(_, s) return s end })
end
package.path = DIR .. "common/?.lua;" .. DIR .. "?.lua;" .. package.path

describe("NumbrixBoard", function()
    local Board

    setup(function()
        Board = require("board")
    end)


    -- Regression guard for the 2026-07-21 bug: same DFS-success-check bug as
    -- hidato (dfs's `step > total` check was unreachable), guaranteeing 100%
    -- generation failure. These tests assert the solution is a genuine
    -- orthogonal Hamiltonian path -- the property that broke before the fix.
    local function newBoard(n, diff)
        math.randomseed(42)
        return Board:new{ n = n or 5, difficulty = diff or "easy" }
    end

    local function isOrthoAdjacent(r1, c1, r2, c2)
        local dr, dc = math.abs(r1 - r2), math.abs(c1 - c2)
        return (dr == 1 and dc == 0) or (dr == 0 and dc == 1)
    end

    describe("construction", function()
        it("creates a 5×5 board by default and auto-generates", function()
            local b = Board:new()
            assert.are.equal(5, b.n)
            assert.is_not_nil(b.solution)
        end)
    end)

    describe("generate", function()
        it("solution is a valid orthogonal Hamiltonian path (1..n²)", function()
            local b = newBoard(5)
            local n = b.n
            local total = n * n
            local pos = {}
            for r = 1, n do
                for c = 1, n do
                    local v = b.solution[r][c]
                    assert.is_true(v >= 1 and v <= total, ("out-of-range value %s"):format(tostring(v)))
                    assert.is_nil(pos[v], ("value %d appears twice"):format(v))
                    pos[v] = { r, c }
                end
            end
            for v = 1, total - 1 do
                local a, b2 = pos[v], pos[v + 1]
                assert.is_true(isOrthoAdjacent(a[1], a[2], b2[1], b2[2]),
                    ("values %d and %d are not orthogonally adjacent"):format(v, v + 1))
            end
        end)

        it("reveals cell 1 and n² as given", function()
            local b = newBoard(5)
            local n = b.n
            local total = n * n
            local found1, foundN = false, false
            for r = 1, n do
                for c = 1, n do
                    if b.given[r][c] then
                        if b.puzzle[r][c] == 1 then found1 = true end
                        if b.puzzle[r][c] == total then foundN = true end
                    end
                end
            end
            assert.is_true(found1)
            assert.is_true(foundN)
        end)

        it("runs across all sizes/difficulties without hanging or erroring", function()
            for _, n in ipairs({ 4, 5, 6 }) do
                for _, diff in ipairs({ "easy", "medium", "hard" }) do
                    math.randomseed(n * 100 + #diff)
                    local ok = pcall(function() Board:new{ n = n, difficulty = diff } end)
                    assert.is_true(ok, ("generate failed for n=%d diff=%s"):format(n, diff))
                end
            end
        end)
    end)

    describe("setCell / clearCell / isSolved", function()
        it("filling every cell with the solution values solves the board", function()
            local b = newBoard(5)
            local n = b.n
            for r = 1, n do
                for c = 1, n do
                    if not b:isGiven(r, c) then
                        b:setCell(r, c, b.solution[r][c])
                    end
                end
            end
            assert.is_true(b:isSolved())
        end)

        it("checkConflicts flags a wrong value", function()
            local b = newBoard(5)
            local n = b.n
            local r, c
            for rr = 1, n do
                for cc = 1, n do
                    if not b:isGiven(rr, cc) then r, c = rr, cc; goto done end
                end
            end
            ::done::
            assert.is_not_nil(r)
            local wrong_value = (b.solution[r][c] % (n * n)) + 1
            b:setCell(r, c, wrong_value)
            b:checkConflicts()
            assert.is_true(b.wrong_marks[r][c])
        end)
    end)

    describe("serialize / load", function()
        it("round-trips puzzle, given and user state", function()
            local b = newBoard(5)
            local n = b.n
            local r, c
            for rr = 1, n do
                for cc = 1, n do
                    if not b:isGiven(rr, cc) then r, c = rr, cc; goto done end
                end
            end
            ::done::
            b:setCell(r, c, b.solution[r][c])

            local data = b:serialize()
            local b2   = Board:new{ n = n }
            local ok   = b2:load(data)
            assert.is_true(ok)
            assert.are.equal(b.n, b2.n)
            assert.are.equal(b.solution[r][c], b2:getWorkingValue(r, c))
        end)

        it("load returns false for invalid data", function()
            local b = Board:new()
            assert.is_false(b:load(nil))
            assert.is_false(b:load({}))
        end)
    end)
end)
