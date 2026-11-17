# Neovim - of

A Neovim configuration built around its native APIs. It works without a plugin manager. Mason and nvim-treesitter are optional and are fetched only when their commands are run.

For the full keymap and feature reference in Japanese, see [README-ja.md](README-ja.md).

## Requirements

- Neovim 0.9 or later. Neovim 0.12 is the primary target.
- `git` for Git signs and optional Mason installation.
- Language servers are optional. Each server starts only when its executable is available.

Run `bin/check.sh` to inspect the available commands, parsers, and language servers. Run `bin/clear.sh` only when you intend to clear this configuration's runtime data.

## Features

The configuration provides native clipboard integration, file navigation, terminal windows, text search, pairs, jump labels, scope highlighting, Git signs, optional Tree-sitter highlighting, completion, and LSP support. Most features use only Neovim's built-in APIs.

`<leader>fg` opens text search. It uses ripgrep when `rg` is available and a native Neovim search otherwise. Separate fields accept a search pattern, comma-separated extensions such as `php,js`, and extra exclusions such as `*.json,node_modules/`. Tab moves through the three fields and the results list. The search pattern uses ripgrep regular expressions with `rg` and Vim regular expressions in the fallback.

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
