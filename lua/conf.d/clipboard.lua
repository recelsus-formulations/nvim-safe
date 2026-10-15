local M = {}

local function parse_text(text)
    local linewise = text:sub(-1) == "\n"
    if linewise then
        text = text:sub(1, -2)
    end
    return { vim.split(text, "\n", { plain = true }), linewise and "V" or "v" }
end

function M.setup(environment)
    local osc52 = require("vim.ui.clipboard.osc52")
    local registers = {}
    local function cached_paste(register)
        return vim.deepcopy(registers[register] or { { "" }, "v" })
    end
    local function copy(register)
        local send = osc52.copy(register)
        return function(lines, register_type)
            registers[register] = { vim.deepcopy(lines), register_type }
            send(lines)
        end
    end
    local function paste(register)
        return function()
            if not environment.paste_command then
                return cached_paste(register)
            end
            local ok, result = pcall(function()
                return vim.system(environment.paste_command, {}):wait(2000)
            end)
            if not ok or result.code ~= 0 or type(result.stdout) ~= "string" then
                return cached_paste(register)
            end
            local text = result.stdout:gsub("\r\n", "\n"):gsub("\r", "\n")
            local cached = registers[register]
            if cached then
                local copied_text = table.concat(cached[1], "\n")
                if text == copied_text or (cached[2] == "V" and text == copied_text .. "\n") then
                    return cached_paste(register)
                end
            end
            registers[register] = parse_text(text)
            return cached_paste(register)
        end
    end
    local name = environment.is_tmux and "OSC52 (tmux)" or "OSC52"
    name = name .. (environment.paste_command and (" + " .. environment.paste_command[1]) or " + cached paste")
    vim.g.clipboard = {
        name = name,
        copy = { ["+"] = copy("+"), ["*"] = copy("*") },
        paste = { ["+"] = paste("+"), ["*"] = paste("*") },
        cache_enabled = 0,
    }
end

return M
