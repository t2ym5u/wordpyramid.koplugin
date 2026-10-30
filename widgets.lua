-- Text helpers, the score table, the brick row and the Great Pyramid for the Word Pyramid screen.

local Device          = require("device")
local Font            = require("ui/font")
local Geom            = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local LeftContainer   = require("ui/widget/container/leftcontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local TextBoxWidget   = require("ui/widget/textboxwidget")
local TextWidget      = require("ui/widget/textwidget")
local VerticalGroup   = require("ui/widget/verticalgroup")
local LineWidget      = require("ui/widget/linewidget")
local Blitbuffer      = require("ffi/blitbuffer")
local Size            = require("ui/size")
local FrameContainer  = require("ui/widget/container/framecontainer")
local VerticalSpan    = require("ui/widget/verticalspan")
local HorizontalSpan  = require("ui/widget/horizontalspan")

local DeviceScreen = Device.screen

-- Font:getFace() scales by DPI: pixel-derived sizes are divided back first.
local DPI_SCALE = DeviceScreen:scaleBySize(1000) / 1000

local W = {}

function W.pxFace(px, bold)
    return Font:getFace(bold and "tfont" or "cfont", math.max(8, math.floor(px / DPI_SCALE)))
end

-- One line at up to px, shrunk until it fits max_w.
function W.fitLine(text, px, max_w, bold, fgcolor)
    local tw
    fgcolor = fgcolor or Blitbuffer.COLOR_BLACK
    while true do
        tw = TextWidget:new{ text = text, face = W.pxFace(px, bold), bold = bold, fgcolor = fgcolor }
        if tw:getSize().w <= max_w or px <= 12 then break end
        tw:free()
        px = math.floor(px * 0.9)
    end
    if tw:getSize().w > max_w then
        tw:free()
        tw = TextWidget:new{ text = text, face = W.pxFace(px, bold), bold = bold, fgcolor = fgcolor,
                             max_width = max_w }
    end
    return tw
end

-- A centred paragraph as big as possible (<= max_px) inside width x max_h,
-- without splitting a word across lines.
function W.fitParagraph(text, max_px, width, max_h, bold, fgcolor, bgcolor)
    local px = max_px
    while true do
        local face = W.pxFace(px, bold)
        local words_fit = true
        for word in text:gmatch("%S+") do
            local tw = TextWidget:new{ text = word, face = face, bold = bold }
            local w = tw:getSize().w
            tw:free()
            if w > width then words_fit = false; break end
        end
        if words_fit or px <= 12 then
            local tb = TextBoxWidget:new{ text = text, face = face, bold = bold, width = width,
                                          alignment = "center", fgcolor = fgcolor,
                                          bgcolor = bgcolor }
            if tb:getSize().h <= max_h or px <= 12 then return tb end
            tb:free()
        end
        px = math.floor(px * 0.9)
    end
end

-- Score table: one row per team, one column per round played, then total.
-- rows: { { name, s1, s2, s3, total, bold } }, headers: { "", "1", "2", "3", "Total" }
function W.scoreTable(headers, rows, width, max_h)
    local n = #rows + 1
    local row_h = math.floor(math.min(max_h / n, width * 0.12))
    local px = math.max(14, math.floor(row_h * 0.45))
    local ncols = #headers - 1
    local name_w = math.floor(width * (ncols > 2 and 0.42 or 0.6))
    local col_w = math.floor((width - name_w) / ncols)
    local function row(cells, bold_last, bold_all)
        local hg = HorizontalGroup:new{
            align = "center",
            LeftContainer:new{ dimen = Geom:new{ w = name_w, h = row_h },
                W.fitLine(cells[1], px, name_w - Size.padding.default, true) },
        }
        for i = 2, #cells do
            local bold = bold_all or (bold_last and i == #cells)
            hg[#hg + 1] = CenterContainer:new{ dimen = Geom:new{ w = col_w, h = row_h },
                W.fitLine(tostring(cells[i]), px, col_w - Size.padding.small, bold) }
        end
        return hg
    end
    local g = VerticalGroup:new{ align = "left", row(headers, false, true),
        LineWidget:new{ background = Blitbuffer.COLOR_GRAY,
                        dimen = Geom:new{ w = width, h = Size.line.medium } } }
    for _, r in ipairs(rows) do g[#g + 1] = row(r, true) end
    return g
end


-- A black banner with white text (which team gives the clue).
function W.banner(text, px, width)
    local tw = W.fitLine(text, px, width - 2 * Size.padding.large, true, Blitbuffer.COLOR_WHITE)
    return FrameContainer:new{
        bordersize = 0, padding = 0, margin = 0, radius = Size.radius.window,
        background = Blitbuffer.COLOR_BLACK,
        CenterContainer:new{ dimen = Geom:new{ w = width, h = tw:getSize().h + 2 * Size.padding.default }, tw },
    }
end

-- The bricks still available: black ones left, outlined ones spent.
function W.bricks(left, total, width, max_h)
    local gap = math.max(2, math.floor(Size.padding.small / 2))
    local bw = math.floor((width - gap * (total - 1)) / total)
    bw = math.min(bw, math.floor(max_h * 2.5))
    local bh = math.max(6, math.min(max_h, math.floor(bw * 0.6)))
    local g = HorizontalGroup:new{ align = "center" }
    for i = 1, total do
        if i > 1 then g[#g + 1] = HorizontalSpan:new{ width = gap } end
        local full = i <= left
        g[#g + 1] = FrameContainer:new{
            bordersize = Size.border.thin, padding = 0, margin = 0,
            background = full and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_WHITE,
            color = full and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_DARK_GRAY,
            CenterContainer:new{ dimen = Geom:new{ w = bw - 2 * Size.border.thin, h = bh - 2 * Size.border.thin },
                                 VerticalSpan:new{ width = 0 } },
        }
    end
    return g
end

-- The Great Pyramid: 6 boxes, 3 at the bottom, 2 above, 1 on top. boxes[i]
-- = { text, state } with state "todo" | "current" | "found" | "missed";
-- boxes 1-3 are the bottom row, 4-5 the middle, 6 the top.
function W.pyramid6(boxes, width, max_h)
    local gap = Size.padding.default
    local box_w = math.floor((width - 2 * gap) / 3)
    local box_h = math.floor(math.min((max_h - 2 * gap) / 3, box_w * 0.62))
    local px = math.max(12, math.floor(box_h * 0.28))
    local function box(i)
        local b = boxes[i] or { state = "todo" }
        local current = b.state == "current"
        local fg = current and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK
        local inner_w = box_w - 2 * (Size.border.thick + Size.padding.small)
        local inner_h = box_h - 2 * (Size.border.thick + Size.padding.small)
        local bg = current and Blitbuffer.COLOR_BLACK
            or (b.state == "found" and Blitbuffer.COLOR_LIGHT_GRAY) or Blitbuffer.COLOR_WHITE
        local text = b.text or ""
        if text ~= "" then
            if b.state == "found" then text = "✓ " .. text elseif b.state == "missed" then text = "✗ " .. text end
        end
        local inner
        if text == "" then
            -- No text: the box number, or a big tick for a found box.
            local found = b.state == "found"
            inner = W.fitLine(found and "✓" or tostring(i), math.floor(box_h * (found and 0.6 or 0.4)), inner_w,
                              true, found and Blitbuffer.COLOR_BLACK or (current and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_GRAY))
        else
            inner = W.fitParagraph(text, px, inner_w, inner_h, current or b.state == "found", fg, bg)
        end
        return FrameContainer:new{
            bordersize = b.state == "todo" and Size.border.default or Size.border.thick,
            padding = Size.padding.small, margin = 0, radius = Size.radius.default,
            background = bg,
            CenterContainer:new{ dimen = Geom:new{ w = inner_w, h = inner_h }, inner },
        }
    end
    local function row(ids)
        local hg = HorizontalGroup:new{ align = "center" }
        for k, i in ipairs(ids) do
            if k > 1 then hg[#hg + 1] = HorizontalSpan:new{ width = gap } end
            hg[#hg + 1] = box(i)
        end
        return hg
    end
    return VerticalGroup:new{
        align = "center",
        row({ 6 }), VerticalSpan:new{ width = gap },
        row({ 4, 5 }), VerticalSpan:new{ width = gap },
        row({ 1, 2, 3 }),
    }
end

return W
