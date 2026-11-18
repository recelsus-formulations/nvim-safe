# Neovim - Safe

A Neovim configuration built around its native APIs. It works without a plugin manager. Mason and nvim-treesitter are optional and are fetched only when their commands are run.

For the full keymap and feature reference in Japanese, see [README-ja.md](README-ja.md).

## Requirements

- Neovim 0.9 or later. Neovim 0.12 is the primary target.
- `git` for Git signs and optional Mason installation.
- Language servers are optional. Each server starts only when its executable is available.

Run `bin/check.sh` to inspect the available commands, parsers, and language servers. Run `bin/clear.sh` only when you intend to clear this configuration's runtime data.

## Features

The configuration provides native clipboard integration, file navigation, terminal windows, text search, pairs, jump labels, scope highlighting, Git signs, optional Tree-sitter highlighting, completion, and LSP support. Most features use only Neovim's built-in APIs.

## Sidebar

The sidebar hosts independent views in one window per tab. `Ctrl-e` opens or closes it. The first opening shows the File Tree; later openings restore the view, cursor position, and scroll position that were visible when it was closed. Inside the sidebar, `Ctrl-n` and `Ctrl-p` cycle through registered views while retaining each view's position. `:Ex` opens or toggles the File Tree directly. `gd` opens the definition view when the key is not already mapped; `:SymbolTree` opens document symbols, and `:SymbolTree definition` opens definitions.

The File Tree shows its current root in yellow, directories in blue, and files in the normal text colour. Git status colours take precedence for changed entries.

In the Symbol Tree, `Enter` expands or collapses a group or jumps to a location. `Tab` previews a location, `Ctrl-v` and `Ctrl-x` open it in a vertical or horizontal split, `R` refreshes the LSP result, and `q` closes the sidebar. A missing LSP produces a message without affecting the File Tree.

`<leader>fg` opens text search, and `<leader>ff` finds files. Both are registered views of the same floating search panel, with input, extension and exclusion fields, a result list, and a preview. `:SearchPanel grep` and `:SearchPanel files` open the views directly. The panel uses ripgrep when `rg` is available and a native Neovim fallback otherwise. Tab moves through the fields and results. Each input field enters Insert mode when focused, and the selected result remains highlighted without cursor focus. Escape leaves Insert mode without closing the panel; Ctrl-w cannot change windows from Normal or Visual mode, while Ctrl-c or `:q` closes it. Text search accepts regular expressions; file search matches relative paths fuzzily without case sensitivity. Additional search views can register with `lua/ex/panel.lua` by providing `title`, `on_show`, `on_change`, and `on_open`.

Matching words under the cursor are highlighted in the current editing window after a short pause. The highlight clears when entering Insert mode or leaving the window.

`:Messages` opens message history in a split. Press `y` to copy the current line, `Y` to copy all displayed messages, `R` to refresh, or `q` to close it. Copies use the configured clipboard.

| Location | Purpose |
| --- | --- |
| `lua/config.lua` and `lua/conf.d/` | Editor settings and environment integration |
| `lua/ex/` | Native implementations of editing and navigation features |
| `lua/tree-sitter/` | Tree-sitter configuration and optional parser installation |
| `lua/lsp/` | Language server configuration and optional Mason integration |
| `lua/completion/` | Completion from LSP, paths, and buffer words |

## LSP

Neovim 0.11 and later use `vim.lsp.config` and `vim.lsp.enable`. Earlier supported versions use the local `vim.lsp.start` fallback. Mason can be installed with `:MasonBootstrap`; `:LspInstall [language]` installs supported language server packages. Servers already on `PATH` work without Mason.

TypeScript and JavaScript use TypeScript 7 or later through `tsc --lsp --stdio`. The configuration checks `node_modules/.bin/tsc` in the project first, then `tsc` on `PATH`. Install TypeScript in the project or on `PATH`; Mason does not install it through `:LspInstall`.

PHP uses Intelephense. In CakePHP projects identified by a `cakephp/cakephp` requirement in `composer.json`, it indexes legacy `.ctp` templates and uses `webroot/` as the document root when present. Neovim also treats `.ctp` files as PHP. Standard `.php` templates work without extra configuration. CakePHP's dynamic members may need PHPDoc annotations in the project; the configuration keeps undefined member diagnostics enabled.

When an LSP is attached, `K` shows diagnostics on the current line or LSP hover when there are none. Press `Esc` to close the floating window. In a hover window, `Ctrl-v` and `Ctrl-x` open its text in a vertical or horizontal split. `<leader>le`, `[d`, and `]d` open, go to the previous, and go to the next diagnostic respectively.

## Further Reading

- [Intelephense documentation](https://www.intelephense.com/docs) covers PHP indexing, project configuration, and PHPDoc support.
- [CakePHP IdeHelper](https://github.com/dereuromark/cakephp-ide-helper) can generate annotations for CakePHP's dynamic APIs.
- [README-ja.md](README-ja.md) contains the detailed setup and keymap reference.
