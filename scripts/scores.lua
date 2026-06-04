-- scripts/scores.lua
-- Local high-score table for Find5. The model only — the scoreboard
-- screen lives in highscores.lua.
--
-- Persisted in find5.dat under the "highscores" option key as an array of
-- { name = <string>, score = <int> }, kept high-to-low and capped at
-- MAX_ENTRIES. Storage is the engine's optSet / optGet / optSave (script.h),
-- the only sanctioned write path since `io` is sandboxed; the nested table
-- round-trips through the options serializer natively.

local M = {}

M.MAX_ENTRIES = 10            -- rows kept (and shown on the scoreboard)
M.MAX_NAME    = 16            -- name length cap; matches the entry LineEdit

local OPT_KEY = "highscores"

-- Read the stored list as a fresh, validated, sorted array. Defensive about
-- corrupt or legacy data: anything that isn't a { name, score } pair is
-- dropped, so the rest of the game can trust the shape and ordering.
function M.list()
    local raw = optGet(OPT_KEY, {})
    local out = {}
    if type(raw) == "table" then
        for _, e in ipairs(raw) do
            if type(e) == "table" and type(e.score) == "number" then
                out[#out + 1] = {
                    name  = type(e.name) == "string" and e.name or "",
                    score = math.floor(e.score),
                }
            end
        end
    end
    -- Stable descending sort (insertion sort; MAX_ENTRIES is tiny). Stability
    -- matters: equal scores keep their stored order, so a tie keeps the
    -- incumbent above and add()'s returned rank matches the displayed row.
    -- table.sort would do neither (Lua 5.1's sort is unstable).
    for i = 2, #out do
        local v, j = out[i], i - 1
        while j >= 1 and out[j].score < v.score do
            out[j + 1] = out[j]
            j = j - 1
        end
        out[j + 1] = v
    end
    return out
end

-- Would `score` earn a place on the board? True when the board isn't full,
-- or the score strictly beats the current lowest entry. A non-positive
-- score never qualifies (no point logging a zero run).
function M.qualifies(score)
    if type(score) ~= "number" or score <= 0 then return false end
    local list = M.list()
    if #list < M.MAX_ENTRIES then return true end
    return score > list[#list].score
end

-- Insert (name, score), keep the board ordered, cap it, persist. Returns the
-- 1-based rank the new entry landed at, or nil if it didn't qualify.
--
-- Ties keep the incumbent above: the new entry is inserted at the first slot
-- whose score it strictly beats, so an equal score sorts below one already on
-- the board. Combined with qualifies()'s strict ">", you must beat a score to
-- displace it.
function M.add(name, score)
    if not M.qualifies(score) then return nil end
    name  = tostring(name or ""):sub(1, M.MAX_NAME)
    score = math.floor(score)

    local list = M.list()
    local pos  = #list + 1
    for i, e in ipairs(list) do
        if score > e.score then pos = i; break end
    end
    table.insert(list, pos, { name = name, score = score })
    while #list > M.MAX_ENTRIES do table.remove(list) end

    optSet(OPT_KEY, list)
    optSave()

    return pos <= M.MAX_ENTRIES and pos or nil
end

return M
