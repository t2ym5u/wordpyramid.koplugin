-- Family-friendly words: Word Pyramid is played around a family table, so no
-- word, clue or answer of its content packs may be vulgar, sexual,
-- scatological, a slur or drug-related. Whole words only, accent-stripped.
local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"

local function strip_accents(s)
    local map = {
        ["à"]="a", ["â"]="a", ["ä"]="a", ["ç"]="c", ["é"]="e", ["è"]="e",
        ["ê"]="e", ["ë"]="e", ["î"]="i", ["ï"]="i", ["ô"]="o", ["ö"]="o",
        ["ù"]="u", ["û"]="u", ["ü"]="u", ["ÿ"]="y", ["œ"]="oe", ["æ"]="ae",
    }
    return (s:lower():gsub("[\194-\244][\128-\191]*", function(c)
        return map[c] or c
    end))
end

-- One list per language: BITE is fine in English.
local BLOCKED = { fr = {}, en = {} }
for w in ([[
    caca pipi prout crotte zizi bite merde putain pute salope salaud connard
    cons couille enfoire enfoires encule branle tapette nichons sperme sexe
    porno orgasme vagin penis viol drogue cocaine
]]):gmatch("%a+") do BLOCKED.fr[w] = true end
for w in ([[
    shit fuck crap damn piss cunt cock dick bitch whore slut porn sexy sex
    penis vagina rape cocaine heroin poop turd
]]):gmatch("%a+") do BLOCKED.en[w] = true end

-- "Moby Dick" and "Dick Turpin" are a whale and a highwayman.
local ALLOWED_PHRASES = { ["moby dick"] = true, ["dick turpin"] = true }

local function strings(v, out)
    if type(v) == "string" then out[#out + 1] = v
    elseif type(v) == "table" then for _, x in pairs(v) do strings(x, out) end end
    return out
end

describe("family-friendly content packs", function()
    for _, lang in ipairs({ "en", "fr" }) do
        for _, pack in ipairs({ "clock", "names", "pyramid", "riddles", "words" }) do
            it(lang .. "/" .. pack .. " has no blocked word", function()
                local all = strings(dofile(DIR .. "content/" .. lang .. "/" .. pack .. ".lua"), {})
                assert.is_true(#all > 50)
                for _, s in ipairs(all) do
                    local t = strip_accents(s)
                    if not ALLOWED_PHRASES[t] then
                        for w in t:gmatch("[%a\128-\255]+") do
                            assert.is_nil(BLOCKED[lang][w], s)
                        end
                    end
                end
            end)
        end
    end
end)
