describe("Optimized justification with attached inline-box footnotes", function()
    local DocumentRegistry
    local fixture = "/tmp/koreader-optimized-footnotes.html"

    setup(function()
        require("commonrequire")
        DocumentRegistry = require("document/documentregistry")
    end)

    before_each(function()
        local file = assert(io.open(fixture, "wb"))
        file:write([[<!doctype html><html lang="en"><head><meta charset="utf-8"><style>
body { font-family: serif; line-height: 1.25; margin: 0; }
p { text-align: justify; hyphens: auto; text-indent: 1.2em; margin: 0 0 .35em; }
a.noteref { display: inline-block; font-size: .7em; vertical-align: super;
    -cr-hint: noteref; text-indent: 0; }
aside { display: block; -cr-hint: footnote-inpage; margin: 0; }
</style></head><body>]])
        for i = 1, 18 do
            file:write(string.format([[<p id="p%d"><span>A%d</span> Ordinary paragraphs with a <span>compact</span> inline footnote reference should still use calm paragraph-wide line breaking across several lines of <span>representative</span> prose<a class="noteref" href="#fn%d"><span>%d</span></a>, without losing the reference or its page association. Additional words make every paragraph long enough to exercise several candidate breaks. <span>Z%d</span></p>
]], i, i, i, i, i))
        end
        for i = 1, 18 do
            file:write(string.format([[<aside id="fn%d" role="doc-footnote">%d. Footnote text for reference %d.</aside>
]], i, i, i))
        end
        file:write("</body></html>")
        file:close()
    end)

    it("preserves attached references and paragraph separation", function()
        local widths = { 430, 520, 610 }
        local heights = { 610, 790 }
        local font_sizes = { 20, 28 }

        for _, width in ipairs(widths) do
            for _, height in ipairs(heights) do
                for _, font_size in ipairs(font_sizes) do
                    local doc = assert(DocumentRegistry:openDocument(fixture))
                    doc:setupDefaultView()
                    doc:setViewMode("page")
                    doc:setViewDimen({ w = width, h = height })
                    doc:setFontSize(font_size)
                    doc._document:setIntProperty(
                        "crengine.style.line.breaking.mode", 1)
                    doc._document:setIntProperty(
                        "crengine.style.justify.tolerance", 10000)
                    doc._document:setIntProperty(
                        "crengine.style.justify.emergency.stretch.percent", 100)
                    doc._document:setIntProperty(
                        "crengine.style.justify.tracking.delta.max.bp", 0)
                    doc:render()

                    local seen = {}
                    for i = 1, 18 do
                        local ref_xp = string.format(
                            "/html/body/p[%d]/a[1]/span[1]/text().0", i)
                        local page = doc:getPageFromXPointer(ref_xp)
                        doc:gotoPage(page, true)
                        for _, link in ipairs(doc:getPageLinks(true)) do
                            if link.section == "#fn" .. i then
                                seen[i] = true
                                break
                            end
                        end
                        if i < 18 then
                            local ending = doc:getPosFromXPointer(string.format(
                                "/html/body/p[%d]/span[4]/text().0", i))
                            local following = doc:getPosFromXPointer(string.format(
                                "/html/body/p[%d]/span[1]/text().0", i + 1))
                            assert.is_true(following > ending, string.format(
                                "paragraph boundary collapsed after reference %d " ..
                                "at %dx%d/%dpt", i, width, height, font_size))
                        end
                    end
                    doc:close()

                    for i = 1, 18 do
                        assert.is_true(seen[i], string.format(
                            "missing footnote link %d at %dx%d/%dpt",
                            i, width, height, font_size))
                    end
                end
            end
        end
    end)

end)
