local M = {}

local function has_environment(name)
    local value = vim.env[name]
    return value ~= nil and value ~= ""
end

function M.detect()
    local environment = {
        is_windows = vim.fn.has("win32") == 1,
        is_macos = vim.fn.has("macunix") == 1,
        is_wsl = vim.fn.has("wsl") == 1 or has_environment("WSL_DISTRO_NAME") or has_environment("WSL_INTEROP"),
        is_tmux = has_environment("TMUX"),
        is_ssh = has_environment("SSH_CONNECTION") or has_environment("SSH_TTY"),
        has_wayland = has_environment("WAYLAND_DISPLAY"),
        has_x11 = has_environment("DISPLAY"),
    }

    if not environment.is_ssh then
        if environment.is_wsl or environment.is_windows then
            if vim.fn.executable("win32yank.exe") == 1 then
                environment.paste_command = { "win32yank.exe", "-o", "--lf" }
            else
                local candidates = environment.is_wsl and { "powershell.exe", "pwsh.exe" }
                    or { "pwsh", "powershell", "powershell.exe" }
                for _, command in ipairs(candidates) do
                    if vim.fn.executable(command) == 1 then
                        environment.paste_command = {
                            command, "-NoLogo", "-NoProfile", "-NonInteractive", "-Command",
                            "[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false); "
                                .. "$ErrorActionPreference = 'Stop'; "
                                .. "[Console]::Out.Write([string](Get-Clipboard -Raw))",
                        }
                        break
                    end
                end
            end
        end
        if not environment.paste_command then
            if environment.is_macos and vim.fn.executable("pbpaste") == 1 then
                environment.paste_command = { "pbpaste" }
            elseif environment.has_wayland and vim.fn.executable("wl-paste") == 1 then
                environment.paste_command = { "wl-paste", "--no-newline" }
            elseif environment.has_x11 and vim.fn.executable("xclip") == 1 then
                environment.paste_command = { "xclip", "-selection", "clipboard", "-out" }
            end
        end
    end

    return environment
end

return M
