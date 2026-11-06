-- Human-style, no-trial solver for Numbrix: every number 1..n*n goes on one
-- cell, and consecutive numbers sit on cells that share a side. Used by the
-- generator to grade a dig: a clue may only be removed if this solver can
-- still finish the grid, so a player never has to guess.
--
-- Vendored from hidato.koplugin/logic.lua (1.6.0), which handles both
-- geometries; here solve() always uses the orthogonal one (rook steps plus
-- parity). Keep the two copies in step when fixing a bug in either.
--
-- The solver only ever writes a number that the rules below force; it never
-- tries a value to see whether it leads to a contradiction. Rules, by tier:
--
--   1. Reach + singles. Number k lies between the nearest placed numbers
--      lo < k < hi, so its cell is at most k - lo steps from lo and at most
--      hi - k steps from hi, with the same parity (a path of s steps on a
--      checkerboard ends on a cell of colour s mod 2). A number with one
--      such cell goes there; a free cell that only one number can reach gets
--      that number (every cell holds a number).
--   2. Neighbours. k can only sit on a cell next to a possible cell of k - 1
--      and of k + 1 (two different cells). Cells that fail are struck out,
--      and the strikes stand for the rest of the solve.
--   3. Short segments. Between two placed numbers with at most SEGMENT_MAX
--      numbers missing, trace every route through the remaining
--      possibilities: a number keeps only the cells some route uses for it,
--      and a cell that every route goes through is taken by that segment.
--
-- Returns solved (bool), values (cell index -> number, row-major) and a
-- stats table { single = , neighbour = , segment = } counting the numbers
-- placed with each tier's help (the highest tier needed for that placement).

local SEGMENT_MAX = 3

local geometry_cache = {}

local function geometry(n, orthogonal)
    local key = n * 2 + (orthogonal and 1 or 0)
    local g = geometry_cache[key]
    if g then return g end
    local total = n * n
    local dist, adj, nbrs = {}, {}, {}
    for i = 1, total do
        local r1, c1 = math.floor((i - 1) / n), (i - 1) % n
        local di, ai, ni = {}, {}, {}
        for j = 1, total do
            local r2, c2 = math.floor((j - 1) / n), (j - 1) % n
            local dr, dc = r1 - r2, c1 - c2
            if dr < 0 then dr = -dr end
            if dc < 0 then dc = -dc end
            local d
            if orthogonal then d = dr + dc else d = dr > dc and dr or dc end
            di[j] = d
            ai[j] = d == 1
            if d == 1 then ni[#ni + 1] = j end
        end
        dist[i], adj[i], nbrs[i] = di, ai, ni
    end
    g = { dist = dist, adj = adj, nbrs = nbrs }
    geometry_cache[key] = g
    return g
end

-- grid[r][c]: the number shown on (r, c), 0 when empty.
-- level: highest rule tier allowed (1, 2 or 3).
local function solve(grid, n, level)
    local orthogonal = true
    local total = n * n
    local geo = geometry(n, orthogonal)
    local dist, adj, nbrs = geo.dist, geo.adj, geo.nbrs

    local val, pos = {}, {}
    for r = 1, n do
        for c = 1, n do
            local i = (r - 1) * n + c
            local v = grid[r][c] or 0
            val[i] = v
            if v ~= 0 then
                if pos[v] then return false, val, nil end
                pos[v] = i
            end
        end
    end
    local placed = 0
    for k = 1, total do if pos[k] then placed = placed + 1 end end

    local stats = { single = 0, neighbour = 0, segment = 0 }
    local banned = {}          -- banned[k][cell] = true: struck out for good
    for k = 1, total do banned[k] = {} end

    local cand, ccount = {}, {} -- cand[k]: cell -> true; ccount[k]: its size

    -- Rule 1: reach from the nearest placed numbers on both sides.
    local function computeReach()
        local lo = {}
        local last = nil
        for k = 1, total do
            if pos[k] then last = k else lo[k] = last end
        end
        local nxt = nil
        for k = total, 1, -1 do
            if pos[k] then
                nxt = k
            else
                local l, h = lo[k], nxt
                local pl, ph = l and pos[l], h and pos[h]
                local dl, dh = pl and dist[pl], ph and dist[ph]
                local set, cnt, bk = {}, 0, banned[k]
                for i = 1, total do
                    if val[i] == 0 and not bk[i] then
                        local ok = true
                        if dl then
                            local d, s = dl[i], k - l
                            if d > s or (orthogonal and (s - d) % 2 == 1) then ok = false end
                        end
                        if ok and dh then
                            local d, s = dh[i], h - k
                            if d > s or (orthogonal and (s - d) % 2 == 1) then ok = false end
                        end
                        if ok then set[i] = true; cnt = cnt + 1 end
                    end
                end
                cand[k], ccount[k] = set, cnt
            end
        end
    end

    -- Place every single at once. Returns the number placed, or false on a
    -- contradiction (only possible on a grid with no solution).
    local function placeSingles()
        local moves = {}
        local seen_by = {}       -- cell -> number reaching it, or false if several
        for k = 1, total do
            if not pos[k] then
                local cnt = ccount[k]
                if cnt == 0 then return false end
                for i in pairs(cand[k]) do
                    if cnt == 1 then moves[#moves + 1] = { k, i } end
                    local s = seen_by[i]
                    if s == nil then seen_by[i] = k elseif s ~= k then seen_by[i] = false end
                end
            end
        end
        for i = 1, total do
            if val[i] == 0 then
                local s = seen_by[i]
                if s == nil then return false end
                if s then moves[#moves + 1] = { s, i } end
            end
        end
        local count = 0
        for _, m in ipairs(moves) do
            local k, i = m[1], m[2]
            if pos[k] or val[i] ~= 0 then
                if pos[k] ~= i then return false end
            else
                pos[k], val[i] = i, k
                count = count + 1
            end
        end
        placed = placed + count
        return count
    end

    local function strike(k, i)
        cand[k][i] = nil
        ccount[k] = ccount[k] - 1
        banned[k][i] = true
    end

    -- Rule 2: k on x needs k - 1 and k + 1 on two different neighbours of x.
    local function neighbourPass()
        local changed_any = false
        local changed = true
        while changed do
            changed = false
            for k = 1, total do
                if not pos[k] then
                    for x in pairs(cand[k]) do
                        local ok = true
                        local only_prev, only_next   -- the single neighbour support, if one
                        for side = -1, 1, 2 do
                            local m = k + side
                            if m >= 1 and m <= total then
                                local pm = pos[m]
                                if pm then
                                    if not adj[x][pm] then ok = false end
                                else
                                    local found, one = 0, nil
                                    local cm = cand[m]
                                    for _, y in ipairs(nbrs[x]) do
                                        if cm[y] then
                                            found = found + 1
                                            one = y
                                            if found > 1 then break end
                                        end
                                    end
                                    if found == 0 then
                                        ok = false
                                    elseif found == 1 then
                                        if side < 0 then only_prev = one else only_next = one end
                                    end
                                end
                                if not ok then break end
                            end
                        end
                        if ok and only_prev and only_prev == only_next then ok = false end
                        if not ok then
                            strike(k, x)
                            changed, changed_any = true, true
                        end
                    end
                end
            end
        end
        return changed_any
    end

    -- Rule 3: trace the routes of every short segment between placed numbers.
    local function segmentPass()
        local changed_any = false
        local a = 1
        while a < total do
            if not pos[a] then a = a + 1 else
                local b = a + 1
                while b <= total and not pos[b] do b = b + 1 end
                if b > total then break end
                local missing = b - a - 1
                if missing > 0 and missing <= SEGMENT_MAX then
                    local support = {}
                    for k = a + 1, b - 1 do support[k] = {} end
                    local used, path = {}, {}
                    local routes = 0
                    local through = nil      -- cells used by every route so far
                    local target = pos[b]
                    local function walk(k, prev)
                        if k == b then
                            if adj[prev][target] then
                                routes = routes + 1
                                local cells = {}
                                for j = a + 1, b - 1 do
                                    support[j][path[j]] = true
                                    cells[path[j]] = true
                                end
                                if through then
                                    for cell in pairs(through) do
                                        if not cells[cell] then through[cell] = nil end
                                    end
                                else
                                    through = cells
                                end
                            end
                            return
                        end
                        for _, x in ipairs(nbrs[prev]) do
                            if cand[k][x] and not used[x] then
                                used[x] = true
                                path[k] = x
                                walk(k + 1, x)
                                used[x] = nil
                            end
                        end
                    end
                    walk(a + 1, pos[a])
                    if routes == 0 then return nil end   -- contradiction
                    for k = a + 1, b - 1 do
                        for x in pairs(cand[k]) do
                            if not support[k][x] then
                                strike(k, x)
                                changed_any = true
                            end
                        end
                    end
                    for cell in pairs(through) do
                        for k = 1, total do
                            if (k <= a or k >= b) and not pos[k] and cand[k][cell] then
                                strike(k, cell)
                                changed_any = true
                            end
                        end
                    end
                end
                a = b
            end
        end
        return changed_any
    end

    while placed < total do
        computeReach()
        local got = placeSingles()
        if got == false then return false, val, stats end
        if got > 0 then
            stats.single = stats.single + got
        else
            local tier = nil
            if level >= 2 then
                -- Neighbour strikes first; segments only when they are not enough.
                while true do
                    local changed = neighbourPass()
                    if changed then
                        got = placeSingles()
                        if got == false then return false, val, stats end
                        if got > 0 then tier = "neighbour"; break end
                    end
                    if level < 3 then break end
                    local seg = segmentPass()
                    if seg == nil then return false, val, stats end
                    if not seg then break end
                    got = placeSingles()
                    if got == false then return false, val, stats end
                    if got > 0 then tier = "segment"; break end
                end
            end
            if not tier then return false, val, stats end
            stats[tier] = stats[tier] + got
        end
    end
    return true, val, stats
end

return {
    solve       = solve,
    SEGMENT_MAX = SEGMENT_MAX,
}
