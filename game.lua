-- Word Pyramid game logic, after the classic French TV word game format.
-- Pure Lua, no UI: the screen drives the timers and calls these methods.
--
-- Four players, two teams of two: players 1-2 are team 1 (A), 3-4 team 2 (B).
-- In each team one player gives ONE-word clues, the partner guesses. Every
-- clue costs a brick. The stages, in order:
--   * riddles  — 6 riddle titles, each team picks 2 in turn. A riddle = 5
--                words to find with 13 bricks (1 point each), then the hidden
--                answer (+1); all 5 found: +1 per unused brick.
--   * pingpong — 5 words played back and forth between the teams, 13 bricks
--                in all, 5 at most per word; the team that finds it scores.
--   * clock    — 4 themes, each team picks 2 in turn: 30 s to find up to 7
--                words linked to the theme, 1 point each.
--   * names    — 6 themes, each team plays one: 4 famous names, a brick limit
--                per name (3/4/5). Before each name the opponent may bid
--                fewer bricks and take it over. Fail: the other team scores
--                (2 points when a 1-brick bid fails). The leader plays the
--                final; a tie is settled by a sudden-death name.
--   * final    — the Great Pyramid: 6 expressions in 1 minute, all or nothing.
-- The round-2 setting keeps pingpong, clock, or both (as in 2002: both,
-- ping-pong first, against the clock before the proper names).

local Game = {}
Game.__index = Game

Game.RIDDLE_OPTIONS  = 6
Game.RIDDLE_WORDS    = 5
Game.RIDDLE_BRICKS   = 13
Game.PP_WORDS        = 5
Game.PP_BRICKS       = 13
Game.PP_MAX_PER_WORD = 5
Game.CLOCK_OPTIONS   = 4
Game.CLOCK_WORDS     = 7
Game.CLOCK_TIME      = 30
Game.NAME_OPTIONS    = 6
Game.NAMES_PER_THEME = 4
Game.FINAL_COUNT     = 6
Game.FINAL_TIME      = 60
Game.PRIZE           = { euros = 10000, points = 100 }

-- Picking order of the riddles: A, B, A, B (later stages: the team behind first).
Game.PICK_ORDER = { 1, 2, 1, 2 }

local function copy(t)
    if type(t) ~= "table" then return t end
    local out = {}
    for k, v in pairs(t) do out[k] = copy(v) end
    return out
end
Game.copy = copy

local function shuffle(t, rng)
    for i = #t, 2, -1 do
        local j = rng(i)
        t[i], t[j] = t[j], t[i]
    end
    return t
end

-- "10 000 €" / "€10,000", "100 pts".
function Game.formatPrize(n, unit, lang)
    local s = tostring(math.floor(n))
    local sep = lang == "fr" and "\u{00A0}" or ","
    local out = s:reverse():gsub("(%d%d%d)", "%1" .. sep:reverse()):reverse()
    if out:sub(1, #sep) == sep then out = out:sub(#sep + 1) end
    if unit == "euros" then
        return lang == "fr" and (out .. "\u{00A0}€") or ("€" .. out)
    end
    return out .. (lang == "fr" and "\u{00A0}pts" or " pts")
end

function Game.stagesFor(round2)
    local s = { "riddles" }
    if round2 ~= "clock" then s[#s + 1] = "pingpong" end
    if round2 ~= "pingpong" then s[#s + 1] = "clock" end
    s[#s + 1] = "names"
    s[#s + 1] = "final"
    return s
end

-- opts: players (4 names), content (function(kind) -> list, kinds riddles,
-- names, clock, pyramid, words), recent (set of keys to avoid), rng,
-- round2 ("both" | "pingpong" | "clock"), name_bricks (3..5), unit.
function Game.new(opts)
    local self = setmetatable({}, Game)
    self.rng = opts.rng or math.random
    self.content = opts.content or function() return {} end
    self.recent = opts.recent or {}
    self.round2 = opts.round2 or "both"
    self.name_bricks = opts.name_bricks or 4
    self.players = {}
    for i = 1, 4 do self.players[i] = (opts.players or {})[i] or ("Player " .. i) end
    self:newGame()
    return self
end

function Game:newGame()
    self.phase = "setup"
    self.stages = Game.stagesFor(self.round2)
    self.si = 0
    self.score = { 0, 0 }
    self.stage_scores = {}         -- stage_scores[stage_id] = { a, b }
    self.used, self.used_list = {}, {}
    self.st, self.play, self.last = nil, nil, nil
    self.history = {}
    self.final = nil
end

function Game:stage()
    return self.stages[self.si]
end

function Game:stageNumber(id)
    for i, s in ipairs(self.stages) do if s == id then return i end end
end

function Game:other(t) return 3 - t end

function Game:teamPlayers(t)
    return t == 1 and 1 or 3, t == 1 and 2 or 4
end

-- Giver and guesser of team t on its k-th turn of the current stage: the
-- partners swap roles every turn, and every stage starts the other way round.
function Game:roles(t, k)
    local a, b = self:teamPlayers(t)
    if ((k or 1) + self.si) % 2 == 1 then a, b = b, a end
    return a, b
end

function Game:addScore(t, n)
    self.score[t] = self.score[t] + n
    local id = self:stage()
    if id then
        self.stage_scores[id] = self.stage_scores[id] or { 0, 0 }
        self.stage_scores[id][t] = self.stage_scores[id][t] + n
    end
end

function Game:leader()
    if self.score[1] == self.score[2] then return nil end
    return self.score[1] > self.score[2] and 1 or 2
end

-- The team behind picks/starts first; team A on a tie.
function Game:trailing()
    return self.score[2] < self.score[1] and 2 or 1
end

-- ---------------------------------------------------------------------------
-- Content
-- ---------------------------------------------------------------------------

local function keyOf(kind, item)
    if type(item) == "string" then return kind .. ":" .. item end
    return kind .. ":" .. tostring(item.t or item.a or item[1])
end
Game.keyOf = keyOf

-- n distinct items of a kind, never twice in a game; items seen in recent
-- games only once the fresh ones run out.
function Game:draw(kind, n, list)
    local fresh, stale = {}, {}
    for _, it in ipairs(list or self.content(kind) or {}) do
        local k = keyOf(kind, it)
        if not self.used[k] then
            if self.recent[k] then stale[#stale + 1] = it else fresh[#fresh + 1] = it end
        end
    end
    shuffle(fresh, self.rng)
    shuffle(stale, self.rng)
    local out = {}
    for _, l in ipairs({ fresh, stale }) do
        for _, it in ipairs(l) do
            if #out >= n then break end
            out[#out + 1] = it
        end
    end
    for _, it in ipairs(out) do self:markUsed(kind, it) end
    return out
end

function Game:markUsed(kind, it)
    local k = keyOf(kind, it)
    if not self.used[k] then
        self.used[k] = true
        self.used_list[#self.used_list + 1] = k
    end
end

-- ---------------------------------------------------------------------------
-- Flow between stages
-- ---------------------------------------------------------------------------

function Game:startGame()
    local players = self.players
    self:newGame()
    self.players = players
    self:_nextStage()
end

function Game:_nextStage()
    self.si = self.si + 1
    self.st, self.play, self.history = nil, nil, {}
    local id = self:stage()
    if id == "final" then
        local t = self:leader()
        if not t then
            -- A tie after the last qualifying stage: one sudden-death name.
            self.si = self.si - 1
            self:_startSudden()
            return
        end
        self:_setupFinal(t)
        return
    end
    self.phase = "intro"
end

-- "Start round" on a stage's intro screen.
function Game:beginStage()
    if self.phase ~= "intro" then return end
    local id = self:stage()
    if id == "riddles" then
        self.st = { options = self:draw("riddles", Game.RIDDLE_OPTIONS), taken = {}, n = 1,
                    order = Game.PICK_ORDER, turns = { 0, 0 } }
        self.phase = "pick"
    elseif id == "clock" then
        local first = self:trailing()
        self.st = { options = self:draw("clock", Game.CLOCK_OPTIONS), taken = {}, n = 1,
                    order = { first, 3 - first, first, 3 - first }, turns = { 0, 0 } }
        self.phase = "pick"
    elseif id == "names" then
        local first = self:trailing()
        self.st = { options = self:draw("names", Game.NAME_OPTIONS), taken = {}, n = 1,
                    order = { first, 3 - first }, turns = { 0, 0 } }
        self.phase = "pick"
    elseif id == "pingpong" then
        local words = {}
        for i, w in ipairs(self:draw("words", Game.PP_WORDS)) do words[i] = w end
        self.st = { words = words, first = self:trailing() }
        local g1 = self:roles(1)
        local g2 = self:roles(2)
        self.play = { kind = "pingpong", pos = 1, bricks = Game.PP_BRICKS, word_bricks = 0,
                      active = self.st.first, results = {}, givers = { g1, g2 } }
        self.phase = "handover"
    end
end

-- The team whose turn it is to pick (riddles, clock, names).
function Game:picker()
    return self.st and self.st.order[self.st.n]
end

function Game:canPick(i)
    return self.phase == "pick" and self.st.options[i] ~= nil and not self.st.taken[i]
end

function Game:pick(i)
    if not self:canPick(i) then return false end
    local st = self.st
    local t = self:picker()
    st.taken[i] = t
    st.turns[t] = st.turns[t] + 1
    local item = st.options[i]
    local id = self:stage()
    if id == "names" then
        st.theme = { opt = i, owner = t, idx = 1, results = {} }
        self:_prepareName()
        return true
    end
    local giver, guesser = self:roles(t, st.turns[t])
    if id == "riddles" then
        self.play = { kind = "riddles", team = t, giver = giver, guesser = guesser, item = item,
                      pos = 1, bricks = Game.RIDDLE_BRICKS, results = {} }
    else
        -- 7 of the theme's words, in a random order.
        local all = shuffle(copy(item.w), self.rng)
        local words = {}
        for k = 1, math.min(Game.CLOCK_WORDS, #all) do words[k] = all[k] end
        self.play = { kind = "clock", team = t, giver = giver, guesser = guesser, item = item,
                      words = words, queue = copy(words), found = 0, results = {} }
    end
    self.phase = "handover"
    return true
end

-- ---------------------------------------------------------------------------
-- Turns (hand-over → turn)
-- ---------------------------------------------------------------------------

function Game:_push()
    self.history[#self.history + 1] = { play = copy(self.play), score = copy(self.score),
        stage_scores = copy(self.stage_scores), phase = self.phase }
end

function Game:canUndo()
    return (self.phase == "turn" or self.phase == "answer") and #self.history > 0
end

function Game:undo()
    if not self:canUndo() then return false end
    local h = table.remove(self.history)
    self.play, self.score, self.stage_scores, self.phase = h.play, h.score, h.stage_scores, h.phase
    return true
end

-- "Ready" on the hand-over screen.
function Game:startTurn()
    if self.phase ~= "handover" or not self.play then return end
    self.history = {}
    local p = self.play
    if p.kind == "clock" then
        -- A timed turn always starts (or restarts) from scratch.
        p.queue, p.found, p.results = copy(p.words), 0, {}
    end
    if p.kind == "riddles" and self:_riddleWordsDone() then
        self.phase = "answer"
        return
    end
    self.phase = "turn"
end

function Game:currentWord()
    local p = self.play
    if not p or (self.phase ~= "turn" and self.phase ~= "answer") then return nil end
    if p.kind == "riddles" then
        if self.phase == "answer" then return p.item.a end
        return p.item.w[p.pos]
    elseif p.kind == "pingpong" then
        return self.st.words[p.pos]
    elseif p.kind == "clock" then
        return p.queue[1]
    elseif p.kind == "names" or p.kind == "sudden" then
        return p.name
    end
end

-- The team giving the current clue.
function Game:activeTeam()
    local p = self.play
    if not p then return nil end
    if p.kind == "pingpong" or p.kind == "sudden" then return p.active end
    return p.team
end

-- Each clue costs one brick; the guesser's answer is Found or Wrong, and a
-- forbidden clue loses the word (its brick is spent too).
function Game:found()
    if self.phase ~= "turn" then return end
    self:_push()
    local p = self.play
    if p.kind == "riddles" then
        p.bricks = p.bricks - 1
        p.results[p.pos] = true
        p.pos = p.pos + 1
        self:_riddleCheck()
    elseif p.kind == "pingpong" then
        p.bricks = p.bricks - 1
        self:addScore(p.active, 1)
        p.results[p.pos] = { team = p.active, found = true }
        self.last = { kind = "pp_found", team = p.active, word = self.st.words[p.pos] }
        self:_ppNext()
    elseif p.kind == "clock" then
        local w = table.remove(p.queue, 1)
        p.found = p.found + 1
        p.results[#p.results + 1] = { word = w, found = true }
        if #p.queue == 0 then self:endClock() end
    elseif p.kind == "names" then
        p.bricks = p.bricks - 1
        self:_nameDone(true)
    elseif p.kind == "sudden" then
        self:_suddenWin(p.active, "found")
    end
end

function Game:wrong()
    if self.phase ~= "turn" then return end
    local p = self.play
    if p.kind == "clock" then return end
    self:_push()
    if p.kind == "riddles" then
        p.bricks = p.bricks - 1
        self:_riddleCheck()
    elseif p.kind == "pingpong" then
        p.bricks = p.bricks - 1
        p.word_bricks = p.word_bricks + 1
        if p.word_bricks >= Game.PP_MAX_PER_WORD or p.bricks <= 0 then
            p.results[p.pos] = { found = false }
            self.last = { kind = "pp_lost", word = self.st.words[p.pos] }
            self:_ppNext()
        else
            p.active = 3 - p.active
        end
    elseif p.kind == "names" then
        p.bricks = p.bricks - 1
        if p.bricks <= 0 then self:_nameDone(false) end
    elseif p.kind == "sudden" then
        p.clues = (p.clues or 0) + 1
        p.active = 3 - p.active
    end
end

function Game:forbidden()
    if self.phase ~= "turn" then return end
    self:_push()
    local p = self.play
    if p.kind == "riddles" then
        p.bricks = p.bricks - 1
        p.results[p.pos] = false
        p.pos = p.pos + 1
        self:_riddleCheck()
    elseif p.kind == "pingpong" then
        p.bricks = p.bricks - 1
        p.results[p.pos] = { found = false, forbidden = true }
        self.last = { kind = "pp_forbidden", team = p.active, word = self.st.words[p.pos] }
        self:_ppNext()
    elseif p.kind == "clock" then
        local w = table.remove(p.queue, 1)
        p.results[#p.results + 1] = { word = w, found = false }
        if #p.queue == 0 then self:endClock() end
    elseif p.kind == "names" then
        p.bricks = p.bricks - 1
        self:_nameDone(false)
    elseif p.kind == "sudden" then
        self:_suddenWin(3 - p.active, "forbidden")
    end
end

-- Clock only: the word goes to the end of the list.
function Game:canPass()
    local p = self.play
    return self.phase == "turn" and p and p.kind == "clock" and #p.queue >= 2
end

function Game:pass()
    if not self:canPass() then return end
    self:_push()
    local p = self.play
    local w = table.remove(p.queue, 1)
    p.queue[#p.queue + 1] = w
end

-- Riddles ------------------------------------------------------------------

function Game:_riddleWordsDone()
    local p = self.play
    return p.pos > Game.RIDDLE_WORDS or p.bricks <= 0
end

function Game:_riddleCheck()
    local p = self.play
    if self:_riddleWordsDone() then
        -- Out of bricks: the words left are missed.
        for i = p.pos, Game.RIDDLE_WORDS do p.results[i] = false end
        p.pos = Game.RIDDLE_WORDS + 1
        self.phase = "answer"
    end
end

function Game:riddleFoundCount()
    local n = 0
    for i = 1, Game.RIDDLE_WORDS do if self.play.results[i] then n = n + 1 end end
    return n
end

-- The guesser gives the riddle's answer; the clue-giver checks it.
function Game:answer(right)
    if self.phase ~= "answer" then return end
    local p = self.play
    local words = self:riddleFoundCount()
    local bonus = words == Game.RIDDLE_WORDS and p.bricks or 0
    local pts = words + (right and 1 or 0) + bonus
    self:addScore(p.team, pts)
    self.last = { kind = "riddle", team = p.team, title = p.item.t, answer = p.item.a,
                  words = words, solved = right and true or false, bonus = bonus, points = pts,
                  results = copy(p.results), list = copy(p.item.w) }
    self.history = {}
    self.phase = "result"
end

-- Ping-pong ------------------------------------------------------------------

function Game:_ppNext()
    local p = self.play
    p.pos = p.pos + 1
    p.word_bricks = 0
    -- The next word starts with the other team than the previous one did.
    p.active = (p.pos % 2 == 1) and self.st.first or (3 - self.st.first)
    if p.pos > Game.PP_WORDS or p.bricks <= 0 then
        self.history = {}
        local found = { 0, 0 }
        for _, r in pairs(p.results) do
            if r.team and r.found then found[r.team] = found[r.team] + 1 end
        end
        self.last = { kind = "pingpong", found = found, words = copy(self.st.words),
                      results = copy(p.results), played = math.min(p.pos - 1, Game.PP_WORDS) }
        self.phase = "result"
    end
end

-- Clock ----------------------------------------------------------------------

-- Time up, or no word left.
function Game:endClock()
    if self.phase ~= "turn" then return end
    local p = self.play
    if p.kind ~= "clock" then return end
    for _, w in ipairs(p.queue) do p.results[#p.results + 1] = { word = w, found = false } end
    p.queue = {}
    self:addScore(p.team, p.found)
    self.last = { kind = "clock", team = p.team, title = p.item.t, points = p.found,
                  results = copy(p.results) }
    self.history = {}
    self.phase = "result"
end

-- Proper names -----------------------------------------------------------------

function Game:themeItem()
    local th = self.st and self.st.theme
    return th and self.st.options[th.opt]
end

-- Before each name: the opponent of the theme's team may bid.
function Game:_prepareName()
    local th = self.st.theme
    th.bid = nil
    self.play = nil
    self.phase = "bid"
end

function Game:bidder()
    local th = self.st and self.st.theme
    return th and (3 - th.owner)
end

-- bid = nil (no bid) or a brick count strictly below the limit.
function Game:placeBid(bid)
    if self.phase ~= "bid" then return false end
    local th = self.st.theme
    if bid ~= nil and (bid < 1 or bid >= self.name_bricks) then return false end
    th.bid = bid
    local t = bid and (3 - th.owner) or th.owner
    local item = self:themeItem()
    local giver, guesser = self:roles(t, th.idx)
    self.play = { kind = "names", team = t, giver = giver, guesser = guesser,
                  name = item.n[th.idx], bricks = bid or self.name_bricks,
                  limit = bid or self.name_bricks, bid = bid }
    self.phase = "handover"
    return true
end

function Game:_nameDone(found)
    local p = self.play
    local th = self.st.theme
    local scorer, pts
    if found then
        scorer, pts = p.team, 1
    else
        scorer, pts = 3 - p.team, (p.bid == 1) and 2 or 1
    end
    self:addScore(scorer, pts)
    th.results[th.idx] = { name = p.name, team = p.team, found = found, scorer = scorer,
                           points = pts, bid = p.bid }
    self.last = { kind = "name", team = p.team, name = p.name, found = found, scorer = scorer,
                  points = pts, bid = p.bid, used = p.limit - p.bricks }
    self.history = {}
    th.idx = th.idx + 1
    if th.idx > Game.NAMES_PER_THEME then
        self.last.theme_done = true
        self.phase = "result"
    else
        self:_prepareName()
    end
end

-- Sudden death -----------------------------------------------------------------

function Game:_suddenName()
    local pool = {}
    for _, th in ipairs(self.content("names") or {}) do
        for _, n in ipairs(th.n or {}) do pool[#pool + 1] = n end
    end
    local used = {}
    if self.st and self.st.options then
        for _, th in ipairs(self.st.options) do
            for _, n in ipairs(th.n or {}) do used[n] = true end
        end
    end
    local fresh = {}
    for _, n in ipairs(pool) do
        if not used[n] and not self.used["sudden:" .. n] then fresh[#fresh + 1] = n end
    end
    if #fresh == 0 then fresh = pool end
    local n = fresh[self.rng(#fresh)] or "?"
    self.used["sudden:" .. n] = true
    return n
end

function Game:_startSudden()
    self.history = {}
    local g1 = self:roles(1)
    local g2 = self:roles(2)
    self.play = { kind = "sudden", name = self:_suddenName(), active = 1, clues = 0,
                  givers = { g1, g2 } }
    self.phase = "handover"
end

function Game:isSudden()
    return self.play and self.play.kind == "sudden"
end

function Game:suddenNewName()
    if self.phase ~= "turn" or not self:isSudden() then return end
    self.play.name = self:_suddenName()
    self.play.clues = 0
end

function Game:_suddenWin(t, reason)
    local p = self.play
    self.last = { kind = "sudden", team = t, reason = reason, name = p.name }
    self.history = {}
    self.sudden_winner = t
    self.si = self.si + 1
    self:_setupFinal(t)
end

-- ---------------------------------------------------------------------------
-- Result screens → next pick / next stage
-- ---------------------------------------------------------------------------

function Game:continue()
    if self.phase ~= "result" then return end
    local id = self:stage()
    local st = self.st
    self.play = nil
    if id == "riddles" or id == "clock" or id == "names" then
        st.n = st.n + 1
        st.theme = nil
        if st.order[st.n] then
            self.phase = "pick"
            return
        end
    end
    self:_nextStage()
end

-- ---------------------------------------------------------------------------
-- The Great Pyramid
-- ---------------------------------------------------------------------------

function Game:_setupFinal(t)
    local giver, guesser = self:teamPlayers(t)
    self.final = { team = t, giver = giver, guesser = guesser }
    self.play = nil
    self.phase = "final_handover"
end

function Game:swapRoles()
    local f = self.final
    if f and self.phase == "final_handover" then f.giver, f.guesser = f.guesser, f.giver end
end

function Game:finalStart()
    if self.phase ~= "final_handover" then return end
    local f = self.final
    local set = self:draw("pyramid", 1)[1] or {}
    f.exprs = {}
    for i = 1, Game.FINAL_COUNT do f.exprs[i] = set[i] or "?" end
    f.queue = {}
    for i = 1, Game.FINAL_COUNT do f.queue[i] = i end
    f.done = {}
    f.outcome = nil
    self.history = {}
    self.phase = "final_turn"
end

function Game:finalCurrent()
    local f = self.final
    return f and f.queue and f.queue[1]
end

function Game:finalFoundCount()
    local n = 0
    for i = 1, Game.FINAL_COUNT do if self.final.done[i] then n = n + 1 end end
    return n
end

function Game:_finalPush()
    local f = self.final
    self.history[#self.history + 1] = { queue = copy(f.queue), done = copy(f.done) }
end

function Game:canFinalUndo()
    return self.phase == "final_turn" and #self.history > 0
end

function Game:finalUndo()
    if not self:canFinalUndo() then return false end
    local h = table.remove(self.history)
    self.final.queue, self.final.done = h.queue, h.done
    return true
end

function Game:finalFound()
    if self.phase ~= "final_turn" then return end
    self:_finalPush()
    local f = self.final
    local i = table.remove(f.queue, 1)
    f.done[i] = true
    if #f.queue == 0 then self:_finalEnd("won") end
end

function Game:canFinalPass()
    return self.phase == "final_turn" and #self.final.queue >= 2
end

function Game:finalPass()
    if not self:canFinalPass() then return end
    self:_finalPush()
    local f = self.final
    local i = table.remove(f.queue, 1)
    f.queue[#f.queue + 1] = i
end

-- All or nothing: a forbidden clue or the end of the minute loses the prize.
function Game:finalForbidden()
    if self.phase ~= "final_turn" then return end
    self:_finalEnd("forbidden")
end

function Game:finalTimeUp()
    if self.phase ~= "final_turn" then return end
    self:_finalEnd("time")
end

function Game:_finalEnd(kind)
    local f = self.final
    f.outcome = { kind = kind, found = self:finalFoundCount() }
    self.history = {}
    self.phase = "game_over"
end

function Game:restartFinal()
    if not self.final then return end
    self:_setupFinal(self.final.team)
end

function Game:isGameOver()
    return self.phase == "game_over"
end

-- ---------------------------------------------------------------------------
-- Save / restore. A turn in progress is never restored on a visible word: it
-- goes back to its hand-over screen. Untimed turns keep their progress; timed
-- ones (against the clock, the final) start again.
-- ---------------------------------------------------------------------------

function Game:serialize()
    local phase = self.phase
    local final = copy(self.final)
    if phase == "turn" or phase == "answer" then
        phase = "handover"
    elseif phase == "final_turn" then
        phase = "final_handover"
        final.exprs, final.queue, final.done = nil, nil, nil
    end
    return {
        version = 1, phase = phase, round2 = self.round2, name_bricks = self.name_bricks,
        stages = copy(self.stages), si = self.si,
        players = copy(self.players), score = copy(self.score),
        stage_scores = copy(self.stage_scores), used = copy(self.used_list),
        st = copy(self.st), play = copy(self.play), last = copy(self.last), final = final,
    }
end

local PHASES = { setup = true, intro = true, pick = true, bid = true, handover = true,
                 result = true, final_handover = true, game_over = true }

function Game:load(state)
    if type(state) ~= "table" or state.version ~= 1 or not PHASES[state.phase]
        or type(state.players) ~= "table" or type(state.score) ~= "table"
        or type(state.stages) ~= "table" then
        return false
    end
    self:newGame()
    self.phase = state.phase
    self.round2 = state.round2 or self.round2
    self.name_bricks = tonumber(state.name_bricks) or self.name_bricks
    self.stages = state.stages
    self.si = tonumber(state.si) or 0
    for i = 1, 4 do self.players[i] = tostring(state.players[i] or self.players[i]) end
    for t = 1, 2 do self.score[t] = tonumber(state.score[t]) or 0 end
    self.stage_scores = state.stage_scores or {}
    for _, k in ipairs(state.used or {}) do
        self.used[k] = true
        self.used_list[#self.used_list + 1] = k
    end
    self.st, self.play, self.last, self.final = state.st, state.play, state.last, state.final
    local ok = true
    if self.phase ~= "setup" and not self:stage() then ok = false end
    if (self.phase == "pick" or self.phase == "bid") and not self.st then ok = false end
    if self.phase == "handover" and not self.play then ok = false end
    if (self.phase == "final_handover" or self.phase == "game_over") and not self.final then ok = false end
    if self.phase == "game_over" and not self.final.outcome then ok = false end
    if not ok then self:newGame() end
    return ok
end

return Game
