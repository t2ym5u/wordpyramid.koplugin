local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"

local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local Blitbuffer      = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device          = require("device")
local Font            = require("ui/font")
local FrameContainer  = require("ui/widget/container/framecontainer")
local Geom            = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local InputDialog     = require("ui/widget/inputdialog")
local Size            = require("ui/size")
local TextBoxWidget   = require("ui/widget/textboxwidget")
local TextWidget      = require("ui/widget/textwidget")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local _               = require("i18n")
local T               = require("ffi/util").template

local MenuHelper = require("menu_helper")
local ScreenBase = require("screen_base")
local SeenHistory = require("seen_history")
local Game       = lrequire("game")
local W          = lrequire("widgets")

local DeviceScreen = Device.screen

-- Items remembered across games, per language (all kinds: ~3100 in French).
local SEEN_MAX = 4000
local KINDS = { "riddles", "names", "clock", "pyramid", "words" }

local GAME_RULES_EN = [[
Word Pyramid — Rules

Inspired by the classic French TV word game. Four players in two teams of two (A and B): in each team one player gives the clues, the partner guesses; the roles swap from turn to turn. The clue-giver holds the reader and sees the secret word; the guesser must not see the screen. Before each turn a hand-over screen says who looks away; the word only appears after Ready.

BRICKS — every clue is ONE word and costs one brick. After each clue the guesser gives one answer:
• Found: the word is found (the brick of that clue is spent).
• Clue given / Wrong: the answer was wrong, the brick is spent, next clue.
• Forbidden!: the clue wasn't allowed, the word is lost.
• Undo takes back the last tap.

ROUND 1 — RIDDLES. 6 riddle titles are offered (e.g. "He lost at Waterloo"); team A picks one, then B, then A, then B. A riddle hides 5 words linked to its answer: find them one after the other with a stock of 13 bricks, 1 point each. Then the guesser gives the riddle's answer: +1 if right. If all 5 words were found, every unused brick is a bonus point; a missed word cancels the bonus. Out of bricks: the words left are missed.

ROUND 2 — PING-PONG. 5 words played back and forth: team A's clue-giver gives a clue to A's guesser; if wrong, team B's clue-giver gives the next clue on the same word to B's guesser, and so on. 13 bricks in all for the round, 5 at most per word; the team that finds the word scores 1 point.

ROUND 3 — AGAINST THE CLOCK. 4 themes; the team behind picks first, then the teams alternate (2 themes each). 30 seconds to find up to 7 words linked to the theme, 1 point each; Pass sends a word to the end of the list.

ROUND 4 — PROPER NAMES. 6 themes of 4 famous names (people, monuments, cities, characters). The team behind picks a theme first, the other team plays a theme next. Each name may take at most 4 bricks (setting: 3, 4 or 5). Before each name, the other team may bid fewer bricks and take the name over. A name not found goes to the other team: it scores 1 point (2 points if a 1-brick bid failed). After this round the leading team plays the final; on a tie, a sudden-death name: the clue-givers take turns, one clue each; the first team to find it goes through, a forbidden clue eliminates.

FINAL — THE GREAT PYRAMID. The winning team has 1 minute to find 6 expressions (idioms, famous titles…), word by word or as a whole. Pass sends one to the end. It's all or nothing: the 6 must be found before the end of the minute, and a forbidden clue loses everything.

FORBIDDEN CLUES
• the word itself, or part of it;
• compound or hyphenated words;
• translations into another language;
• brand names;
• words of the same family or root (the same first sound is allowed);
• gestures, miming, spelling;
• "incitations" — a clue that sounds like the start of the word — are allowed only from the 3rd brick on.

The round-2 setting plays both the ping-pong and the against-the-clock round (as in the 2002 seasons), or only one of them. The show's phone-in game for viewers has no table equivalent and is left out.
]]

local GAME_RULES_FR = [[
La Pyramide des mots — Règles

Inspiré du jeu télévisé français classique. Quatre joueurs en deux équipes de deux (A et B) : dans chaque équipe un joueur fait deviner, son partenaire devine ; les rôles s'inversent d'un tour à l'autre. Celui qui fait deviner tient la liseuse et voit le mot secret ; celui qui devine ne doit pas voir l'écran. Avant chaque tour, un écran de passage dit qui détourne les yeux ; le mot n'apparaît qu'après « Prêt ».

LES BRIQUES — chaque indice est UN seul mot et coûte une brique. Après chaque indice, celui qui devine donne une réponse :
• Trouvé : le mot est trouvé (la brique de cet indice est dépensée).
• Indice donné / Faux : mauvaise réponse, la brique est dépensée, indice suivant.
• Interdit ! : l'indice n'était pas permis, le mot est perdu.
• Annuler reprend la dernière touche.

MANCHE 1 — LES ÉNIGMES. 6 titres d'énigmes sont proposés (par ex. « Il a perdu à Waterloo ») ; l'équipe A en choisit un, puis B, puis A, puis B. Une énigme cache 5 mots liés à sa réponse : trouvez-les l'un après l'autre avec un stock de 13 briques, 1 point chacun. Puis celui qui devine donne la réponse de l'énigme : +1 si elle est juste. Si les 5 mots ont été trouvés, chaque brique restante rapporte un point de bonus ; un mot manqué annule le bonus. Plus de briques : les mots restants sont manqués.

MANCHE 2 — LE PING-PONG. 5 mots joués en alternance : le meneur de l'équipe A donne un indice à son partenaire ; s'il se trompe, le meneur de l'équipe B donne l'indice suivant sur le même mot à son partenaire, et ainsi de suite. 13 briques en tout pour la manche, 5 au plus par mot ; l'équipe qui trouve le mot marque 1 point.

MANCHE 3 — LE CONTRE-LA-MONTRE. 4 thèmes ; l'équipe menée choisit la première, puis les équipes alternent (2 thèmes chacune). 30 secondes pour faire trouver jusqu'à 7 mots liés au thème, 1 point chacun ; Passer renvoie un mot en fin de liste.

MANCHE 4 — LES NOMS PROPRES. 6 thèmes de 4 noms célèbres (personnages, monuments, villes, héros de fiction). L'équipe menée choisit un thème la première, l'autre équipe joue ensuite un thème à son tour. Chaque nom se joue en 4 briques au plus (réglage : 3, 4 ou 5). Avant chaque nom, l'équipe adverse peut annoncer moins de briques et prendre le nom à son compte. Un nom non trouvé revient à l'autre équipe : elle marque 1 point (2 points si une annonce à 1 brique échoue). À l'issue de cette manche, l'équipe en tête joue la finale ; en cas d'égalité, un nom décisif en mort subite : les meneurs donnent un indice chacun leur tour ; la première équipe qui trouve est qualifiée, un indice interdit élimine.

FINALE — LA GRANDE PYRAMIDE. L'équipe gagnante a 1 minute pour faire trouver 6 expressions (expressions toutes faites, titres célèbres…), mot par mot ou en entier. Passer en renvoie une à la fin. C'est tout ou rien : les 6 doivent être trouvées avant la fin de la minute, et un indice interdit fait tout perdre.

INDICES INTERDITS
• le mot lui-même, ou une partie du mot ;
• les mots composés ou avec trait d'union ;
• les traductions dans une autre langue ;
• les marques ;
• les mots de la même famille ou de la même racine (le même premier son est permis) ;
• les gestes, le mime, épeler ;
• les « incitations » — un indice qui sonne comme le début du mot — ne sont permises qu'à partir de la 3e brique.

Le réglage de la manche 2 joue à la fois le ping-pong et le contre-la-montre (comme dans les saisons 2002), ou un seul des deux. Le jeu par téléphone des téléspectateurs de l'émission n'a pas d'équivalent autour d'une table et n'est pas repris.
]]

-- One file per language and kind, each loaded only when first needed.
local function contentLoader(lang)
    local cache = {}
    return function(kind)
        if cache[kind] == nil then
            local chunk = loadfile(_dir .. "content/" .. lang .. "/" .. kind .. ".lua")
            local ok, data = pcall(chunk or error)
            cache[kind] = ok and type(data) == "table" and data or {}
        end
        return cache[kind]
    end
end

local function para(text, face, width)
    return TextBoxWidget:new{ text = text, face = face, width = width, alignment = "center" }
end

-- A vertical list of widgets separated by spans.
local function stack(items, vs)
    local g = VerticalGroup:new{ align = "center" }
    for i, w in ipairs(items) do
        if i > 1 then g[#g + 1] = VerticalSpan:new{ width = vs } end
        g[#g + 1] = w
    end
    return g
end

local function nbsp(s)
    return (s:gsub(" ", "\u{00A0}"))
end

-- ---------------------------------------------------------------------------

local PyramidScreen = ScreenBase:extend{}

function PyramidScreen:init()
    local plugin = self.plugin
    self.lang = plugin:getLang({ "fr", "en" })
    self.unit = plugin:getSetting("unit", "euros")
    self:_migrateRecent()
    self.game = Game.new{
        players = self:_savedPlayers(),
        content = contentLoader(self.lang),
        seen = self:_seen(self.lang),
        round2 = plugin:getSetting("round2", "both"),
        name_bricks = plugin:getSetting("name_bricks", 4),
    }
    self.game:load(plugin:loadState())
    ScreenBase.init(self)
end

function PyramidScreen:_savedPlayers()
    local saved = self.plugin:getSetting("players", {})
    local out = {}
    for i = 1, 4 do out[i] = saved[i] or T(_("Player %1"), i) end
    return out
end

function PyramidScreen:serializeState()
    return self.game:serialize()
end

function PyramidScreen:_save()
    self.plugin:saveState(self:serializeState())
end

function PyramidScreen:_redraw()
    self:buildLayout()
    UIManager:setDirty(self, function() return "ui", self.dimen end)
end

function PyramidScreen:_name(p)
    return self.game.players[p] or "?"
end

function PyramidScreen:_teamLetter(t)
    return t == 1 and "A" or "B"
end

function PyramidScreen:_teamName(t)
    local a, b = self.game:teamPlayers(t)
    return T(_("%1 & %2"), self:_name(a), self:_name(b))
end

function PyramidScreen:_team(t)
    return T(_("Team %1"), self:_teamLetter(t))
end

function PyramidScreen:_prize()
    return Game.formatPrize(Game.PRIZE[self.unit] or Game.PRIZE.euros, self.unit, _.lang())
end

local STAGE_LABELS = {
    riddles  = function() return _("Riddles") end,
    pingpong = function() return _("Ping-pong") end,
    clock    = function() return _("Against the clock") end,
    names    = function() return _("Proper names") end,
    final    = function() return _("The Great Pyramid") end,
}

function PyramidScreen:_stageLabel(id)
    id = id or self.game:stage()
    return STAGE_LABELS[id] and STAGE_LABELS[id]() or ""
end

-- "Round 2 · Ping-pong" (the final has no number).
function PyramidScreen:_stageTitle(id)
    local g = self.game
    id = id or g:stage()
    if id == "final" then return self:_stageLabel(id) end
    return T(_("Round %1 · %2"), g:stageNumber(id) or 1, self:_stageLabel(id))
end

-- ---------------------------------------------------------------------------
-- Timers: one tick per second, only the timer widget is refreshed.
-- ---------------------------------------------------------------------------

function PyramidScreen:_startCountdown(seconds)
    self.time_left = seconds
    self._tick_gen = (self._tick_gen or 0) + 1
    local gen = self._tick_gen
    UIManager:scheduleIn(1, function() self:_onTick(gen) end)
end

function PyramidScreen:_stopCountdown()
    self._tick_gen = (self._tick_gen or 0) + 1
end

function PyramidScreen:_timerText()
    local t = self.time_left or 0
    return string.format("%d:%02d", math.floor(t / 60), t % 60)
end

function PyramidScreen:_refreshTimer()
    if not self.timer_widget then return end
    self.timer_widget:setText(self:_timerText())
    UIManager:setDirty(self, function()
        return "fast", self.timer_frame and self.timer_frame.dimen or self.dimen
    end)
end

function PyramidScreen:_isTimed()
    local g = self.game
    return g.phase == "final_turn" or (g.phase == "turn" and g.play and g.play.kind == "clock")
end

function PyramidScreen:_onTick(gen)
    if gen ~= self._tick_gen or not self:_isTimed() then return end
    self.time_left = math.max(0, (self.time_left or 0) - 1)
    if self.time_left <= 0 then
        self:onTimeUp()
        return
    end
    self:_refreshTimer()
    UIManager:scheduleIn(1, function() self:_onTick(gen) end)
end

-- ---------------------------------------------------------------------------
-- Actions
-- ---------------------------------------------------------------------------

-- What was dealt (riddles, names, themes, words, pyramids), remembered in
-- the settings ("seen_content_<lang>") as it is dealt: an item comes back
-- only once every item of its kind has been played.
function PyramidScreen:_seen(lang)
    return SeenHistory.open(self.plugin, "content_" .. lang, { max = SEEN_MAX })
end

-- Up to 1.0.x the last 600 items of finished games were kept under
-- "recent" (newest first, both languages mixed): move them into each
-- language's history once, then drop the old setting.
function PyramidScreen:_migrateRecent()
    local old = self.plugin:getSetting("recent", nil)
    if old == nil then return end
    if type(old) == "table" then
        Game.migrateRecent(old, { fr = contentLoader("fr"), en = contentLoader("en") }, KINDS,
            function(lang) return self:_seen(lang) end)
    end
    self.plugin:saveSetting("recent", nil)
end

function PyramidScreen:_hasContent()
    for _i, kind in ipairs(KINDS) do
        if #self.game.content(kind) == 0 then return false end
    end
    return true
end

function PyramidScreen:_applySettings()
    local g = self.game
    g.round2 = self.plugin:getSetting("round2", "both")
    g.name_bricks = self.plugin:getSetting("name_bricks", 4)
end

function PyramidScreen:_act(fn)
    fn()
    self:_save()
    self:_redraw()
end

function PyramidScreen:onStartGame()
    if not self:_hasContent() then
        self:showMessage(_("No words for this language."))
        return
    end
    self:_applySettings()
    self:_act(function() self.game:startGame() end)
end

function PyramidScreen:onBeginStage()
    self:_act(function() self.game:beginStage() end)
end

function PyramidScreen:onPick(i)
    self:_act(function() self.game:pick(i) end)
end

function PyramidScreen:onBid(n)
    self:_act(function() self.game:placeBid(n) end)
end

function PyramidScreen:onReady()
    self.game:startTurn()
    self:_save()
    if self:_isTimed() then self:_startCountdown(Game.CLOCK_TIME) end
    self:_redraw()
end

-- Found / Wrong / Forbidden / Pass in every turn kind.
function PyramidScreen:_turnAction(method)
    self.game[method](self.game)
    if not self:_isTimed() then self:_stopCountdown() end
    self:_save()
    self:_redraw()
end

function PyramidScreen:onFound() self:_turnAction("found") end
function PyramidScreen:onWrong() self:_turnAction("wrong") end
function PyramidScreen:onForbidden() self:_turnAction("forbidden") end
function PyramidScreen:onPass() self:_turnAction("pass") end

function PyramidScreen:onUndo()
    if self.game:undo() then
        self:_save()
        self:_redraw()
    end
end

function PyramidScreen:onAnswer(right)
    self:_act(function() self.game:answer(right) end)
end

function PyramidScreen:onOtherName()
    self.game:suddenNewName()
    self:_redraw()
end

function PyramidScreen:onContinue()
    self:_act(function() self.game:continue() end)
end

function PyramidScreen:onTimeUp()
    self:_stopCountdown()
    local g = self.game
    if g.phase == "final_turn" then g:finalTimeUp() else g:endClock() end
    self:_save()
    self:_redraw()
    self:showMessage(_("Time's up!"), 2)
end

-- Final -------------------------------------------------------------------

function PyramidScreen:onSwapRoles()
    self:_act(function() self.game:swapRoles() end)
end

function PyramidScreen:onFinalReady()
    self.game:finalStart()
    self:_save()
    self:_startCountdown(Game.FINAL_TIME)
    self:_redraw()
end

function PyramidScreen:_finalAction(method)
    self.game[method](self.game)
    if self.game.phase ~= "final_turn" then
        self:_stopCountdown()
        self:_save()
    end
    self:_redraw()
end

function PyramidScreen:onFinalFound() self:_finalAction("finalFound") end
function PyramidScreen:onFinalPass() self:_finalAction("finalPass") end
function PyramidScreen:onFinalForbidden() self:_finalAction("finalForbidden") end
function PyramidScreen:onFinalUndo() self:_finalAction("finalUndo") end

function PyramidScreen:onNewGame()
    self:_stopCountdown()
    self:_applySettings()
    self.game:newGame()
    self:_save()
    self:_redraw()
end

function PyramidScreen:onFinalAgain()
    self:_stopCountdown()
    self:_act(function() self.game:restartFinal() end)
end

-- ---------------------------------------------------------------------------
-- Settings
-- ---------------------------------------------------------------------------

function PyramidScreen:_picker(title, items, current, on_select)
    MenuHelper.openPickerMenu{
        title = title, items = items, current_id = current, parent = self,
        on_select = function(id)
            on_select(id)
            self:_redraw()
        end,
    }
end

-- Rules settings change how a game is played: they apply from the next game.
function PyramidScreen:_nextGameSetting(key, value)
    self.plugin:saveSetting(key, value)
    if self.game.phase == "setup" then
        self:_applySettings()
        self.game:newGame()
    else
        self:showMessage(_("Applies from the next game."), 2)
    end
end

function PyramidScreen:openLangMenu()
    self:_picker(_("Language"),
        { { id = "fr", text = "Français" }, { id = "en", text = "English" } }, self.lang,
        function(lang)
            self.lang = lang
            self.plugin:setLang(lang)
            self.game.content = contentLoader(lang)
            self.game.seen = self:_seen(lang)
        end)
end

local ROUND2 = { "both", "pingpong", "clock" }

function PyramidScreen:_round2Label(v)
    v = v or self.plugin:getSetting("round2", "both")
    if v == "pingpong" then return _("Ping-pong") end
    if v == "clock" then return _("Against the clock") end
    return _("Ping-pong + against the clock")
end

function PyramidScreen:openRound2Menu()
    local items = {}
    for i, v in ipairs(ROUND2) do items[i] = { id = v, text = self:_round2Label(v) } end
    self:_picker(_("Round 2"), items, self.plugin:getSetting("round2", "both"),
        function(v) self:_nextGameSetting("round2", v) end)
end

function PyramidScreen:openBricksMenu()
    local items = {}
    for n = 3, 5 do items[#items + 1] = { id = n, text = tostring(n) } end
    self:_picker(_("Bricks per name"), items, self.plugin:getSetting("name_bricks", 4),
        function(n) self:_nextGameSetting("name_bricks", n) end)
end

function PyramidScreen:_unitLabel(u)
    return (u or self.unit) == "points" and _("Points") or _("Euros (for fun)")
end

function PyramidScreen:openUnitMenu()
    self:_picker(_("Prizes"),
        { { id = "euros", text = self:_unitLabel("euros") }, { id = "points", text = self:_unitLabel("points") } },
        self.unit, function(u)
            self.unit = u
            self.plugin:saveSetting("unit", u)
        end)
end

function PyramidScreen:openPlayersDialog()
    local dialog
    dialog = InputDialog:new{
        title = _("Player names"),
        description = _("One name per line: team A's two players, then team B's."),
        input = table.concat(self.game.players, "\n"),
        allow_newline = true,
        buttons = { {
            { text = _("Cancel"), id = "close", callback = function() UIManager:close(dialog) end },
            { text = _("OK"), callback = function()
                local text = dialog:getInputText() or ""
                UIManager:close(dialog)
                self:applyPlayerNames(text)
            end },
        } },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

-- Renames in place (scores kept); missing lines keep the old name.
function PyramidScreen:applyPlayerNames(text)
    local names = {}
    for raw in (text .. "\n"):gmatch("(.-)\n") do
        local line = raw:gsub("^%s+", ""):gsub("%s+$", "")
        if line ~= "" then names[#names + 1] = line end
    end
    for i = 1, 4 do
        if names[i] then self.game.players[i] = names[i] end
    end
    self.plugin:saveSetting("players", { unpack(self.game.players) })
    self:_save()
    self:_redraw()
end

-- ---------------------------------------------------------------------------
-- Layout helpers
-- ---------------------------------------------------------------------------

function PyramidScreen:isRoundOver()
    return self.game:isGameOver()
end

function PyramidScreen:getRoundOverButtons()
    local new = self:_bigButton(_("New game"), function() self:onNewGame() end)
    local again = self:_bigButton(_("Final again"), function() self:onFinalAgain() end)
    if self:isLandscape() then return { { new }, { again } } end
    return { new, again }
end

function PyramidScreen:_bigButton(text, callback, extra, scale)
    local b = { text = text, callback = callback,
                height = DeviceScreen:scaleBySize(60 * (scale or 1)),
                font_size = math.floor(22 * math.min(scale or 1, 1.3)) }
    for k, v in pairs(extra or {}) do b[k] = v end
    return b
end

function PyramidScreen:_titleBar()
    return self:buildTitleBar(_("Word Pyramid"), function()
        return {
            { text = _("New game"), callback = function() self:onNewGame() end },
            { text = T(_("Language: %1"), self.lang:upper()), callback = function() self:openLangMenu() end },
            { text = T(_("Round 2: %1"), self:_round2Label()), callback = function() self:openRound2Menu() end },
            { text = T(_("Bricks per name: %1"), self.plugin:getSetting("name_bricks", 4)),
              callback = function() self:openBricksMenu() end },
            { text = T(_("Prizes: %1"), self:_unitLabel()), callback = function() self:openUnitMenu() end },
            { text = _("Player names"), callback = function() self:openPlayersDialog() end },
            self:makeRulesButtonConfig(GAME_RULES_EN, GAME_RULES_FR),
        }
    end)
end

function PyramidScreen:_controls(rows, extra_top)
    self.status_text:setMaxWidth(self:getControlsWidth())
    local g = VerticalGroup:new{ align = "center" }
    if extra_top then
        g[#g + 1] = extra_top
        g[#g + 1] = VerticalSpan:new{ width = Size.span.vertical_large }
    end
    g[#g + 1] = self.status_text
    g[#g + 1] = VerticalSpan:new{ width = Size.span.vertical_large }
    g[#g + 1] = self:buildActionBar(rows)
    return g
end

function PyramidScreen:_place(title_bar, content, controls)
    if self:isLandscape() then
        self:buildLandscapeLayout(title_bar, HorizontalGroup:new{
            align = "center",
            content,
            HorizontalSpan:new{ width = self:getGutter() },
            controls,
        })
    else
        self:buildPortraitLayout(title_bar, content,
            VerticalGroup:new{ align = "center", controls, VerticalSpan:new{ width = self:getGutter() } })
    end
end

-- Score table: one row per team, one column per qualifying stage, then total.
function PyramidScreen:_scoreTable(width, max_h)
    local g = self.game
    local headers = { "" }
    local ids = {}
    for i, id in ipairs(g.stages) do
        if id ~= "final" then
            ids[#ids + 1] = id
            headers[#headers + 1] = T(_("R%1"), i)
        end
    end
    headers[#headers + 1] = _("Total")
    local rows = {}
    for t = 1, 2 do
        local row = { self:_teamLetter(t) .. " · " .. self:_teamName(t) }
        for _i, id in ipairs(ids) do
            local s = g.stage_scores[id]
            row[#row + 1] = s and tostring(s[t]) or "–"
        end
        row[#row + 1] = g.score[t]
        rows[t] = row
    end
    return W.scoreTable(headers, rows, width, max_h)
end

-- Appends the score table under `items` when there is room for it.
function PyramidScreen:_withScores(items, bw, bh, vs)
    local short = math.min(self.dimen.w, self.dimen.h)
    local content = stack(items, vs * 2)
    local used = content:getSize().h
    -- Only when the table can be readable (3 rows of a decent height).
    if bh - used - 4 * vs > short * 0.2 then
        content = stack({ content, self:_scoreTable(math.floor(bw * 0.95),
            math.min(bh - used - 4 * vs, short * 0.3)) }, vs * 4)
    end
    return content
end

-- The big card holding the secret word, with an optional line under it.
function PyramidScreen:_wordCard(word, sub, bw, bh, label)
    local pad = Size.padding.large
    local vs = Size.span.vertical_large
    local inner_w = bw - 2 * (pad + Size.border.thick)
    local inner_h = bh - 2 * (pad + Size.border.thick)
    local g = VerticalGroup:new{ align = "center" }
    local extra_h = 0
    local label_w, sub_w
    if label then
        label_w = W.fitLine(label, math.min(inner_h * 0.1, inner_w * 0.06), inner_w)
        extra_h = extra_h + label_w:getSize().h + vs * 2
        g[#g + 1] = label_w
        g[#g + 1] = VerticalSpan:new{ width = vs * 2 }
    end
    if sub then
        sub_w = W.fitLine(sub, math.min(inner_h * 0.1, inner_w * 0.06), inner_w)
        extra_h = extra_h + sub_w:getSize().h + vs * 2
    end
    g[#g + 1] = W.fitParagraph(word or "?", math.min(inner_w * 0.14, inner_h * 0.3),
        inner_w, inner_h - extra_h, true)
    if sub_w then
        g[#g + 1] = VerticalSpan:new{ width = vs * 2 }
        g[#g + 1] = sub_w
    end
    return FrameContainer:new{
        bordersize = Size.border.thick, padding = pad, margin = 0, radius = Size.radius.window,
        CenterContainer:new{ dimen = Geom:new{ w = inner_w, h = inner_h }, g },
    }
end

-- Timer frame: only this area is refreshed every second.
function PyramidScreen:_timer(px)
    self.timer_widget = TextWidget:new{ text = self:_timerText(), face = W.pxFace(px, true), bold = true }
    local probe = W.fitLine("0:00", px, 10000, true)
    local w = probe:getSize().w + Size.padding.large
    probe:free()
    self.timer_frame = FrameContainer:new{
        bordersize = 0, padding = 0, margin = 0,
        CenterContainer:new{ dimen = Geom:new{ w = w, h = self.timer_widget:getSize().h }, self.timer_widget },
    }
    return self.timer_frame
end

function PyramidScreen:_timerPx()
    local short = math.min(self.dimen.w, self.dimen.h)
    return math.floor(short * (self:isLandscape() and 0.1 or 0.11))
end

function PyramidScreen:_headerWidth()
    return self:isLandscape() and self:getControlsWidth() or (self.dimen.w - 2 * self:getGutter())
end

-- Turn screens: header above the card in portrait, beside the buttons in
-- landscape. `below` (optional) goes under the card, sized by below_fn(w, h).
function PyramidScreen:_turnLayout(header, word, sub, rows, label, below_fn)
    local land = self:isLandscape()
    local title_bar = self:_titleBar()
    local controls = self:_controls(rows, land and header or nil)
    local bw, bh = self:getBoardBudget(title_bar, controls)
    local vs = Size.span.vertical_large
    local card_h = bh - ((land or not header) and 0 or (header:getSize().h + vs))
    local below
    if below_fn then
        local below_h = math.floor(card_h * 0.55)
        below = below_fn(bw, below_h)
        card_h = card_h - below:getSize().h - vs * 2
    end
    local items = {}
    if header and not land then items[#items + 1] = header end
    items[#items + 1] = self:_wordCard(word, sub, bw, card_h, label)
    if below then items[#items + 1] = below end
    local content = VerticalGroup:new{ align = "center" }
    for i, w in ipairs(items) do
        if i > 1 then content[#content + 1] = VerticalSpan:new{ width = below and i == #items and vs * 2 or vs } end
        content[#content + 1] = w
    end
    self:_place(title_bar, content, controls)
end

-- Header line + optional bricks row.
function PyramidScreen:_turnHeader(top, line, bricks_left, bricks_total)
    local hw = self:_headerWidth()
    local g = VerticalGroup:new{ align = "center" }
    if top then
        g[#g + 1] = top
        g[#g + 1] = VerticalSpan:new{ width = Size.span.vertical_default }
    end
    if line then
        g[#g + 1] = W.fitLine(line, Font:getFace("infofont").size * 1.1, hw, true)
    end
    if bricks_total then
        g[#g + 1] = VerticalSpan:new{ width = Size.span.vertical_default }
        g[#g + 1] = W.bricks(bricks_left, bricks_total, math.floor(hw * 0.95),
            math.floor(math.min(self.dimen.w, self.dimen.h) * 0.045))
    end
    return g
end

-- Found / Wrong / Forbidden / Undo, landscape-friendly.
function PyramidScreen:_clueRows(found_label)
    local g = self.game
    local found = self:_bigButton("✓ " .. (found_label or _("Found")), function() self:onFound() end, nil, 1.5)
    local wrong = self:_bigButton(_("Clue given / Wrong"), function() self:onWrong() end, nil, 1.2)
    local forbidden = self:_bigButton("✗ " .. _("Forbidden!"), function() self:onForbidden() end)
    local undo = self:_bigButton("↶ " .. _("Undo"), function() self:onUndo() end, { enabled = g:canUndo() })
    return { { found }, { wrong }, { forbidden, undo } }
end

function PyramidScreen:_lookAway(names)
    return T(_("Look away: %1"), names)
end

-- ---------------------------------------------------------------------------
-- Screens
-- ---------------------------------------------------------------------------

function PyramidScreen:buildLayout()
    local phase = self.game.phase
    self.timer_widget, self.timer_frame = nil, nil
    local builders = {
        intro = self._buildIntro, pick = self._buildPick, bid = self._buildBid,
        handover = self._buildHandover, turn = self._buildTurn, answer = self._buildAnswer,
        result = self._buildResult, final_handover = self._buildFinalHandover,
        final_turn = self._buildFinalTurn, game_over = self._buildGameOver,
    }
    local fn = builders[phase] or self._buildSetup
    fn(self)
    self[1] = self.layout
    self:updateStatus()
end

function PyramidScreen:_buildSetup()
    local g = self.game
    local title_bar = self:_titleBar()
    local controls = self:_controls({
        { self:_bigButton(_("Start game"), function() self:onStartGame() end, nil, 1.3) },
        { self:_bigButton(_("Player names"), function() self:openPlayersDialog() end) },
    })
    local bw, bh = self:getBoardBudget(title_bar, controls)
    local short = math.min(bw, bh)
    local vs = Size.span.vertical_large
    local rounds = {}
    for i, id in ipairs(Game.stagesFor(self.plugin:getSetting("round2", "both"))) do
        rounds[#rounds + 1] = id == "final" and self:_stageLabel(id) or (i .. ". " .. self:_stageLabel(id))
    end
    local items = {
        W.fitLine(_("Word Pyramid"), short * 0.1, bw, true),
        W.fitLine(T(_("Team %1: %2"), "A", self:_teamName(1)), short * 0.055, bw, true),
        W.fitLine(T(_("Team %1: %2"), "B", self:_teamName(2)), short * 0.055, bw, true),
        para(_("One-word clues, each one costs a brick. Four rounds, then the winning team climbs the Great Pyramid: 6 expressions in 1 minute, all or nothing."),
            Font:getFace("infofont"), bw),
        para(table.concat(rounds, " · "), Font:getFace("smallinfofont"), bw),
    }
    local top = stack(items, vs * 2)
    local pyr_h = math.min(bh - top:getSize().h - 6 * vs, short * 0.5)
    local content = top
    if pyr_h > short * 0.2 then
        local boxes = {}
        for i = 1, 6 do boxes[i] = { state = "todo" } end
        content = stack({ top, W.pyramid6(boxes, math.floor(math.min(bw, pyr_h * 1.6)), pyr_h) }, vs * 4)
    end
    self:_place(title_bar, content, controls)
end

local INTRO_TEXT = {
    riddles = function(s)
        return _("6 riddles are offered; team A picks one, then B, then A, then B. Find its 5 words with 13 bricks (1 point each), then the riddle's answer (+1). All 5 words found: +1 per unused brick.")
    end,
    pingpong = function(s)
        return _("5 words played back and forth: one clue for one team, the next clue on the same word for the other. 13 bricks in all, 5 at most per word; the team that finds the word scores 1 point.")
    end,
    clock = function(s)
        return _("4 themes, 2 per team, the team behind picks first. 30 seconds to find up to 7 words linked to the theme, 1 point each.")
    end,
    names = function(s)
        return T(_("Each team plays a theme of 4 famous names, %1 bricks at most per name. Before each name the other team may bid fewer bricks and take it over. Not found: the other team scores (2 points for a failed 1-brick bid). The leader then plays the final."),
            s.game.name_bricks)
    end,
}

function PyramidScreen:_buildIntro()
    local g = self.game
    local id = g:stage()
    local title_bar = self:_titleBar()
    local controls = self:_controls({ self:_bigButton(_("Start round"), function() self:onBeginStage() end, nil, 1.4) })
    local bw, bh = self:getBoardBudget(title_bar, controls)
    local short = math.min(bw, bh)
    local vs = Size.span.vertical_large
    local items = {
        W.fitLine(T(_("Round %1"), g:stageNumber(id)), short * 0.07, bw),
        W.fitLine(self:_stageLabel(id), short * 0.11, bw, true),
        para(INTRO_TEXT[id](self), Font:getFace("infofont"), math.floor(bw * 0.95)),
    }
    self:_place(title_bar, self:_withScores(items, bw, bh, vs), controls)
end

-- The riddles / themes on offer: one button each, the taken ones disabled.
function PyramidScreen:_buildPick()
    local g = self.game
    local id = g:stage()
    local st = g.st
    local t = g:picker()
    local rows = {}
    local land = self:isLandscape()
    local scale = land and 0.8 or 0.9
    for i, item in ipairs(st.options) do
        local taken = st.taken[i]
        local text = item.t
        if taken then text = "✓ " .. self:_teamLetter(taken) .. " · " .. text end
        rows[#rows + 1] = { self:_bigButton(text, function() self:onPick(i) end,
            { enabled = not taken, font_size = land and 18 or 20 }, scale) }
    end
    local title_bar = self:_titleBar()
    local controls = self:_controls(rows)
    local bw, bh = self:getBoardBudget(title_bar, controls)
    -- The option buttons take most of the height: size the heading on the screen.
    local short = math.min(bw, math.max(bh, math.min(self.dimen.w, self.dimen.h) * 0.6))
    local vs = Size.span.vertical_large
    local what = id == "riddles" and _("%1, pick a riddle")
        or (id == "clock" and _("%1, pick a theme for 30 seconds") or _("%1, pick a theme of 4 names"))
    local items = {
        W.fitLine(self:_stageTitle(id), short * 0.065, bw),
        W.fitLine(self:_team(t), short * 0.1, bw, true),
        para(T(what, self:_teamName(t)), Font:getFace("infofont"), bw),
    }
    self:_place(title_bar, self:_withScores(items, bw, bh, vs), controls)
end

-- Last proper name played, for the next neutral screen.
function PyramidScreen:_lastNameText()
    local l = self.game.last
    if not (l and l.kind == "name") then return nil end
    if l.found then
        return T(_("“%1”: found by team %2 (+1)."), l.name, self:_teamLetter(l.team))
    end
    return T(_("“%1”: not found, team %2 scores %3."), l.name, self:_teamLetter(l.scorer), l.points)
end

function PyramidScreen:_buildBid()
    local g = self.game
    local th = g.st.theme
    local item = g:themeItem()
    local bidder, owner = g:bidder(), th.owner
    local rows = {
        { self:_bigButton(T(_("No bid: team %1 plays in %2"), self:_teamLetter(owner), g.name_bricks),
            function() self:onBid(nil) end, nil, 1.2) },
    }
    local bids = {}
    for n = g.name_bricks - 1, 1, -1 do
        bids[#bids + 1] = self:_bigButton(T(n == 1 and _("%1 brick") or _("%1 bricks"), n),
            function() self:onBid(n) end, nil, 1.1)
    end
    if self:isLandscape() then
        -- The side panel is too narrow for the bids on one row.
        for _i, b in ipairs(bids) do rows[#rows + 1] = { b } end
    else
        rows[2] = bids
    end
    local title_bar = self:_titleBar()
    local controls = self:_controls(rows)
    local bw, bh = self:getBoardBudget(title_bar, controls)
    local short = math.min(bw, bh)
    local vs = Size.span.vertical_large
    local items = {}
    local last = self:_lastNameText()
    if last then items[#items + 1] = para(last, Font:getFace("infofont"), bw) end
    items[#items + 1] = W.fitLine(T(_("Theme: %1"), item.t), short * 0.065, bw, true)
    items[#items + 1] = W.fitLine(T(_("Name %1 of %2"), th.idx, Game.NAMES_PER_THEME), short * 0.06, bw)
    items[#items + 1] = W.fitLine(T(_("%1, do you bid?"), self:_team(bidder)), short * 0.08, bw, true)
    items[#items + 1] = para(T(_("Team %1 plays this name in %2 bricks at most. Bid fewer bricks to take it over: found, you score; missed, team %1 scores."),
        self:_teamLetter(owner), g.name_bricks), Font:getFace("smallinfofont"), math.floor(bw * 0.95))
    self:_place(title_bar, self:_withScores(items, bw, bh, vs), controls)
end

-- Neutral screen before every turn: no word visible until Ready is tapped.
function PyramidScreen:_buildHandover()
    local g = self.game
    local p = g.play
    local title_bar = self:_titleBar()
    local controls = self:_controls({ self:_bigButton(_("Ready"), function() self:onReady() end, nil, 1.4) })
    local bw, bh = self:getBoardBudget(title_bar, controls)
    local short = math.min(bw, bh)
    local vs = Size.span.vertical_large
    local info = Font:getFace("infofont")
    local small = Font:getFace("smallinfofont")
    local items = {}
    if p.kind == "pingpong" or p.kind == "sudden" then
        local _g1, r1 = g:roles(1)
        local _g2, r2 = g:roles(2)
        local givers = p.givers
        if p.kind == "sudden" then
            items[#items + 1] = W.fitLine(_("Sudden death"), short * 0.1, bw, true)
            items[#items + 1] = para(_("A tie! One name decides who plays the final."), info, bw)
        else
            items[#items + 1] = W.fitLine(self:_stageTitle(), short * 0.08, bw, true)
            items[#items + 1] = W.fitLine(T(_("Word %1 of %2"), p.pos, Game.PP_WORDS), short * 0.06, bw)
        end
        items[#items + 1] = W.fitLine(T(_("Clue-givers: %1 and %2"), self:_name(givers[1]), self:_name(givers[2])),
            short * 0.065, bw, true)
        items[#items + 1] = W.fitLine(self:_lookAway(T(_("%1 and %2"), self:_name(r1), self:_name(r2))),
            short * 0.065, bw, true)
        items[#items + 1] = para(T(_("Both clue-givers see the word; the teams take turns, one clue each. %1 starts."),
            self:_team(p.active)), small, math.floor(bw * 0.92))
    else
        local head = self:_stageTitle()
        local item_line
        if p.kind == "riddles" then
            item_line = "« " .. p.item.t .. " »"
            if _.lang() ~= "fr" then item_line = "“" .. p.item.t .. "”" end
        elseif p.kind == "clock" then
            item_line = T(_("Theme: %1"), p.item.t)
        elseif p.kind == "names" then
            item_line = T(_("Theme: %1"), g:themeItem().t)
        end
        items[#items + 1] = W.fitLine(head, short * 0.065, bw)
        items[#items + 1] = W.fitLine(self:_team(p.team), short * 0.09, bw, true)
        if item_line then items[#items + 1] = para(item_line, Font:getFace("tfont"), bw) end
        items[#items + 1] = W.fitLine(T(_("Clue-giver: %1"), self:_name(p.giver)), short * 0.075, bw, true)
        items[#items + 1] = W.fitLine(T(_("Guesser: %1 — look away!"), self:_name(p.guesser)), short * 0.06, bw)
        local how
        if p.kind == "riddles" then
            how = T(_("Word %1 of 5 · %2 bricks left."), math.min(p.pos, Game.RIDDLE_WORDS), p.bricks)
        elseif p.kind == "clock" then
            how = _("30 seconds, up to 7 words.")
        else
            how = T(_("Name %1 of %2 · %3 bricks at most."), g.st.theme.idx, Game.NAMES_PER_THEME, p.limit)
        end
        items[#items + 1] = para(how .. " " .. T(_("Hold the reader so only %1 sees it, then tap Ready."),
            self:_name(p.giver)), small, math.floor(bw * 0.92))
    end
    self:_place(title_bar, self:_withScores(items, bw, bh, vs), controls)
end

function PyramidScreen:_buildTurn()
    local g = self.game
    local p = g.play
    local land = self:isLandscape()
    local word = g:currentWord()
    if p.kind == "riddles" then
        local header = self:_turnHeader(nil,
            T(_("Team %1"), self:_teamLetter(p.team)) .. " · " .. T(_("%1 → %2"), self:_name(p.giver), self:_name(p.guesser)),
            p.bricks, Game.RIDDLE_BRICKS)
        local label = "« " .. p.item.t .. " »"
        if _.lang() ~= "fr" then label = "“" .. p.item.t .. "”" end
        self:_turnLayout(header, word, T(_("Word %1 of %2"), p.pos, Game.RIDDLE_WORDS), self:_clueRows(), label)
    elseif p.kind == "pingpong" or p.kind == "sudden" then
        local _gv, guesser = g:roles(p.active)
        local banner = W.banner(self:_team(p.active) .. " · " .. T(_("%1 → %2"), self:_name(p.givers[p.active]),
            self:_name(guesser)), math.floor(self:_timerPx() * 0.5), self:_headerWidth())
        local header, sub
        local rows
        if p.kind == "pingpong" then
            header = self:_turnHeader(banner, T(_("This word: %1/%2 bricks"), p.word_bricks, Game.PP_MAX_PER_WORD),
                p.bricks, Game.PP_BRICKS)
            sub = T(_("Word %1 of %2"), p.pos, Game.PP_WORDS)
            rows = self:_clueRows()
        else
            header = self:_turnHeader(banner, _("Sudden death"))
            rows = self:_clueRows()
            rows[3] = { rows[3][1], self:_bigButton("⟳ " .. _("Other name"), function() self:onOtherName() end) }
        end
        local label
        local l = g.last
        if p.kind == "pingpong" and l and (l.kind == "pp_found" or l.kind == "pp_lost" or l.kind == "pp_forbidden") then
            label = l.kind == "pp_found" and T(_("Last word: %1 (team %2)"), l.word, self:_teamLetter(l.team))
                or T(_("Last word: %1 (lost)"), l.word)
        end
        self:_turnLayout(header, word, sub, rows, label)
    elseif p.kind == "clock" then
        local header = self:_turnHeader(self:_timer(self:_timerPx()),
            T(_("Theme: %1"), p.item.t))
        local pass = self:_bigButton("→ " .. _("Pass"), function() self:onPass() end, { enabled = g:canPass() })
        local forbidden = self:_bigButton("✗ " .. _("Forbidden!"), function() self:onForbidden() end)
        local undo = self:_bigButton("↶ " .. _("Undo"), function() self:onUndo() end, { enabled = g:canUndo() })
        local found = self:_bigButton("✓ " .. _("Found"), function() self:onFound() end, nil, 1.6)
        local rows = land and { { found }, { forbidden }, { pass, undo } } or { { found }, { pass, forbidden, undo } }
        self:_turnLayout(header, word, T(_("Found: %1/%2"), p.found, #p.words), rows)
    else -- names
        local header = self:_turnHeader(nil,
            T(_("Theme: %1"), g:themeItem().t), p.bricks, p.limit)
        local sub = T(_("Name %1 of %2"), g.st.theme.idx, Game.NAMES_PER_THEME)
        if p.bid then sub = sub .. " · " .. T(_("Bid: %1"), p.bid) end
        self:_turnLayout(header, word, sub, self:_clueRows(),
            self:_team(p.team) .. " · " .. T(_("%1 → %2"), self:_name(p.giver), self:_name(p.guesser)))
    end
end

-- The riddle's answer: the guesser says it, the clue-giver checks.
function PyramidScreen:_buildAnswer()
    local g = self.game
    local p = g.play
    local n = g:riddleFoundCount()
    local header = self:_turnHeader(nil, T(_("Words found: %1/%2"), n, Game.RIDDLE_WORDS), p.bricks, Game.RIDDLE_BRICKS)
    local rows = {
        { self:_bigButton("✓ " .. _("Solved"), function() self:onAnswer(true) end, nil, 1.5) },
        { self:_bigButton("✗ " .. _("Not solved"), function() self:onAnswer(false) end),
          self:_bigButton("↶ " .. _("Undo"), function() self:onUndo() end, { enabled = g:canUndo() }) },
    }
    local sub = n == Game.RIDDLE_WORDS and T(_("Bonus if solved or not: +%1"), p.bricks) or _("A word was missed: no bonus.")
    self:_turnLayout(header, p.item.a, sub, rows, _("Answer to the riddle:"))
end

local function marks(list)
    local parts = {}
    for _i, r in ipairs(list) do
        parts[#parts + 1] = (r.ok and "✓\u{00A0}" or "✗\u{00A0}") .. nbsp(r.text)
    end
    return table.concat(parts, "   ")
end

function PyramidScreen:_buildResult()
    local g = self.game
    local l = g.last or {}
    local title_bar = self:_titleBar()
    local controls = self:_controls({ self:_bigButton(_("Continue"), function() self:onContinue() end, nil, 1.4) })
    local bw, bh = self:getBoardBudget(title_bar, controls)
    local short = math.min(bw, bh)
    local vs = Size.span.vertical_large
    local info = Font:getFace("infofont")
    local small = Font:getFace("smallinfofont")
    local items = { W.fitLine(self:_stageTitle(), short * 0.06, bw) }
    if l.kind == "riddle" then
        items[#items + 1] = W.fitLine(T(_("Team %1: +%2"), self:_teamLetter(l.team), l.points), short * 0.1, bw, true)
        items[#items + 1] = para(T(_("“%1” → %2"), l.title, l.answer), Font:getFace("tfont"), bw)
        local parts = { T(_("Words: %1/%2"), l.words, Game.RIDDLE_WORDS),
                        l.solved and _("Riddle solved") or _("Riddle not solved") }
        if l.bonus > 0 then parts[#parts + 1] = T(_("Brick bonus: %1"), l.bonus) end
        items[#items + 1] = para(table.concat(parts, " · "), info, bw)
        local list = {}
        for i, w in ipairs(l.list or {}) do list[i] = { text = w, ok = l.results[i] } end
        items[#items + 1] = para(marks(list), small, bw)
    elseif l.kind == "pingpong" then
        items[#items + 1] = W.fitLine(T(_("A: +%1 · B: +%2"), l.found[1], l.found[2]), short * 0.1, bw, true)
        local parts = {}
        for i = 1, l.played do
            local r = l.results[i] or {}
            parts[#parts + 1] = (r.found and ("✓\u{00A0}" .. self:_teamLetter(r.team) .. "\u{00A0}") or "✗\u{00A0}")
                .. nbsp(l.words[i])
        end
        items[#items + 1] = para(table.concat(parts, "   "), info, bw)
    elseif l.kind == "clock" then
        items[#items + 1] = W.fitLine(T(_("Team %1: +%2"), self:_teamLetter(l.team), l.points), short * 0.1, bw, true)
        items[#items + 1] = para(T(_("Theme: %1"), l.title), Font:getFace("tfont"), bw)
        local list = {}
        for i, r in ipairs(l.results) do list[i] = { text = r.word, ok = r.found } end
        items[#items + 1] = para(marks(list), small, bw)
    elseif l.kind == "name" then
        local th = g.st.theme
        items[#items + 1] = W.fitLine(_("Theme over"), short * 0.09, bw, true)
        items[#items + 1] = para(T(_("Theme: %1"), g:themeItem().t), Font:getFace("tfont"), bw)
        local parts = {}
        for _i, r in ipairs(th.results) do
            parts[#parts + 1] = (r.found and "✓\u{00A0}" or "✗\u{00A0}") .. nbsp(r.name) .. "\u{00A0}→\u{00A0}"
                .. self:_teamLetter(r.scorer) .. "\u{00A0}+" .. r.points
        end
        items[#items + 1] = para(table.concat(parts, "   "), info, bw)
    end
    self:_place(title_bar, self:_withScores(items, bw, bh, vs), controls)
end

-- The 6 boxes: found / current / still to do (all shown once it's over).
function PyramidScreen:_pyramidBoxes(reveal)
    local f = self.game.final
    local boxes = {}
    local cur = self.game:finalCurrent()
    for i = 1, Game.FINAL_COUNT do
        local b = { state = "todo" }
        if f and f.exprs then
            if f.done and f.done[i] then
                -- During the minute a tick is enough; the texts come at the end.
                b = { state = "found", text = reveal and f.exprs[i] or nil }
            elseif reveal then
                b = { state = "missed", text = f.exprs[i] }
            elseif i == cur then
                b = { state = "current" }
            end
        end
        boxes[i] = b
    end
    return boxes
end

function PyramidScreen:_buildFinalHandover()
    local g = self.game
    local f = g.final
    local title_bar = self:_titleBar()
    local controls = self:_controls({
        { self:_bigButton(_("Ready"), function() self:onFinalReady() end, nil, 1.4) },
        { self:_bigButton("⇄ " .. _("Swap roles"), function() self:onSwapRoles() end) },
    })
    local bw, bh = self:getBoardBudget(title_bar, controls)
    local short = math.min(bw, bh)
    local vs = Size.span.vertical_large
    local items = {}
    local l = g.last
    if l and l.kind == "sudden" then
        items[#items + 1] = para(l.reason == "found"
            and T(_("Sudden death: team %1 found “%2”."), self:_teamLetter(l.team), l.name)
            or T(_("Sudden death: forbidden clue on “%1”, team %2 goes through."), l.name, self:_teamLetter(l.team)),
            Font:getFace("infofont"), bw)
    end
    items[#items + 1] = W.fitLine(_("The Great Pyramid"), short * 0.09, bw, true)
    items[#items + 1] = W.fitLine(self:_team(f.team) .. " · " .. self:_teamName(f.team), short * 0.055, bw)
    items[#items + 1] = W.fitLine(T(_("Clue-giver: %1"), self:_name(f.giver)), short * 0.07, bw, true)
    items[#items + 1] = W.fitLine(T(_("Guesser: %1 — look away!"), self:_name(f.guesser)), short * 0.06, bw)
    items[#items + 1] = para(T(_("6 expressions in 1 minute, word by word or as a whole. All or nothing: %1."), self:_prize()),
        Font:getFace("smallinfofont"), math.floor(bw * 0.92))
    local top = stack(items, vs * 2)
    local pyr_h = math.min(bh - top:getSize().h - 4 * vs, short * 0.55)
    local boxes = {}
    for i = 1, 6 do boxes[i] = { state = "todo" } end
    self:_place(title_bar, stack({ top, W.pyramid6(boxes, math.floor(math.min(bw, pyr_h * 1.6)), pyr_h) }, vs * 3), controls)
end

function PyramidScreen:_buildFinalTurn()
    local g = self.game
    local land = self:isLandscape()
    local header = self:_turnHeader(self:_timer(self:_timerPx()),
        T(_("Found: %1/%2"), g:finalFoundCount(), Game.FINAL_COUNT) .. " · " .. self:_prize())
    local found = self:_bigButton("✓ " .. _("Found"), function() self:onFinalFound() end, nil, 1.3)
    local pass = self:_bigButton("→ " .. _("Pass"), function() self:onFinalPass() end, { enabled = g:canFinalPass() })
    local forbidden = self:_bigButton("✗ " .. _("Forbidden!"), function() self:onFinalForbidden() end)
    local undo = self:_bigButton("↶ " .. _("Undo"), function() self:onFinalUndo() end, { enabled = g:canFinalUndo() })
    local rows = land and { { found }, { forbidden }, { pass, undo } } or { { found }, { pass, forbidden, undo } }
    local f = g.final
    self:_turnLayout(header, f.exprs[g:finalCurrent()], nil, rows, nil, function(w, h)
        return W.pyramid6(self:_pyramidBoxes(false), w, h)
    end)
end

function PyramidScreen:_buildGameOver()
    local g = self.game
    local f = g.final
    local o = f.outcome or { kind = "time", found = 0 }
    local title_bar = self:_titleBar()
    local controls = self:_controls({ self:_bigButton(_("New game"), function() self:onNewGame() end) })
    local bw, bh = self:getBoardBudget(title_bar, controls)
    local short = math.min(bw, bh)
    local vs = Size.span.vertical_large
    local head, line
    if o.kind == "won" then
        head = T(_("Jackpot: %1!"), self:_prize())
        line = _("The Great Pyramid is complete. Bravo!")
    else
        head = _("The pyramid stays unfinished")
        line = o.kind == "forbidden"
            and T(_("Forbidden clue with %1 of 6 expressions found: all or nothing!"), o.found)
            or T(_("Time's up with %1 of 6 expressions found."), o.found)
    end
    local items = {
        W.fitLine(head, short * 0.085, bw, true),
        para(self:_team(f.team) .. " · " .. self:_teamName(f.team) .. " · " .. line, Font:getFace("infofont"), bw),
        W.fitLine(T(_("Final score: A %1 · B %2"), g.score[1], g.score[2]), short * 0.05, bw),
    }
    local top = stack(items, vs * 2)
    local pyr_h = math.min(bh - top:getSize().h - 4 * vs, short * 0.6)
    local pyr = f.exprs and W.pyramid6(self:_pyramidBoxes(true), bw, pyr_h)
    self:_place(title_bar, pyr and stack({ top, pyr }, vs * 3) or top, controls)
end

function PyramidScreen:updateStatus(msg)
    if msg then ScreenBase.updateStatus(self, msg); return end
    local g = self.game
    local ph = g.phase
    local p = g.play
    local scores = self:joinStatus(T(_("Team %1: %2"), "A", g.score[1]), T(_("Team %1: %2"), "B", g.score[2]))
    local s
    if ph == "turn" and p then
        if p.kind == "riddles" then
            s = self:joinStatus(T(_("Bricks: %1"), p.bricks), scores)
        elseif p.kind == "pingpong" then
            s = self:joinStatus(T(_("Bricks: %1"), p.bricks), scores)
        elseif p.kind == "clock" then
            s = self:joinStatus(T(_("Words left: %1"), #p.queue), T(_("Words found: %1"), p.found))
        elseif p.kind == "names" then
            s = self:joinStatus(T(_("Bricks: %1/%2"), p.bricks, p.limit), scores)
        else
            s = scores
        end
    elseif ph == "final_turn" then
        local f = g.final
        s = self:joinStatus(T(_("Words left: %1"), #f.queue), self:_team(f.team))
    elseif ph == "setup" then
        s = self:joinStatus(T(_("Language: %1"), self.lang:upper()), T(_("Prizes: %1"), self:_unitLabel()))
    else
        s = scores
    end
    ScreenBase.updateStatus(self, s)
end

function PyramidScreen:closeScreen()
    self:_stopCountdown()
    ScreenBase.closeScreen(self)
end

return PyramidScreen
