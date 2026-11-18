local M = {}

-- Project colours, defined independently of external themes.
local palette = {
    foreground = "#d9d2c3",
    comment = "#82796b",
    red = "#d8787c",
    orange = "#d9a075",
    yellow = "#dfc18c",
    green = "#a6bd83",
    cyan = "#83bab1",
    blue = "#83aeca",
    purple = "#b89acb",
}

local syntax_groups = {
    foreground = { "Normal", "NormalNC", "Identifier", "Operator", "Delimiter", "SpecialChar" },
    comment = { "Comment", "NonText", "LineNr" },
    red = { "Tag" },
    orange = { "Constant", "Number", "Boolean", "Float" },
    yellow = { "Type", "StorageClass", "Structure", "Typedef" },
    green = { "String", "Character" },
    cyan = { "Special", "PreProc", "Include", "Define", "Macro", "PreCondit" },
    blue = { "Function", "Title" },
    purple = { "Statement", "Conditional", "Repeat", "Label", "Keyword", "Exception" },
}

local syntax_links = {
    ["@variable"] = "Identifier",
    ["@variable.builtin"] = "Special",
    ["@variable.parameter"] = "Identifier",
    ["@variable.member"] = "Tag",
    ["@constant"] = "Constant",
    ["@constant.builtin"] = "Constant",
    ["@constant.macro"] = "Macro",
    ["@module"] = "Type",
    ["@label"] = "Label",
    ["@string"] = "String",
    ["@string.escape"] = "Special",
    ["@string.regexp"] = "Special",
    ["@character"] = "Character",
    ["@boolean"] = "Boolean",
    ["@number"] = "Number",
    ["@type"] = "Type",
    ["@type.builtin"] = "Type",
    ["@attribute"] = "PreProc",
    ["@property"] = "Tag",
    ["@function"] = "Function",
    ["@function.builtin"] = "Special",
    ["@function.call"] = "Function",
    ["@function.macro"] = "Macro",
    ["@function.method"] = "Function",
    ["@function.method.call"] = "Function",
    ["@constructor"] = "Type",
    ["@operator"] = "Operator",
    ["@keyword"] = "Keyword",
    ["@keyword.import"] = "Include",
    ["@punctuation"] = "Delimiter",
    ["@punctuation.special"] = "Special",
    ["@comment"] = "Comment",
    ["@tag"] = "Tag",
    ["@tag.attribute"] = "Type",
    ["@tag.delimiter"] = "Delimiter",
    -- Older queries use these capture names.
    ["@parameter"] = "Identifier",
    ["@field"] = "Tag",
    ["@namespace"] = "Type",
    ["@method"] = "Function",
    ["@method.call"] = "Function",
    ["@lsp.type.namespace"] = "@module",
    ["@lsp.type.type"] = "@type",
    ["@lsp.type.class"] = "@type",
    ["@lsp.type.enum"] = "@type",
    ["@lsp.type.interface"] = "@type",
    ["@lsp.type.struct"] = "@type",
    ["@lsp.type.typeParameter"] = "@type",
    ["@lsp.type.parameter"] = "@variable.parameter",
    ["@lsp.type.variable"] = "@variable",
    ["@lsp.type.property"] = "@property",
    ["@lsp.type.enumMember"] = "@constant",
    ["@lsp.type.function"] = "@function",
    ["@lsp.type.method"] = "@function.method",
    ["@lsp.type.macro"] = "@constant.macro",
    ["@lsp.type.keyword"] = "@keyword",
    ["@lsp.type.comment"] = "@comment",
    ["@lsp.type.string"] = "@string",
    ["@lsp.type.number"] = "@number",
    ["@lsp.type.regexp"] = "@string.regexp",
    ["@lsp.type.operator"] = "@operator",
    ["@lsp.type.decorator"] = "@attribute",
    ["@lsp.typemod.variable.defaultLibrary"] = "@variable.builtin",
    ["@lsp.typemod.function.defaultLibrary"] = "@function.builtin",
    ["@lsp.typemod.variable.readonly"] = "@constant",
}

local excluded_groups = {
    Visual = true,
    VisualNOS = true,
    PmenuSel = true,
    ExSidebarFileTitle = true,
    ExSidebarSymbolTitle = true,
    ExSidebarDiagnosticTitle = true,
}

local custom_groups = {
    Search = { fg = "#0f0f0f", bg = "#ffe066", bold = true },
    IncSearch = { fg = "#0f0f0f", bg = "#ffca3a", bold = true },
    CurSearch = { fg = "#0f0f0f", bg = "#ffba08", bold = true },
    PmenuSel = { fg = "#ffffff", bg = "#3e68d7", bold = true },
}

local function refresh_highlights()
    for colour, names in pairs(syntax_groups) do
        for _, name in ipairs(names) do
            vim.api.nvim_set_hl(0, name, { fg = palette[colour] })
        end
    end
    for name, target in pairs(syntax_links) do
        vim.api.nvim_set_hl(0, name, { link = target })
    end
    -- Preserve links used by syntax, Tree-sitter and semantic highlights.
    for _, name in ipairs(vim.fn.getcompletion("", "highlight")) do
        if not excluded_groups[name] then
            local highlight = vim.api.nvim_get_hl(0, { name = name, link = true })
            if not highlight.link and (highlight.bg ~= nil or highlight.ctermbg ~= nil) then
                highlight.bg = nil
                highlight.ctermbg = nil
                vim.api.nvim_set_hl(0, name, highlight)
            end
        end
    end
    for name, options in pairs(custom_groups) do
        vim.api.nvim_set_hl(0, name, options)
    end
end

function M.setup()
    refresh_highlights()
    vim.api.nvim_create_autocmd("ColorScheme", {
        group = vim.api.nvim_create_augroup("ex_transparent", { clear = true }),
        callback = refresh_highlights,
    })
end

return M
