local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
package.path = DIR .. "?.lua;" .. package.path

local Game = dofile(DIR .. "game.lua")

local function lcg(seed)
    local s = seed
    return function(n)
        s = (s * 1103515245 + 12345) % 2147483648
        return (s % n) + 1
    end
end

local function fakeContent()
    local c = { riddles = {}, names = {}, clock = {}, pyramid = {}, words = {} }
    for i = 1, 20 do
        c.riddles[i] = { t = "riddle" .. i, a = "answer" .. i,
                         w = { "r" .. i .. "a", "r" .. i .. "b", "r" .. i .. "c", "r" .. i .. "d", "r" .. i .. "e" } }
        c.names[i] = { t = "theme" .. i, n = { "n" .. i .. "a", "n" .. i .. "b", "n" .. i .. "c", "n" .. i .. "d" } }
        c.clock[i] = { t = "clock" .. i, w = {} }
        for k = 1, 8 do c.clock[i].w[k] = "c" .. i .. "w" .. k end
        c.pyramid[i] = {}
        for k = 1, 6 do c.pyramid[i][k] = "p" .. i .. "e" .. k end
    end
    for i = 1, 60 do c.words[i] = "word" .. i end
    return function(kind) return c[kind] end
end

local function newGame(opts)
    opts = opts or {}
    return Game.new{ players = { "Alice", "Bob", "Carol", "Dave" }, content = fakeContent(),
                     rng = lcg(opts.seed or 1), round2 = opts.round2, name_bricks = opts.name_bricks }
end

-- Plays one riddle: `script` is a string of f (found), w (wrong), x (forbidden).
local function playRiddle(g, opt, script, solved)
    assert.are.equal("pick", g.phase)
    assert.is_true(g:pick(opt))
    assert.are.equal("handover", g.phase)
    g:startTurn()
    for c in script:gmatch(".") do
        if c == "f" then g:found() elseif c == "w" then g:wrong() else g:forbidden() end
    end
    assert.are.equal("answer", g.phase)
    g:answer(solved)
    assert.are.equal("result", g.phase)
    local last = g.last
    g:continue()
    return last
end

describe("wordpyramid stages", function()
    it("orders the stages from the round-2 setting", function()
        assert.are.same({ "riddles", "pingpong", "clock", "names", "final" }, Game.stagesFor("both"))
        assert.are.same({ "riddles", "pingpong", "names", "final" }, Game.stagesFor("pingpong"))
        assert.are.same({ "riddles", "clock", "names", "final" }, Game.stagesFor("clock"))
    end)

    it("starts on the riddles intro, then offers 6 distinct riddles", function()
        local g = newGame()
        g:startGame()
        assert.are.equal("intro", g.phase)
        assert.are.equal("riddles", g:stage())
        g:beginStage()
        assert.are.equal("pick", g.phase)
        assert.are.equal(6, #g.st.options)
        local seen = {}
        for _, r in ipairs(g.st.options) do
            assert.is_nil(seen[r.t]); seen[r.t] = true
        end
        assert.are.equal(1, g:picker())
    end)

    it("swaps the partners' roles between a team's two turns", function()
        local g = newGame()
        g:startGame(); g:beginStage()
        g:pick(1)
        local a1, b1 = g.play.giver, g.play.guesser
        g:startTurn()
        for _ = 1, 5 do g:found() end
        g:answer(true); g:continue()
        g:pick(2); g:startTurn(); for _ = 1, 5 do g:found() end; g:answer(true); g:continue()
        g:pick(3)
        assert.are.equal(a1, g.play.guesser)
        assert.are.equal(b1, g.play.giver)
    end)
end)

describe("wordpyramid riddles", function()
    it("scores words, the answer and the unused bricks when all 5 are found", function()
        local g = newGame()
        g:startGame(); g:beginStage()
        local last = playRiddle(g, 1, "wfffwff", true)     -- 7 bricks used, 6 left
        assert.are.equal(5, last.words)
        assert.are.equal(6, last.bonus)
        assert.are.equal(5 + 1 + 6, last.points)
        assert.are.equal(12, g.score[1])
        assert.are.equal(2, g:picker())
    end)

    it("cancels the bonus when a word is missed", function()
        local g = newGame()
        g:startGame(); g:beginStage()
        local last = playRiddle(g, 1, "fxfff", false)
        assert.are.equal(4, last.words)
        assert.are.equal(0, last.bonus)
        assert.are.equal(4, last.points)
    end)

    it("ends the words when the 13 bricks are spent", function()
        local g = newGame()
        g:startGame(); g:beginStage()
        g:pick(1); g:startTurn()
        g:found()
        for _ = 1, 11 do g:wrong() end
        assert.are.equal("turn", g.phase)
        g:wrong()
        assert.are.equal("answer", g.phase)
        assert.are.equal(0, g.play.bricks)
        assert.are.equal(1, g:riddleFoundCount())
        g:answer(true)
        assert.are.equal(2, g.score[1])
    end)

    it("undoes the last tap, also out of the answer step", function()
        local g = newGame()
        g:startGame(); g:beginStage()
        g:pick(1); g:startTurn()
        for _ = 1, 4 do g:found() end
        g:wrong()
        assert.are.equal(8, g.play.bricks)
        g:undo()
        assert.are.equal(9, g.play.bricks)
        g:found()
        assert.are.equal("answer", g.phase)
        assert.is_true(g:canUndo())
        g:undo()
        assert.are.equal("turn", g.phase)
        assert.are.equal(5, g.play.pos)
    end)

    it("lets each team pick 2 riddles, never a taken one", function()
        local g = newGame()
        g:startGame(); g:beginStage()
        playRiddle(g, 1, "fffff", true)
        assert.is_false(g:canPick(1))
        assert.is_false(g:pick(1))
        playRiddle(g, 2, "fffff", true)
        playRiddle(g, 3, "fffff", true)
        playRiddle(g, 4, "fffff", true)
        assert.are.equal("intro", g.phase)
        assert.are.equal("pingpong", g:stage())
        assert.are.equal(2 * 14, g.score[1])
        assert.are.equal(2 * 14, g.score[2])
    end)
end)

local function skipRiddles(g, a_bricks)
    g:startGame(); g:beginStage()
    playRiddle(g, 1, a_bricks or "fffff", true)
    playRiddle(g, 2, "fffff", false)
    playRiddle(g, 3, "fffff", false)
    playRiddle(g, 4, "fffff", false)
end

describe("wordpyramid ping-pong", function()
    it("alternates the teams clue by clue and scores the finder", function()
        local g = newGame()
        skipRiddles(g)            -- A 14+12, B 12+12 → B trails and starts
        assert.are.equal("pingpong", g:stage())
        g:beginStage()
        assert.are.equal("handover", g.phase)
        g:startTurn()
        assert.are.equal(2, g:activeTeam())
        g:wrong()
        assert.are.equal(1, g:activeTeam())
        local before = g.score[1]
        g:found()
        assert.are.equal(before + 1, g.score[1])
        assert.are.equal(2, g.play.pos)
        assert.are.equal(1, g:activeTeam())    -- word 2 starts with the other team
        assert.are.equal(11, g.play.bricks)
    end)

    it("loses a word after 5 bricks and ends at 13 bricks", function()
        local g = newGame()
        skipRiddles(g)
        g:beginStage(); g:startTurn()
        for _ = 1, 5 do g:wrong() end
        assert.are.equal(2, g.play.pos)
        assert.are.equal(8, g.play.bricks)
        for _ = 1, 5 do g:wrong() end
        assert.are.equal(3, g.play.pos)
        for _ = 1, 2 do g:wrong() end
        assert.are.equal("turn", g.phase)
        g:wrong()
        assert.are.equal("result", g.phase)
        assert.are.equal(0, g.last.found[1] + g.last.found[2])
        g:continue()
        assert.are.equal("clock", g:stage())
    end)

    it("ends after 5 words", function()
        local g = newGame()
        skipRiddles(g)
        g:beginStage(); g:startTurn()
        for _ = 1, 5 do g:found() end
        assert.are.equal("result", g.phase)
        assert.are.equal(5, g.last.found[1] + g.last.found[2])
    end)
end)

describe("wordpyramid against the clock", function()
    it("offers 4 themes, 7 words each, found / pass / forbidden", function()
        local g = newGame{ round2 = "clock" }
        skipRiddles(g)
        assert.are.equal("clock", g:stage())
        g:beginStage()
        assert.are.equal(4, #g.st.options)
        assert.are.equal(2, g:picker())   -- the team behind picks first
    end)

    it("scores the words found when time runs out", function()
        local g = newGame{ round2 = "clock" }
        skipRiddles(g)
        g:beginStage()
        g:pick(1)
        g:startTurn()
        assert.are.equal(7, #g.play.queue)
        local first = g.play.queue[1]
        g:pass()
        assert.are.equal(first, g.play.queue[7])
        g:found(); g:found(); g:forbidden()
        assert.are.equal(4, #g.play.queue)
        local t = g.play.team
        local before = g.score[t]
        g:endClock()
        assert.are.equal("result", g.phase)
        assert.are.equal(before + 2, g.score[t])
        assert.are.equal(7, #g.last.results)
    end)
end)

-- Plays the whole game up to the proper names.
local function toNames(g, a_script)
    skipRiddles(g, a_script)
    g:beginStage(); g:startTurn()
    for _ = 1, 5 do g:found() end  -- ping-pong
    g:continue()
    g:beginStage()
    for _ = 1, 4 do
        g:pick(g.st.taken[1] and (g.st.taken[2] and (g.st.taken[3] and 4 or 3) or 2) or 1)
        g:startTurn(); g:endClock(); g:continue()
    end
    assert.are.equal("names", g:stage())
    assert.are.equal("intro", g.phase)
end

describe("wordpyramid proper names", function()
    it("lets the opponent take a name over with a lower bid", function()
        local g = newGame{ name_bricks = 4 }
        toNames(g)
        g:beginStage()
        local owner = g:picker()
        g:pick(1)
        assert.are.equal("bid", g.phase)
        assert.are.equal(3 - owner, g:bidder())
        assert.is_false(g:placeBid(4))      -- strictly lower only
        assert.is_true(g:placeBid(2))
        assert.are.equal(3 - owner, g.play.team)
        assert.are.equal(2, g.play.bricks)
        g:startTurn()
        local before = g.score[3 - owner]
        g:wrong(); g:found()
        assert.are.equal(before + 1, g.score[3 - owner])
        assert.are.equal("bid", g.phase)
        assert.are.equal(2, g.st.theme.idx)
    end)

    it("gives the name to the other team on a fail, 2 points for a failed 1-brick bid", function()
        local g = newGame{ name_bricks = 4 }
        toNames(g)
        g:beginStage()
        local owner = g:picker()
        g:pick(1)
        g:placeBid(nil)
        assert.are.equal(owner, g.play.team)
        assert.are.equal(4, g.play.bricks)
        g:startTurn()
        local b = g.score[3 - owner]
        for _ = 1, 4 do g:wrong() end
        assert.are.equal(b + 1, g.score[3 - owner])
        g:placeBid(1)
        g:startTurn()
        local o = g.score[owner]
        g:wrong()
        assert.are.equal(o + 2, g.score[owner])
        g:placeBid(nil); g:startTurn(); g:forbidden()
        assert.are.equal(o + 2, g.score[owner])
        g:placeBid(nil); g:startTurn(); g:found()
        assert.are.equal("result", g.phase)
        assert.is_true(g.last.theme_done)
        g:continue()
        assert.are.equal("pick", g.phase)
        assert.are.equal(3 - owner, g:picker())
    end)

    it("sends the leader to the final, or plays a sudden-death name on a tie", function()
        local g = newGame()
        toNames(g)
        g:beginStage()
        for _ = 1, 2 do
            g:pick(g.st.taken[1] and 2 or 1)
            for _ = 1, 4 do g:placeBid(nil); g:startTurn(); g:found() end
            g:continue()
        end
        if g.score[1] ~= g.score[2] then
            assert.are.equal("final_handover", g.phase)
            assert.are.equal(g:leader(), g.final.team)
        end
        -- Force a tie and replay the end of the stage.
        local g2 = newGame()
        toNames(g2)
        g2:beginStage()
        g2.score = { 10, 10 }
        for _ = 1, 2 do
            g2:pick(g2.st.taken[1] and 2 or 1)
            for _ = 1, 4 do g2:placeBid(nil); g2:startTurn(); g2:forbidden() end
            g2:continue()
        end
        assert.are.equal(14, g2.score[1]); assert.are.equal(14, g2.score[2])
        assert.are.equal("handover", g2.phase)
        assert.is_true(g2:isSudden())
        g2:startTurn()
        assert.are.equal(1, g2:activeTeam())
        g2:wrong()
        assert.are.equal(2, g2:activeTeam())
        local n = g2:currentWord()
        g2:suddenNewName()
        assert.are_not.equal(n, g2:currentWord())
        g2:forbidden()                 -- team 2's clue was forbidden: team 1 wins
        assert.are.equal("final_handover", g2.phase)
        assert.are.equal(1, g2.final.team)
        assert.are.equal("final", g2:stage())
    end)
end)

local function toFinal(g)
    toNames(g, "fffff")
    g:beginStage()
    for _ = 1, 2 do
        g:pick(g.st.taken[1] and 2 or 1)
        for _ = 1, 4 do g:placeBid(nil); g:startTurn(); g:found() end
        g:continue()
    end
    if g.phase == "handover" then g:startTurn(); g:found() end
    assert.are.equal("final_handover", g.phase)
end

describe("wordpyramid final", function()
    it("wins only with all 6 expressions", function()
        local g = newGame()
        toFinal(g)
        local giver = g.final.giver
        g:swapRoles()
        assert.are_not.equal(giver, g.final.giver)
        g:finalStart()
        assert.are.equal(6, #g.final.exprs)
        local first = g:finalCurrent()
        g:finalPass()
        assert.are.equal(first, g.final.queue[6])
        for _ = 1, 5 do g:finalFound() end
        assert.are.equal("final_turn", g.phase)
        g:finalUndo()
        assert.are.equal(4, g:finalFoundCount())
        g:finalFound(); g:finalFound()
        assert.are.equal("game_over", g.phase)
        assert.are.equal("won", g.final.outcome.kind)
    end)

    it("loses everything on a forbidden clue or when time runs out", function()
        local g = newGame()
        toFinal(g)
        g:finalStart(); g:finalFound(); g:finalForbidden()
        assert.are.equal("forbidden", g.final.outcome.kind)
        assert.are.equal(1, g.final.outcome.found)
        g:restartFinal()
        assert.are.equal("final_handover", g.phase)
        g:finalStart(); g:finalTimeUp()
        assert.are.equal("time", g.final.outcome.kind)
    end)
end)

describe("wordpyramid save / restore", function()
    it("never restores on a visible word, keeps untimed progress", function()
        local g = newGame()
        g:startGame(); g:beginStage()
        g:pick(1); g:startTurn(); g:found(); g:wrong()
        local s = g:serialize()
        assert.are.equal("handover", s.phase)
        local g2 = newGame()
        assert.is_true(g2:load(s))
        assert.are.equal("handover", g2.phase)
        g2:startTurn()
        assert.are.equal(2, g2.play.pos)
        assert.are.equal(11, g2.play.bricks)
        -- the riddle's answer step is not restored on screen either
        for _ = 1, 4 do g2:found() end
        assert.are.equal("answer", g2.phase)
        local g3 = newGame()
        g3:load(g2:serialize())
        assert.are.equal("handover", g3.phase)
        g3:startTurn()
        assert.are.equal("answer", g3.phase)
    end)

    it("restores a final in progress on its hand-over and a finished game as over", function()
        local g = newGame()
        toFinal(g)
        g:finalStart(); g:finalFound()
        local s = g:serialize()
        assert.are.equal("final_handover", s.phase)
        assert.is_nil(s.final.exprs)
        local g2 = newGame()
        assert.is_true(g2:load(s))
        g2:finalStart()
        assert.are.equal(0, g2:finalFoundCount())
        g2:finalTimeUp()
        local g3 = newGame()
        assert.is_true(g3:load(g2:serialize()))
        assert.is_true(g3:isGameOver())
    end)

    it("rejects garbage", function()
        local g = newGame()
        assert.is_false(g:load(nil))
        assert.is_false(g:load({ version = 1, phase = "turn", players = {}, score = {}, stages = {} }))
        assert.are.equal("setup", g.phase)
    end)
end)

describe("wordpyramid prizes", function()
    it("formats euros and points per language", function()
        assert.are.equal("10\u{00A0}000\u{00A0}€", Game.formatPrize(10000, "euros", "fr"))
        assert.are.equal("€10,000", Game.formatPrize(10000, "euros", "en"))
        assert.are.equal("100 pts", Game.formatPrize(100, "points", "en"))
    end)
end)

-- ---------------------------------------------------------------------------
-- The real content files
-- ---------------------------------------------------------------------------

local function load(lang, kind) return dofile(DIR .. "content/" .. lang .. "/" .. kind .. ".lua") end

-- Lower-case, accents stripped (enough for duplicate / containment checks).
local ACCENTS = { ["à"] = "a", ["â"] = "a", ["ä"] = "a", ["á"] = "a", ["ç"] = "c", ["é"] = "e", ["è"] = "e",
    ["ê"] = "e", ["ë"] = "e", ["î"] = "i", ["ï"] = "i", ["í"] = "i", ["ô"] = "o", ["ö"] = "o", ["ó"] = "o",
    ["ù"] = "u", ["û"] = "u", ["ü"] = "u", ["ú"] = "u", ["ÿ"] = "y", ["ñ"] = "n", ["œ"] = "oe", ["æ"] = "ae",
    ["À"] = "a", ["Â"] = "a", ["É"] = "e", ["È"] = "e", ["Ê"] = "e", ["Î"] = "i", ["Ô"] = "o", ["Œ"] = "oe",
    ["Ç"] = "c", ["Ü"] = "u", ["Ö"] = "o" }
local function norm(s)
    s = s:gsub("[%z\1-\127\194-\244][\128-\191]*", function(c) return ACCENTS[c] or c end)
    return (s:lower():gsub("[%p%s]+", " "):gsub("^ ", ""):gsub(" $", ""))
end

local function ulen(s) return select(2, s:gsub("[^\128-\191]", "")) end

-- Whole words / names (the Amazon river or François Ier are fine).
local EXCLUDED = { "hitler", "staline", "stalin", "pol pot", "ben laden", "bin laden", "mussolini",
    "pinochet", "idi amin", "saddam", "goebbels", "himmler", "landru", "eventreur", "ripper",
    "petiot", "khomeini", "ceausescu", "kim jong", "franco",
    -- brands
    "coca", "nutella", "lego", "google", "iphone", "kleenex", "frigidaire", "ferrari", "disney",
    "mcdonald", "monopoly", "nike", "playstation", "barbie", "tupperware", "post-it", "velcro",
    "mobylette", "facebook", "twitter", "pokemon", "mickey", "netflix", "renault",
    "peugeot", "michelin", "nintendo", "microsoft", "adidas", "pepsi", "starbucks", "ikea" }

local function checkText(s, where)
    local n = " " .. norm(s) .. " "
    for _, bad in ipairs(EXCLUDED) do
        local b = norm(bad)
        if n:find(" " .. b .. " ", 1, true) then error(where .. ": excluded '" .. bad .. "' in " .. s) end
    end
end

for _, lang in ipairs({ "fr", "en" }) do
    describe("wordpyramid content (" .. lang .. ")", function()
        it("has >= 150 riddles of 5 words, answer not among its words", function()
            local r = load(lang, "riddles")
            assert.is_true(#r >= 150, #r .. " riddles")
            local answers = {}
            for i, it in ipairs(r) do
                local where = lang .. " riddle " .. i
                assert.is_string(it.t, where); assert.is_string(it.a, where)
                assert.are.equal(5, #it.w, where)
                assert.is_true(ulen(it.t) <= 40, where .. " title too long")
                local a = norm(it.a)
                assert.is_nil(answers[a], where .. " duplicate answer " .. it.a)
                answers[a] = true
                local seen = {}
                for _, w in ipairs(it.w) do
                    local nw = norm(w)
                    assert.is_nil(seen[nw], where .. " duplicate word " .. w); seen[nw] = true
                    assert.are_not.equal(a, nw, where .. " answer among words")
                    assert.is_nil((" " .. nw .. " "):find(" " .. a .. " ", 1, true), where .. ": " .. w .. " contains the answer")
                    assert.is_true(ulen(w) <= 22, where .. " word too long " .. w)
                    checkText(w, where)
                end
                checkText(it.t, where); checkText(it.a, where)
            end
        end)

        it("has >= 80 proper-name themes of 4 unique names", function()
            local t = load(lang, "names")
            assert.is_true(#t >= 80, #t .. " themes")
            local names, themes = {}, {}
            for i, th in ipairs(t) do
                local where = lang .. " names theme " .. i
                assert.is_nil(themes[norm(th.t)], where .. " duplicate theme"); themes[norm(th.t)] = true
                assert.are.equal(4, #th.n, where)
                for _, n in ipairs(th.n) do
                    assert.is_nil(names[norm(n)], where .. " duplicate name " .. n); names[norm(n)] = true
                    assert.is_true(ulen(n) <= 26, where .. " name too long " .. n)
                    checkText(n, where)
                end
                checkText(th.t, where)
            end
        end)

        it("has >= 80 against-the-clock themes of 7+ words", function()
            local t = load(lang, "clock")
            assert.is_true(#t >= 80, #t .. " themes")
            local themes = {}
            for i, th in ipairs(t) do
                local where = lang .. " clock theme " .. i
                assert.is_nil(themes[norm(th.t)], where .. " duplicate theme"); themes[norm(th.t)] = true
                assert.is_true(#th.w >= Game.CLOCK_WORDS, where)
                local seen = {}
                for _, w in ipairs(th.w) do
                    assert.is_nil(seen[norm(w)], where .. " duplicate word " .. w); seen[norm(w)] = true
                    checkText(w, where)
                end
                checkText(th.t, where)
            end
        end)

        it("has >= 150 Great-Pyramid sets of 6 unique expressions", function()
            local t = load(lang, "pyramid")
            assert.is_true(#t >= 150, #t .. " sets")
            local seen = {}
            for i, set in ipairs(t) do
                local where = lang .. " pyramid set " .. i
                assert.are.equal(6, #set, where)
                for _, e in ipairs(set) do
                    assert.is_nil(seen[norm(e)], where .. " duplicate " .. e); seen[norm(e)] = true
                    assert.is_true(ulen(e) <= 34, where .. " too long " .. e)
                    checkText(e, where)
                end
            end
        end)

        it("has >= 600 unique ping-pong words", function()
            local t = load(lang, "words")
            assert.is_true(#t >= 600, #t .. " words")
            local seen = {}
            for _, w in ipairs(t) do
                assert.is_nil(seen[norm(w)], lang .. " duplicate word " .. w); seen[norm(w)] = true
                checkText(w, lang .. " words")
            end
        end)
    end)
end
