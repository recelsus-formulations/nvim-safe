-- Neovim 0.9 / 0.10 向けの互換層。新しい API があればそれを使い、無ければ代替実装を使う
local M = {}

M.uv = vim.uv or vim.loop

function M.joinpath(...)
    if vim.fs.joinpath then
        return vim.fs.joinpath(...)
    end
    return (table.concat({ ... }, "/"):gsub("//+", "/"))
end

-- vim.system のうち、このリポジトリで使う範囲 (stdout/stderr/code, wait, kill, env) だけを再現する
-- options.env: 追加・上書きする環境変数
function M.system(command, on_exit, options)
    options = options or {}
    if vim.system then
        return vim.system(command, { env = options.env }, on_exit)
    end
    local result
    local output = { stdout = "", stderr = "" }
    local function collect(name)
        return function(_, data)
            output[name] = table.concat(data, "\n")
        end
    end
    local job = vim.fn.jobstart(command, {
        env = options.env,
        stdout_buffered = true,
        stderr_buffered = true,
        on_stdout = collect("stdout"),
        on_stderr = collect("stderr"),
        on_exit = function(_, code)
            result = { code = code, stdout = output.stdout, stderr = output.stderr }
            if on_exit then
                on_exit(result)
            end
        end,
    })
    if job <= 0 then
        error("Could not run command: " .. tostring(command[1]))
    end
    return {
        wait = function(_, timeout)
            vim.fn.jobwait({ job }, timeout or -1)
            if not result then
                vim.fn.jobstop(job)
                return { code = 124, stdout = "", stderr = "timeout" }
            end
            return result
        end,
        kill = function()
            vim.fn.jobstop(job)
        end,
    }
end

local base64_alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

function M.base64_encode(text)
    if vim.base64 then
        return vim.base64.encode(text)
    end
    local bit = require("bit")
    local encoded = {}
    for index = 1, #text, 3 do
        local a, b, c = text:byte(index, index + 2)
        local value = bit.bor(bit.lshift(a, 16), bit.lshift(b or 0, 8), c or 0)
        for offset = 3, 0, -1 do
            local position = bit.band(bit.rshift(value, offset * 6), 63) + 1
            encoded[#encoded + 1] = base64_alphabet:sub(position, position)
        end
        if not b then
            encoded[#encoded] = "="
            encoded[#encoded - 1] = "="
        elseif not c then
            encoded[#encoded] = "="
        end
    end
    return table.concat(encoded)
end

-- vim.ui.clipboard.osc52 (0.10+) の copy と同等
function M.osc52_copy(register)
    local ok, osc52 = pcall(require, "vim.ui.clipboard.osc52")
    if ok then
        return osc52.copy(register)
    end
    local clipboard = register == "+" and "c" or "p"
    return function(lines)
        local encoded = M.base64_encode(table.concat(lines, "\n"))
        vim.api.nvim_chan_send(2, string.format("\027]52;%s;%s\027\\", clipboard, encoded))
    end
end

-- vim.wo[window][0].name = value (0.10+) と同等。ウィンドウ内の現在のバッファに対してのみ設定する
function M.set_window_local(window, name, value)
    vim.api.nvim_set_option_value(name, value, { scope = "local", win = window })
end

function M.has_option(name)
    return vim.fn.exists("+" .. name) == 1
end

function M.is_winfixbuf(window)
    return M.has_option("winfixbuf") and vim.wo[window].winfixbuf
end

function M.has_event(name)
    return vim.fn.exists("##" .. name) == 1
end

-- vim.lsp.rpc.start(cmd, dispatchers, opts) は 0.10+。0.9 は (cmd, args, dispatchers, opts) で
-- 引数の数でしか区別できないためバージョンで分ける
function M.lsp_rpc_start(command, dispatchers, options)
    if vim.fn.has("nvim-0.10") == 1 then
        return vim.lsp.rpc.start(command, dispatchers, options)
    end
    return vim.lsp.rpc.start(command[1], vim.list_slice(command, 2), dispatchers, options)
end

-- vim.lsp.get_clients は 0.10+。それ以前は get_active_clients
function M.lsp_clients(filter)
    return (vim.lsp.get_clients or vim.lsp.get_active_clients)(filter)
end

-- client:request / client:cancel_request (メソッド呼び出し) は 0.11+。それ以前は client.request(...)
-- 0.12 では旧形式が非推奨のため、形式の違いは関数の有無で判別できずバージョンで分ける
local method_call = vim.fn.has("nvim-0.11") == 1

function M.lsp_request(client, method, params, handler, bufnr)
    if method_call then
        return client:request(method, params, handler, bufnr)
    end
    return client.request(method, params, handler, bufnr)
end

function M.lsp_cancel_request(client, id)
    if method_call then
        return client:cancel_request(id)
    end
    return client.cancel_request(id)
end

-- LSP の位置 (character は offset_encoding の単位) を行内のバイト位置に変換する。
-- vim.str_byteindex は 0.11 で引数の形式が変わったため使わない
function M.lsp_byte_index(line, character, encoding)
    if encoding == "utf-8" then
        return math.min(character, #line)
    end
    local units, index = 0, 0
    while index < #line and units < character do
        local byte = line:byte(index + 1)
        local length = byte < 0x80 and 1 or byte < 0xE0 and 2 or byte < 0xF0 and 3 or 4
        units = units + ((encoding == "utf-16" and length == 4) and 2 or 1)
        index = index + length
    end
    return index
end

-- vim.fs.root (0.10+) と同等。markers のいずれかを含む最も近い親ディレクトリ
function M.find_root(buffer, markers)
    if vim.fs.root then
        return vim.fs.root(buffer, markers)
    end
    local path = vim.api.nvim_buf_get_name(buffer)
    if path == "" then
        return nil
    end
    local found = vim.fs.find(markers, { path = vim.fs.dirname(path), upward = true })[1]
    return found and vim.fs.dirname(found) or nil
end

-- jobstart の term オプションは 0.11+。それ以前は termopen を使う
function M.open_terminal(command, options)
    if vim.fn.has("nvim-0.11") == 1 then
        return vim.fn.jobstart(command, vim.tbl_extend("force", options, { term = true }))
    end
    return vim.fn.termopen(command, options)
end

return M
