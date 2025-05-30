--[[
-- This filter is used to run marimo cells in a pandoc document.
-- It will run the marimo cells and replace them with the output.
-- It will also add the marimo assets to the document header.
--]]

local utils = require("utils")

-- globals
local is_mime_sensitive = utils.is_mime_sensitive()
local marimo_execution = nil
local missingMarimoCell = true

-- count number of entries in marimo_execution["outputs"]
marimo_execution = utils.run_marimo({})
local expected_cells = marimo_execution["count"]
cell_index = 1

function Meta(m)
    return m
end

-- Hook functions to pandoc
function CodeBlock(el)
    --[[
    --]]
    if
        el.attr
        and el.attr.classes:find_if(function(c)
            return string.match(c, ".*marimo.*")
        end)
    then
        missingMarimoCell = false
        if cell_index > expected_cells then
            message = string.format(
                "attempted to extract more cells than "
                    .. "expected %d (expected %d)\n",
                cell_index,
                expected_cells
            )
            if pandoc.log ~= nil then
                pandoc.log.warn(message)
            else
                io.stderr:write(message)
            end
            cell_index = cell_index + 1
            return
        end
        cell_table = marimo_execution["outputs"][cell_index]
        cell_index = cell_index + 1

        -- A type will be returned if the output type is mime sensitive (e.g. pdf,
        -- or latex).
        if is_mime_sensitive then
            local response = {} -- empty
            if cell_table.display_code then
                table.insert(
                    response,
                    pandoc.CodeBlock(cell_table.code, "python")
                )
            end

            if cell_table.type == "figure" then
                -- for latex/pdf, has to be run with --extract-media=media flag
                -- can also set this in qmd header
                image = pandoc.Image("Generated Figure", cell_table.value)
                table.insert(response, pandoc.Figure(pandoc.Para({ image })))
                return response
            end
            if cell_table.type == "para" then
                table.insert(response, pandoc.Para(cell_table.value))
                return response
            end
            if cell_table.type == "blockquote" then
                table.insert(response, pandoc.BlockQuote(cell_table.value))
                return response
            end
            local code_block = response[1]
            response = pandoc.read(cell_table.value, cell_table.type).blocks
            table.insert(response, code_block)
            return response
        end

        -- Response is HTML, so whatever formats are OK with that.
        return pandoc.RawBlock(cell_table.type, cell_table.value)
    end
end

function Pandoc(doc)
    --[[
    --]]

    -- If the expected count != actual count, then we have a problem
    -- and should fail.
    if expected_cells ~= cell_index - 1 then
        error(
            "marimo filter failed. Expected "
                .. expected_cells
                .. " cells, but got "
                .. cell_index - 1
        )
    end

    -- Don't do anything if we don't have to
    if missingMarimoCell then
        return doc
    end

    if quarto == nil then
        message = (
            "Since not using quarto, be sure to include the following in "
            .. "your document header for html documents:\n"
            .. marimo_execution["header"]
        )
        if pandoc.log ~= nil then
            pandoc.log.warn(message)
        else
            io.stderr:write(message)
        end
        return doc
    end

    -- Don't add assets to non-html documents
    if not quarto.doc.is_format("html") then
        return doc
    end

    -- For local testing we can connect to the frontend webserver
    local dev_server = os.getenv("QUARTO_MARIMO_DEBUG_ENDPOINT")
    if dev_server ~= nil then
        quarto.doc.include_text(
            "in-header",
            '<meta name="referrer" content="unsafe-url" />'
                .. '<script type="module" crossorigin="anonymous">import { injectIntoGlobalHook } from "'
                .. dev_server
                .. '/@react-refresh";injectIntoGlobalHook(window); window.$RefreshReg$ = () => {};'
                .. "window.$RefreshSig$ = () => (type) => type;</script>"
                .. '<script type="module" crossorigin="anonymous" src="'
                .. dev_server
                .. '/@vite/client"></script>'
        )
    end

    -- Web assets, seems best way
    quarto.doc.include_text("in-header", marimo_execution["header"])
    return doc
end
