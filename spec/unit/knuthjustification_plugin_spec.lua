describe("Knuth justification plugin", function()
    local Plugin
    local config
    local document
    local native_properties
    local saved
    local ui

    local setting_names = {
        "line_breaking_mode",
        "justification_word_spacing",
        "justification_letter_spacing",
        "justification_tracking_smoothness",
        "justification_tolerance",
        "justification_hyphen_penalty",
        "justification_line_penalty",
        "justification_hyphen_demerits",
        "justification_line_limits",
    }

    setup(function()
        require("commonrequire")
        disable_plugins()
        Plugin = dofile("plugins/knuthjustification.koplugin/main.lua")
    end)

    before_each(function()
        for _, name in ipairs(setting_names) do
            G_reader_settings:delSetting("copt_" .. name)
        end
        native_properties = {}
        saved = {}
        document = {
            configurable = {},
            _document = {
                setIntProperty = function(_, property, value)
                    native_properties[property] = value
                end,
            },
        }
        config = {
            readSetting = function(_, name)
                return saved[name]
            end,
            saveSetting = function(_, name, value)
                saved[name] = value
            end,
        }
        ui = {
            rolling = {},
            document = document,
            doc_settings = config,
            menu = { registerToMainMenu = function() end },
            handleEvent = function() end,
        }
    end)

    it("loads existing copt settings before rendering and applies every native property", function()
        saved.copt_line_breaking_mode = 1
        saved.copt_justification_word_spacing = { 29, 47 }
        saved.copt_justification_letter_spacing = { 2, 3 }
        saved.copt_justification_tracking_smoothness = 75
        saved.copt_justification_tolerance = { 70, 140 }
        saved.copt_justification_hyphen_penalty = { 61, 62 }
        saved.copt_justification_line_penalty = { 13, 17000 }
        saved.copt_justification_hyphen_demerits = { 12000, 7000 }
        saved.copt_justification_line_limits = { 9, 44 }

        local plugin = Plugin:new{ ui = ui }
        plugin:onReadSettings(config)

        assert.are.equal(1, native_properties["crengine.style.line.breaking.mode"])
        assert.are.equal(29, native_properties["crengine.style.justify.space.shrink.percent"])
        assert.are.equal(47, native_properties["crengine.style.justify.space.stretch.percent"])
        assert.are.equal(2, native_properties["crengine.style.justify.tracking.shrink.percent"])
        assert.are.equal(3, native_properties["crengine.style.justify.tracking.stretch.percent"])
        assert.are.equal(75, native_properties["crengine.style.justify.tracking.delta.max.bp"])
        assert.are.equal(70, native_properties["crengine.style.justify.pretolerance"])
        assert.are.equal(140, native_properties["crengine.style.justify.tolerance"])
        assert.are.equal(61, native_properties["crengine.style.justify.hyphen.penalty"])
        assert.are.equal(62, native_properties["crengine.style.justify.explicit.hyphen.penalty"])
        assert.are.equal(13, native_properties["crengine.style.justify.line.penalty"])
        assert.are.equal(17000, native_properties["crengine.style.justify.adjacent.demerits"])
        assert.are.equal(12000, native_properties["crengine.style.justify.double.hyphen.demerits"])
        assert.are.equal(7000, native_properties["crengine.style.justify.final.hyphen.demerits"])
        assert.are.equal(9, native_properties["crengine.style.justify.emergency.stretch.percent"])
        assert.are.equal(44, native_properties["crengine.style.justify.last.line.min.percent"])
        assert.are.same({ 29, 47 }, document.configurable.justification_word_spacing)
    end)

    it("persists profile events under the compatible copt keys", function()
        local updates = 0
        ui.handleEvent = function()
            updates = updates + 1
        end
        local plugin = Plugin:new{ ui = ui }
        plugin:onReadSettings(config)
        plugin:onSetJustificationTolerance({ 70, 140 })

        assert.are.same({ 70, 140 }, saved.copt_justification_tolerance)
        assert.are.same({ 70, 140 }, document.configurable.justification_tolerance)
        assert.are.equal(70, native_properties["crengine.style.justify.pretolerance"])
        assert.are.equal(140, native_properties["crengine.style.justify.tolerance"])
        assert.are.equal(1, updates)
    end)

    it("persists and applies hybrid Greedy-with-microspacing mode", function()
        local plugin = Plugin:new{ ui = ui }
        plugin:onReadSettings(config)
        plugin:onSetLineBreakingMode(2)

        assert.are.equal(2, saved.copt_line_breaking_mode)
        assert.are.equal(2, document.configurable.line_breaking_mode)
        assert.are.equal(2,
            native_properties["crengine.style.line.breaking.mode"])
    end)

    it("enables page-level justified text when selecting a mode", function()
        local enabled = false
        local forced_tweak
        ui.styletweak = {
            enabled = false,
            tweaks_by_id = {
                text_align_most_justify = { id = "text_align_most_justify" },
            },
            onToggleStyleTweaks = function(self)
                self.enabled = true
                enabled = true
            end,
            onToggleStyleTweak = function(_, value, item, quiet)
                forced_tweak = { value, item, quiet }
            end,
        }
        local plugin = Plugin:new{ ui = ui }
        plugin:onReadSettings(config)
        plugin:onSetLineBreakingMode(1, true)

        assert.is_true(enabled)
        assert.are.same({ "text_align_most_justify", true }, forced_tweak[1])
        assert.are.equal("text_align_most_justify", forced_tweak[2].id)
        assert.is_true(forced_tweak[3])
        assert.are.equal(1,
            native_properties["crengine.style.line.breaking.mode"])
    end)

    it("labels the page-level modes Fast, Hybrid and Best", function()
        local plugin = Plugin:new{ ui = ui }
        plugin:onReadSettings(config)
        local mode_items = plugin:getMenuTable()[1].sub_item_table_func()

        assert.are.same({ "Fast", "Hybrid", "Best" }, {
            mode_items[1].text, mode_items[2].text, mode_items[3].text,
        })
    end)

    it("uses global copt defaults for books without saved values", function()
        G_reader_settings:saveSetting("copt_justification_line_limits", { 9, 44 })
        local plugin = Plugin:new{ ui = ui }
        plugin:onReadSettings(config)

        assert.are.same({ 9, 44 }, document.configurable.justification_line_limits)
        assert.are.equal(9, native_properties["crengine.style.justify.emergency.stretch.percent"])
        assert.are.equal(44, native_properties["crengine.style.justify.last.line.min.percent"])
    end)

    it("migrates the old symmetric Balanced word-space preset", function()
        saved.copt_justification_word_spacing = { 25, 25 }
        local plugin = Plugin:new{ ui = ui }
        plugin:onReadSettings(config)

        assert.are.same({ 34, 25 }, saved.copt_justification_word_spacing)
        assert.are.same({ 34, 25 },
            document.configurable.justification_word_spacing)
        assert.are.equal(34,
            native_properties["crengine.style.justify.space.shrink.percent"])
        assert.are.equal(25,
            native_properties["crengine.style.justify.space.stretch.percent"])
    end)

    it("keeps Knuth controls out of the bottom CreOptions menu", function()
        local found = {}
        local function visit(entries)
            for _, entry in ipairs(entries or {}) do
                if entry.name and entry.show ~= false then
                    found[entry.name] = true
                end
                visit(entry.options)
            end
        end
        visit(require("ui/data/creoptions"))

        assert.is_true(found.word_spacing)
        for _, name in ipairs(setting_names) do
            assert.is_nil(found[name], name)
        end
    end)

    it("hides obsolete hyphen-cost controls from the upper menu", function()
        local plugin = Plugin:new{ ui = ui }
        plugin:onReadSettings(config)
        for _, item in ipairs(plugin:getMenuTable()) do
            local text = item.text_func and item.text_func() or item.text or ""
            assert.is_nil(text:find("Hyphen penalties", 1, true))
            assert.is_nil(text:find("Repeated%-hyphen penalties"))
        end
    end)
end)
