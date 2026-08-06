describe("Optimized justification of short paragraphs", function()
    local DocumentRegistry
    local fixture = "/tmp/koreader-optimized-short-paragraph.html"

    setup(function()
        require("commonrequire")
        DocumentRegistry = require("document/documentregistry")
    end)

    before_each(function()
        local words = {
            "A", "short", "sentence", "should", "wrap", "naturally", "without",
            "distorting", "the", "spaces", "between", "its", "ordinary", "words."
        }
        local file = assert(io.open(fixture, "wb"))
        file:write([[<!doctype html><html><head><meta charset="utf-8"><style>
body { font-family: serif; margin: 0; }
p { text-align: justify; hyphens: none; margin: 0; }
</style></head><body><p>]])
        for i, word in ipairs(words) do
            if i > 1 then file:write(" ") end
            file:write(string.format('<span id="w%d">%s</span>', i, word))
        end
        file:write("</p></body></html>")
        file:close()
    end)

    local function positions(width, ending_minimum)
        local doc = assert(DocumentRegistry:openDocument(fixture))
        doc:setupDefaultView()
        doc:setViewMode("page")
        doc:setViewDimen({ w = width, h = 610 })
        doc:setFontSize(28)
        doc._document:setIntProperty("crengine.style.line.breaking.mode", 1)
        doc._document:setIntProperty(
            "crengine.style.justify.last.line.min.percent", ending_minimum)
        doc:render()
        local result = {}
        for i = 1, 14 do
            local y, x = doc:getPosFromXPointer(string.format(
                "/html/body/p/span[%d]/text().0", i))
            result[i] = { y, x }
        end
        doc:close()
        return result
    end

    it("does not rebalance a two-line sentence to lengthen its ending", function()
        local checked = 0
        for width = 400, 900, 10 do
            local natural = positions(width, 0)
            local lines = {}
            for _, pos in ipairs(natural) do lines[pos[1]] = true end
            local line_count = 0
            for _ in pairs(lines) do line_count = line_count + 1 end
            if line_count == 2 then
                local preferred = positions(width, 100)
                assert.are.same(natural, preferred, "width " .. width)
                checked = checked + 1
            end
        end
        assert.is_true(checked > 0)
    end)
end)

describe("Optimized texture-aware path search", function()
    local DocumentRegistry, KnuthPlugin
    local fixture = "/tmp/koreader-optimized-texture-search.html"
    -- Deliberately varied word lengths provide several similarly viable TeX
    -- paths. With texture transitions removed, this geometry starts its first
    -- three lines at 0, 31 and 60; the integrated 30/30/30/10 search selects
    -- the calmer sequence asserted below. Hyphenation is off, so this cannot
    -- be caused by the later unhyphenated-vs-hyphenated comparison.
    local text = "measure quiet among typography visual different width while " ..
        "consistent the river viable gradually complete distribution sequence " ..
        "intervals layout texture horizontal figures patient calm without calm " ..
        "patient figures horizontal texture layout intervals sequence distribution " ..
        "complete gradually viable river the consistent while width different " ..
        "visual typography among quiet measure quiet."

    setup(function()
        require("commonrequire")
        DocumentRegistry = require("document/documentregistry")
        KnuthPlugin = dofile("plugins/knuthjustification.koplugin/main.lua")
        local file = assert(io.open(fixture, "wb"))
        file:write([[<!doctype html><html lang="en"><head><meta charset="utf-8"><style>
body { font-family: serif; margin: 0; }
p { text-align: justify; text-indent: 1.2em; hyphens: none; margin: 0; }
</style></head><body><p>]])
        file:write(text)
        file:write("</p></body></html>")
        file:close()
    end)

    it("lets texture transitions steer interior Knuth paths", function()
        local doc = assert(DocumentRegistry:openDocument(fixture))
        doc:setupDefaultView()
        doc:setViewMode("page")
        doc:setViewDimen({ w = 430, h = 800 })
        doc:setFontSize(23)
        doc._document:setIntProperty("font.kerning.mode", 3)
        doc._document:setIntProperty(
            "crengine.style.line.breaking.mode", 1)
        doc._document:setIntProperty(
            "crengine.style.justify.space.shrink.percent", 25)
        doc._document:setIntProperty(
            "crengine.style.justify.space.stretch.percent", 25)
        doc._document:setIntProperty(
            "crengine.style.justify.tracking.shrink.percent", 1)
        doc._document:setIntProperty(
            "crengine.style.justify.tracking.stretch.percent", 1)
        doc._document:setIntProperty(
            "crengine.style.justify.pretolerance", 500)
        doc._document:setIntProperty(
            "crengine.style.justify.tolerance", 500)
        doc._document:setIntProperty(
            "crengine.style.justify.last.line.min.percent", 0)
        doc:render()

        local signature = {}
        local last_y
        for offset = 0, #text - 1 do
            local y = doc:getPosFromXPointer(
                "/html/body/p/text()." .. offset)
            if y ~= last_y then
                signature[#signature + 1] = offset
                last_y = y
            end
        end
        doc:close()
        assert.are.same(
            { 0, 31, 71, 107, 146, 181, 215, 251, 282, 320, 349, 380 },
            signature)
    end)

    it("switches a live page between Fast, Hybrid and Best from the top plugin", function()
        local doc = assert(DocumentRegistry:openDocument(fixture))
        doc:setupDefaultView()
        doc:setViewMode("page")
        doc:setViewDimen({ w = 430, h = 800 })
        doc:setFontSize(23)
        doc._document:setIntProperty("font.kerning.mode", 3)
        doc.configurable = doc.configurable or {}
        doc:render()

        local saved = {}
        local config = {
            readSetting = function(_, name) return saved[name] end,
            saveSetting = function(_, name, value) saved[name] = value end,
        }
        local ui = {
            rolling = {},
            document = doc,
            doc_settings = config,
            menu = { registerToMainMenu = function() end },
            handleEvent = function()
                -- Match ReaderRolling:onUpdatePos(): force pending CREngine
                -- property changes to finish rendering, then discard cached
                -- XPointer geometry from the previous mode.
                doc:getCurrentPos()
                doc:resetCallCache()
            end,
        }
        local plugin = KnuthPlugin:new{ ui = ui }
        plugin:onReadSettings(config)
        doc._document:setIntProperty(
            "crengine.style.justify.space.shrink.percent", 25)
        doc._document:setIntProperty(
            "crengine.style.justify.space.stretch.percent", 25)
        doc._document:setIntProperty(
            "crengine.style.justify.tracking.shrink.percent", 1)
        doc._document:setIntProperty(
            "crengine.style.justify.tracking.stretch.percent", 1)
        doc._document:setIntProperty(
            "crengine.style.justify.pretolerance", 500)
        doc._document:setIntProperty(
            "crengine.style.justify.tolerance", 500)
        doc._document:setIntProperty(
            "crengine.style.justify.last.line.min.percent", 0)

        local function signature(mode)
            plugin:onSetLineBreakingMode(mode, true)
            local result = {}
            local last_y
            for offset = 0, #text - 1 do
                local y = doc:getPosFromXPointer(
                    "/html/body/p/text()." .. offset)
                if y ~= last_y then
                    result[#result + 1] = offset
                    last_y = y
                end
            end
            return result
        end

        local fast = signature(0)
        local hybrid = signature(2)
        local best = signature(1)
        assert.are.same(fast, hybrid,
            "Hybrid must retain the exact Fast break sequence")
        assert.are_not.same(fast, best,
            "Best must activate paragraph-wide line breaking")
        assert.are.equal(1, saved.copt_line_breaking_mode)
        doc:close()
    end)
end)

describe("Optimized positive letter spacing", function()
    local DocumentRegistry, Blitbuffer
    local fixture = "/tmp/koreader-optimized-positive-tracking.html"

    setup(function()
        require("commonrequire")
        DocumentRegistry = require("document/documentregistry")
        Blitbuffer = require("ffi/blitbuffer")
        local file = assert(io.open(fixture, "wb"))
        file:write([[<!doctype html><html lang="en"><head><meta charset="utf-8"><style>
body { font-family: serif; margin: 0; }
p { text-align: justify; hyphens: none; margin: 0; }
</style></head><body><p><span>Microtypography</span> can distribute a small
positive remainder between letters while preserving equal word spaces across
the complete paragraph and selecting calm line endings for representative
prose in this rendering regression.</p></body></html>]])
        file:close()
    end)

    local function firstWordSpan(mode, max_positive)
        local doc = assert(DocumentRegistry:openDocument(fixture))
        doc:setupDefaultView()
        doc:setViewMode("page")
        doc:setViewDimen({ w = 500, h = 610 })
        doc:setFontSize(28)
        doc._document:setIntProperty("font.kerning.mode", 3)
        doc._document:setIntProperty(
            "crengine.style.line.breaking.mode", mode)
        doc._document:setIntProperty(
            "crengine.style.justify.space.shrink.percent", 0)
        doc._document:setIntProperty(
            "crengine.style.justify.space.stretch.percent", 0)
        doc._document:setIntProperty(
            "crengine.style.justify.tracking.shrink.percent", 0)
        doc._document:setIntProperty(
            "crengine.style.justify.tracking.stretch.percent", max_positive)
        doc._document:setIntProperty(
            "crengine.style.justify.tracking.delta.max.bp", 0)
        doc._document:setIntProperty(
            "crengine.style.justify.tolerance", 10000)
        doc._document:setIntProperty(
            "crengine.style.justify.emergency.stretch.percent", 100)
        doc:render()

        local y0, x0 = doc:getScreenPositionFromXPointer(
            "/html/body/p/span[1]/text().0")
        local y1, x1 = doc:getScreenPositionFromXPointer(
            "/html/body/p/span[1]/text().13")
        local next_y, next_x = doc:getScreenPositionFromXPointer(
            "/html/body/p/text().1")
        assert.are.equal(y0, y1)
        assert.are.equal(y0, next_y)

        local bb = Blitbuffer.new(500, 610)
        bb:fill(Blitbuffer.COLOR_WHITE)
        doc:drawCurrentView(bb, 0, 0,
            { x = 0, y = 0, w = 500, h = 610 })
        local ink_end = x0
        for y = y0, y0 + 39 do
            for x = x0, next_x - 1 do
                if bb:getPixel(x, y):getColor8().a < 128 then
                    ink_end = math.max(ink_end, x)
                end
            end
        end
        bb:free()
        doc:close()
        return { x1 - x0, next_x - x0, ink_end - x0 }
    end

    it("uses Max + as actual distributed positive tracking", function()
        local without_positive = firstWordSpan(1, 0)
        local with_positive = firstWordSpan(1, 20)

        assert.is_true(with_positive[3] > without_positive[3],
            string.format(
                "tracked ink %d (%d/%d) should exceed untracked ink %d (%d/%d)",
                with_positive[3], with_positive[1], with_positive[2],
                without_positive[3], without_positive[1], without_positive[2]))
    end)

    it("uses the same distributed tracking after Hybrid Greedy breaks", function()
        local without_positive = firstWordSpan(2, 0)
        local with_positive = firstWordSpan(2, 20)

        assert.is_true(with_positive[3] > without_positive[3],
            string.format(
                "hybrid tracked ink %d should exceed untracked ink %d",
                with_positive[3], without_positive[3]))
    end)
end)

describe("Hybrid optical word spacing", function()
    local DocumentRegistry, Blitbuffer
    local fixture = "/tmp/koreader-hybrid-optical-spacing.html"
    local words = {
        "Tall", "oval", "waft", "quiet", "river", "Typography", "rests",
        "beside", "Avrana", "Kern", "while", "careful", "figures", "form",
        "another", "measured", "line", "for", "comparison."
    }
    local text = table.concat(words, " ")
    local offsets = {}

    setup(function()
        require("commonrequire")
        DocumentRegistry = require("document/documentregistry")
        Blitbuffer = require("ffi/blitbuffer")
        local offset = 0
        for index, word in ipairs(words) do
            offsets[index] = offset
            offset = offset + #word + 1
        end
        local file = assert(io.open(fixture, "wb"))
        file:write([[<!doctype html><html lang="en"><head><meta charset="utf-8"><style>
body { font-family: serif; margin: 0; }
p { text-align: justify; hyphens: none; margin: 0; }
</style></head><body><p>]])
        file:write(text)
        file:write("</p></body></html>")
        file:close()
    end)

    local function firstLineGaps(mode)
        local width, height = 560, 610
        local doc = assert(DocumentRegistry:openDocument(fixture))
        doc:setupDefaultView()
        doc:setViewMode("page")
        doc:setViewDimen({ w = width, h = height })
        doc:setFontSize(34)
        doc._document:setIntProperty("font.kerning.mode", 3)
        doc._document:setIntProperty(
            "crengine.style.line.breaking.mode", mode)
        doc._document:setIntProperty(
            "crengine.style.justify.space.shrink.percent", 33)
        doc._document:setIntProperty(
            "crengine.style.justify.space.stretch.percent", 50)
        doc._document:setIntProperty(
            "crengine.style.justify.tracking.shrink.percent", 2)
        doc._document:setIntProperty(
            "crengine.style.justify.tracking.stretch.percent", 2)
        doc:render()

        local positions = {}
        for index, word in ipairs(words) do
            local y, x = doc:getScreenPositionFromXPointer(string.format(
                "/html/body/p/text().%d", offsets[index]))
            local end_y, end_x = doc:getScreenPositionFromXPointer(
                string.format("/html/body/p/text().%d",
                    offsets[index] + #word))
            positions[index] = { y = y, x = x, end_x = end_x }
            assert.are.equal(y, end_y)
        end

        local bb = Blitbuffer.new(width, height)
        bb:fill(Blitbuffer.COLOR_WHITE)
        doc:drawCurrentView(bb, 0, 0,
            { x = 0, y = 0, w = width, h = height })
        local gaps = {}
        local first_y = positions[1].y
        for index = 1, #words - 1 do
            local current = positions[index]
            local next_word = positions[index + 1]
            if current.y ~= first_y or next_word.y ~= first_y then break end
            local boundary = math.floor((current.end_x + next_word.x) / 2)
            local right_ink = current.x
            local left_ink = next_word.end_x
            for y = first_y, first_y + 47 do
                for x = current.x - 4, boundary do
                    if bb:getPixel(x, y):getColor8().a < 128 then
                        right_ink = math.max(right_ink, x)
                    end
                end
                for x = boundary + 1, next_word.end_x + 4 do
                    if bb:getPixel(x, y):getColor8().a < 128 then
                        left_ink = math.min(left_ink, x)
                    end
                end
            end
            gaps[#gaps + 1] = left_ink - right_ink - 1
        end
        bb:free()
        doc:close()
        return gaps
    end

    local function spread(values)
        local minimum, maximum = values[1], values[1]
        for _, value in ipairs(values) do
            minimum = math.min(minimum, value)
            maximum = math.max(maximum, value)
        end
        return maximum - minimum
    end

    it("equalizes visible ink-to-ink gaps after exact Greedy breaks", function()
        local greedy = firstLineGaps(0)
        local hybrid = firstLineGaps(2)
        assert.are.equal(#greedy, #hybrid,
            "Hybrid changed the number of words on Greedy's first line")
        assert.is_true(#hybrid >= 4, "fixture has too few first-line gaps")
        assert.is_true(spread(hybrid) <= 2, string.format(
            "Hybrid visible gap spread is %d px (%s)",
            spread(hybrid), table.concat(hybrid, ", ")))
        assert.is_true(spread(hybrid) < spread(greedy), string.format(
            "Hybrid spread %d (%s) should improve Greedy spread %d (%s)",
            spread(hybrid), table.concat(hybrid, ", "),
            spread(greedy), table.concat(greedy, ", ")))
    end)
end)

describe("Optimized justification at inline style boundaries", function()
    local DocumentRegistry
    local fixture = "/tmp/koreader-optimized-italic-gap.html"

    setup(function()
        require("commonrequire")
        DocumentRegistry = require("document/documentregistry")
        local file = assert(io.open(fixture, "wb"))
        file:write([[<!doctype html><html lang="en"><head><meta charset="utf-8"><style>
body { font-family: serif; margin: 0; }
p { text-align: justify; hyphens: auto; margin: 0; }
</style></head><body><p>An inclination to play God was part and parcel of wanting
to go out and terraform other worlds, but good practice was to at least play
nicely with the rest of the pantheon. Senkovi had met Avrana Kern once—it had
been hard to avoid her—<span>and </span><em>there</em><span> was a woman who was
her own Zeus, Odin and Yahweh all in one. Baltiel's role had only ever been
intended as a subordinate Vulcan, but now he had found a new lease of divinity,
a project Kern could not reach across the abyss to dictate.</span></p></body></html>]])
        file:close()
    end)

    it("keeps the word space before italic text equal to its neighbors", function()
        local doc = assert(DocumentRegistry:openDocument(fixture))
        doc:setupDefaultView()
        doc:setViewMode("page")
        doc:setViewDimen({ w = 490, h = 610 })
        doc:setFontSize(28)
        doc._document:setIntProperty("font.kerning.mode", 3)
        doc._document:setIntProperty(
            "crengine.style.line.breaking.mode", 1)
        doc:render()

        local and_y, and_space_x = doc:getPosFromXPointer(
            "/html/body/p/span[1]/text().3")
        local there_y, there_x = doc:getPosFromXPointer(
            "/html/body/p/em[1]/text().0")
        local there_end_y, there_space_x = doc:getPosFromXPointer(
            "/html/body/p/em[1]/text().5")
        local was_y, was_x = doc:getPosFromXPointer(
            "/html/body/p/span[2]/text().1")

        assert.are.equal(and_y, there_y)
        assert.are.equal(there_y, there_end_y)
        assert.are.equal(there_end_y, was_y)
        assert.is_true(math.abs(
            (there_x - and_space_x) - (was_x - there_space_x)) <= 1)
        doc:close()
    end)
end)

describe("Greedy fallback paragraph indicator", function()
    local DocumentRegistry, Blitbuffer
    local fixture = "/tmp/koreader-optimized-fallback-marker.html"

    setup(function()
        require("commonrequire")
        DocumentRegistry = require("document/documentregistry")
        Blitbuffer = require("ffi/blitbuffer")
        local file = assert(io.open(fixture, "wb"))
        file:write([[<!doctype html><html lang="en"><head><meta charset="utf-8"><style>
body { font-family: serif; margin: 0; }
p { text-align: justify; hyphens: auto; text-indent: 40px; margin: 0 0 12px; }
.nowrap { white-space: nowrap; }
</style></head><body>
<p><span>Supported paragraph</span> breaking examines a complete paragraph and
selects calm lines with consistent spacing across representative prose while
keeping readable endings for this rendering test.</p>
<p><span class="nowrap">Unsupported paragraph</span> breaking contains one
locally nonwrapping fragment and therefore must use the safe greedy formatter
while still producing readable content.</p>
</body></html>]])
        file:close()
    end)

    it("draws one small dot only on the greedy fallback paragraph", function()
        local width, height = 500, 610
        local doc = assert(DocumentRegistry:openDocument(fixture))
        doc:setupDefaultView()
        doc:setViewMode("page")
        doc:setViewDimen({ w = width, h = height })
        doc:setFontSize(28)
        doc._document:setIntProperty("font.kerning.mode", 3)
        doc._document:setIntProperty(
            "crengine.style.line.breaking.mode", 1)
        doc:render()

        local supported_y, supported_x = doc:getScreenPositionFromXPointer(
            "/html/body/p[1]/span[1]/text().0")
        local fallback_y, fallback_x = doc:getScreenPositionFromXPointer(
            "/html/body/p[2]/span[1]/text().0")
        local bb = Blitbuffer.new(width, height)
        bb:fill(Blitbuffer.COLOR_WHITE)
        doc:drawCurrentView(bb, 0, 0,
            { x = 0, y = 0, w = width, h = height })

        local function hasMarker(text_x, line_y)
            for y = line_y, line_y + 37 do
                local solid = true
                for x = text_x - 5, text_x - 3 do
                    if bb:getPixel(x, y):getColor8().a >= 128 then
                        solid = false
                        break
                    end
                end
                if solid then return true end
            end
            return false
        end

        assert.is_false(hasMarker(supported_x, supported_y))
        assert.is_true(hasMarker(fallback_x, fallback_y))
        bb:free()
        doc:close()
    end)

    it("leaves unsupported Hybrid paragraphs on stock Greedy spacing", function()
        local function unsupportedPositions(mode)
            local doc = assert(DocumentRegistry:openDocument(fixture))
            doc:setupDefaultView()
            doc:setViewMode("page")
            doc:setViewDimen({ w = 500, h = 610 })
            doc:setFontSize(28)
            doc._document:setIntProperty("font.kerning.mode", 3)
            doc._document:setIntProperty(
                "crengine.style.line.breaking.mode", mode)
            doc._document:setIntProperty(
                "crengine.style.justify.tracking.stretch.percent", 20)
            doc:render()

            local positions = {}
            for _, offset in ipairs({ 1, 20, 50, 100 }) do
                positions[offset] = { doc:getPosFromXPointer(
                    "/html/body/p[2]/text()." .. offset) }
            end
            doc:close()
            return positions
        end

        assert.are.same(unsupportedPositions(0), unsupportedPositions(2))
    end)
end)

describe("Optimized first-line indentation", function()
    local DocumentRegistry
    local fixture = "/tmp/koreader-optimized-first-line-indent.html"
    local word_count = 18

    setup(function()
        require("commonrequire")
        DocumentRegistry = require("document/documentregistry")
        local words = {
            "Measured", "paragraph", "spacing", "should", "respect", "the",
            "shorter", "indented", "first", "line", "without", "silently",
            "using", "tighter", "letters", "than", "configured", "here."
        }
        local marked = {}
        for index, word in ipairs(words) do
            marked[index] = string.format('<span id="w%d">%s</span>', index, word)
        end
        local text = table.concat(marked, " ")
        local file = assert(io.open(fixture, "wb"))
        file:write([[<!doctype html><html lang="en"><head><meta charset="utf-8"><style>
body { font-family: serif; margin: 0; }
p { text-align: justify; hyphens: none; margin: 0 0 20px; }
.plain { text-indent: 0; }
.indented { text-indent: 60px; }
</style></head><body><p class="plain">]])
        file:write(text)
        file:write([[</p><p class="indented">]])
        file:write(text)
        file:write("</p></body></html>")
        file:close()
    end)

    local function layout(width, paragraph, tracking_shrink)
        local doc = assert(DocumentRegistry:openDocument(fixture))
        doc:setupDefaultView()
        doc:setViewMode("page")
        doc:setViewDimen({ w = width, h = 1000 })
        doc:setFontSize(28)
        doc._document:setIntProperty("font.kerning.mode", 3)
        doc._document:setIntProperty(
            "crengine.style.line.breaking.mode", 1)
        doc._document:setIntProperty(
            "crengine.style.justify.space.shrink.percent", 0)
        doc._document:setIntProperty(
            "crengine.style.justify.space.stretch.percent", 100)
        doc._document:setIntProperty(
            "crengine.style.justify.tracking.shrink.percent", tracking_shrink)
        doc._document:setIntProperty(
            "crengine.style.justify.tracking.stretch.percent", 0)
        doc._document:setIntProperty(
            "crengine.style.justify.tracking.delta.max.bp", 0)
        doc._document:setIntProperty(
            "crengine.style.justify.pretolerance", 10000)
        doc:render()

        local first_y
        local first_line_words = 0
        local lines = {}
        for index = 1, word_count do
            local y = doc:getPosFromXPointer(string.format(
                "/html/body/p[%d]/span[%d]/text().0", paragraph, index))
            first_y = first_y or y
            if y == first_y then first_line_words = first_line_words + 1 end
            lines[y] = true
        end
        local line_count = 0
        for _ in pairs(lines) do line_count = line_count + 1 end
        doc:close()
        return first_line_words, line_count
    end

    it("subtracts text-indent from the first Knuth line measure", function()
        local found_reduced_first_line = false
        for width = 420, 620, 10 do
            local plain_words, plain_lines = layout(width, 1, 0)
            local indented_words, indented_lines = layout(width, 2, 0)
            if plain_lines == indented_lines and
                    indented_words < plain_words then
                found_reduced_first_line = true
                break
            end
        end
        assert.is_true(found_reduced_first_line,
            "text-indent never reduced the optimized first-line measure")
    end)

    it("does not promote Max - 1% to 2% on an indented first line", function()
        local one_percent, one_lines = layout(994, 2, 1)
        local two_percent, two_lines = layout(994, 2, 2)

        assert.are.equal(2, one_lines)
        assert.are.equal(2, two_lines)
        assert.are.equal(8, one_percent)
        assert.are.equal(9, two_percent)
    end)
end)

describe("Optimized first-line spacing guide", function()
    local DocumentRegistry
    local fixture = "/tmp/koreader-optimized-first-line-guide.html"
    local text = "Nothing in the figures was dramatic. Each deviation was small enough to dismiss on its own, yet together they formed a patient sequence. She adjusted the focus, waited for the mount to become still, and began another reading before the air above the valley could change."

    setup(function()
        require("commonrequire")
        DocumentRegistry = require("document/documentregistry")
        local file = assert(io.open(fixture, "wb"))
        file:write([[<!doctype html><html lang="en"><head><meta charset="utf-8"><style>
body { font-family: serif; margin: 34px 38px; }
p { text-align: justify; text-indent: 1.5em; line-height: 1.34;
    hyphens: auto; margin: 0; }
</style></head><body><p>]])
        file:write(text)
        file:write("</p></body></html>")
        file:close()
    end)

    local function lineSignature(hyphen_penalty, repeated_penalty, mode)
        local doc = assert(DocumentRegistry:openDocument(fixture))
        doc:setupDefaultView()
        doc:setViewMode("page")
        doc:setViewDimen({ w = 600, h = 800 })
        doc:setFontSize(23)
        doc._document:setIntProperty("font.kerning.mode", 3)
        doc._document:setIntProperty(
            "crengine.style.line.breaking.mode", mode or 1)
        doc._document:setIntProperty(
            "crengine.style.justify.space.shrink.percent", 34)
        doc._document:setIntProperty(
            "crengine.style.justify.space.stretch.percent", 25)
        doc._document:setIntProperty(
            "crengine.style.justify.tracking.shrink.percent", 1)
        doc._document:setIntProperty(
            "crengine.style.justify.tracking.stretch.percent", 1)
        doc._document:setIntProperty(
            "crengine.style.justify.tracking.delta.max.bp", 50)
        doc._document:setIntProperty(
            "crengine.style.justify.pretolerance", 50)
        doc._document:setIntProperty(
            "crengine.style.justify.tolerance", 500)
        doc._document:setIntProperty(
            "crengine.style.justify.last.line.min.percent", 33)
        doc._document:setIntProperty(
            "crengine.style.justify.hyphen.penalty", hyphen_penalty)
        doc._document:setIntProperty(
            "crengine.style.justify.explicit.hyphen.penalty", hyphen_penalty)
        doc._document:setIntProperty(
            "crengine.style.justify.double.hyphen.demerits", repeated_penalty)
        doc._document:setIntProperty(
            "crengine.style.justify.final.hyphen.demerits", repeated_penalty)
        doc:render()

        local signature = {}
        local last_y
        for offset = 0, #text - 1 do
            local y = doc:getPosFromXPointer(
                "/html/body/p/text()." .. offset)
            if y ~= last_y then
                table.insert(signature, offset)
                last_y = y
            end
        end
        doc:close()
        return signature
    end

    it("keeps Each on the indented first line at 10 pt geometry", function()
        local doc = assert(DocumentRegistry:openDocument(fixture))
        doc:setupDefaultView()
        doc:setViewMode("page")
        doc:setViewDimen({ w = 600, h = 800 })
        doc:setFontSize(23)
        doc._document:setIntProperty("font.kerning.mode", 3)
        doc._document:setIntProperty(
            "crengine.style.line.breaking.mode", 1)
        doc._document:setIntProperty(
            "crengine.style.justify.space.shrink.percent", 34)
        doc._document:setIntProperty(
            "crengine.style.justify.space.stretch.percent", 25)
        doc._document:setIntProperty(
            "crengine.style.justify.tracking.shrink.percent", 1)
        doc._document:setIntProperty(
            "crengine.style.justify.tracking.stretch.percent", 1)
        doc._document:setIntProperty(
            "crengine.style.justify.tracking.delta.max.bp", 50)
        doc._document:setIntProperty(
            "crengine.style.justify.pretolerance", 50)
        doc._document:setIntProperty(
            "crengine.style.justify.tolerance", 500)
        doc._document:setIntProperty(
            "crengine.style.justify.hyphen.penalty", 25)
        doc._document:setIntProperty(
            "crengine.style.justify.double.hyphen.demerits", 3000)
        doc._document:setIntProperty(
            "crengine.style.justify.final.hyphen.demerits", 1500)
        doc:render()

        local first_y = doc:getPosFromXPointer("/html/body/p/text().0")
        local each_offset = assert(text:find("Each", 1, true)) - 1
        local each_y = doc:getPosFromXPointer(
            "/html/body/p/text()." .. each_offset)
        assert.are.equal(first_y, each_y)
        doc:close()
    end)

    it("gives hyphens zero weight in the texture rating", function()
        assert.are.same(
            lineSignature(0, 0),
            lineSignature(10000, 1000000))
    end)

    it("does not buy smoother middle lines with a one-word extra ending", function()
        local greedy = lineSignature(0, 0, 0)
        local optimized = lineSignature(0, 0, 1)
        assert.is_true(#optimized <= #greedy, string.format(
            "Optimized used %d lines while Greedy used %d",
            #optimized, #greedy))
    end)

end)

describe("Optimized justification recovery", function()
    local DocumentRegistry
    local fixture = "/tmp/koreader-optimized-no-greedy-fallback.html"
    local text = "Adaptive paragraph breaking should examine the complete paragraph before choosing calm lines with consistent spacing while preserving readable endings and avoiding distracting rivers across neighboring lines of representative prose."

    setup(function()
        require("commonrequire")
        DocumentRegistry = require("document/documentregistry")
        local file = assert(io.open(fixture, "wb"))
        file:write([[<!doctype html><html lang="en"><head><meta charset="utf-8"><style>
body { font-family: serif; margin: 0; }
p { text-align: justify; hyphens: auto; text-indent: 1.2em; margin: 0; }
</style></head><body><p>]])
        file:write(text)
        file:write("</p></body></html>")
        file:close()
    end)

    local function wordOffsets()
        local result = {}
        local from = 1
        while true do
            local first, last = text:find("%S+", from)
            if not first then break end
            table.insert(result, first - 1)
            from = last + 1
        end
        return result
    end

    local function lineStarts(mode, strict)
        local doc = assert(DocumentRegistry:openDocument(fixture))
        doc:setupDefaultView()
        doc:setViewMode("page")
        doc:setViewDimen({ w = 600, h = 1000 })
        doc:setFontSize(28)
        doc._document:setIntProperty("font.kerning.mode", 3)
        doc._document:setIntProperty(
            "crengine.style.line.breaking.mode", mode)
        if strict then
            doc._document:setIntProperty(
                "crengine.style.justify.space.shrink.percent", 0)
            doc._document:setIntProperty(
                "crengine.style.justify.space.stretch.percent", 0)
            doc._document:setIntProperty(
                "crengine.style.justify.tracking.shrink.percent", 0)
            doc._document:setIntProperty(
                "crengine.style.justify.tracking.stretch.percent", 0)
            doc._document:setIntProperty(
                "crengine.style.justify.pretolerance", 0)
            doc._document:setIntProperty(
                "crengine.style.justify.tolerance", 0)
            doc._document:setIntProperty(
                "crengine.style.justify.emergency.stretch.percent", 0)
        end
        doc:render()

        local result = {}
        local last_y
        for index, offset in ipairs(wordOffsets()) do
            local y = doc:getPosFromXPointer(
                "/html/body/p/text()." .. offset)
            if y ~= last_y then
                table.insert(result, index)
                last_y = y
            end
        end
        doc:close()
        return result
    end

    it("keeps supported paragraphs in Knuth when quality limits reject every normal path", function()
        local greedy = lineStarts(0, false)
        local hybrid = lineStarts(2, false)
        local recovered = lineStarts(1, true)

        assert.are.same(greedy, hybrid)
        assert.are_not.same(greedy, recovered)
        assert.are.same({ 1, 6, 10, 15, 18, 23, 27 }, recovered)
    end)
end)

describe("Optimized justification draw metadata", function()
    local DocumentRegistry, Blitbuffer
    local fixture = "/tmp/koreader-optimized-last-line-draw.html"

    setup(function()
        require("commonrequire")
        DocumentRegistry = require("document/documentregistry")
        Blitbuffer = require("ffi/blitbuffer")
    end)

    before_each(function()
        local file = assert(io.open(fixture, "wb"))
        file:write([[<!doctype html><html><head><meta charset="utf-8"><style>
body { font-family: serif; margin: 0; }
p { text-align: justify; hyphens: none; margin: 0 0 1em; }
p.reference { text-align: left; }
</style></head><body>
<p>We think it is more than ten metres across, Baltiel's voice broke in because scale.</p>
<p class="reference"><span>We think it is more than ten metres across, Baltiel's voice</span><br/>
<span>broke in because scale.</span></p>
</body></html>]])
        file:close()
    end)

    it("draws a ragged final line like an ordinary left-aligned line", function()
        local doc
        local width
        for candidate_width = 250, 700, 10 do
            doc = assert(DocumentRegistry:openDocument(fixture))
            doc:setupDefaultView()
            doc:setViewMode("page")
            doc:setViewDimen({ w = candidate_width, h = 610 })
            doc:setFontSize(28)
            doc._document:setIntProperty(
                "crengine.style.line.breaking.mode", 1)
            doc._document:setIntProperty(
                "crengine.style.justify.tolerance", 10000)
            doc._document:setIntProperty(
                "crengine.style.justify.emergency.stretch.percent", 100)
            doc._document:setIntProperty(
                "crengine.style.justify.tracking.delta.max.bp", 0)
            doc:render()

            local lead_y = doc:getPosFromXPointer(
                "/html/body/p[1]/text().0")
            local actual_y, actual_x = doc:getPosFromXPointer(
                "/html/body/p[1]/text().60")
            local actual_last_y = doc:getPosFromXPointer(
                "/html/body/p[1]/text().77")
            if actual_y > lead_y and actual_last_y == actual_y and
                    actual_x == 0 then
                width = candidate_width
                break
            end
            doc:close()
            doc = nil
        end
        assert.is_truthy(doc, "no two-line geometry found")

        local actual_y, actual_x = doc:getScreenPositionFromXPointer(
            "/html/body/p[1]/text().60")
        local reference_y, reference_x = doc:getScreenPositionFromXPointer(
            "/html/body/p[2]/span[2]/text().0")

        local bb = Blitbuffer.new(width, 610)
        doc:drawCurrentView(bb, 0, 0, { x = 0, y = 0, w = width, h = 610 })
        local line_height = 40
        local compare_width = math.min(
            width - actual_x, width - reference_x)
        for dy = 0, line_height - 1 do
            for dx = 0, compare_width - 1 do
                local actual = bb:getPixel(
                    actual_x + dx, actual_y + dy):getColor8().a
                local reference = bb:getPixel(
                    reference_x + dx, reference_y + dy):getColor8().a
                assert.are.equal(reference, actual, string.format(
                    "last-line raster differs at width %d, x=%d, y=%d",
                    width, dx, dy))
            end
        end
        bb:free()
        doc:close()
    end)
end)
