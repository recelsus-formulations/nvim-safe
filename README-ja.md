# Neovim - Safe

## Dependencies

必須は Neovim 本体のみです。

基準は Neovim 0.12 です。0.11 以前は、同じ挙動になるよう代替実装へ順にフォールバックします。

| Neovim | LSP の接続 | Mason | nvim-treesitter |
| --- | --- | --- | --- |
| 0.12（基準） | `vim.lsp.config` / `vim.lsp.enable` | 利用可 | `main` |
| 0.11 | 同上 | 利用可 | `master`（0.11 向けに凍結） |
| 0.10 | `vim.lsp.start`（`lua/lsp/fallback.lua`） | 利用可 | `master` |
| 0.9（Ubuntu 24.04 の apt 版は 0.9.5） | 同上 | 対象外（PATH 上のサーバーのみ） | 対象外（同梱 parser のみ） |

0.9.5・0.10.4・0.11.0・0.11.6・0.12.6 で動作確認しています。 \
新しい API がある場合はそれを使い、無い場合は `lua/compat.lua` などの代替実装を使います。 \
Mason・nvim-treesitter が対象外のバージョンでは、取得用のコマンド（`:MasonBootstrap` など）を定義しません。 \
0.12 で追加された機能（ノード単位の選択など）を使う設定は、現時点では入れていません。

以下の外部コマンドはすべて任意で、無い場合は該当機能だけが無効または代替動作になります。

| コマンド | 利用箇所 | 無い場合 |
| --- | --- | --- |
| `git` | Git Signs、`:MasonBootstrap` | 印を表示しない。Mason を取得できない |
| `win32yank.exe` / `powershell.exe` / `pwsh` | 貼り付け（WSL・Windows） | 次の候補、最終的に Neovim 内のキャッシュを使用 |
| `pbpaste` | 貼り付け（macOS） | 同上 |
| `wl-paste` | 貼り付け（Wayland） | 同上 |
| `xclip` | 貼り付け（X11） | 同上 |
| `shell`（`$SHELL`） | Terminal | 端末を開けない |

* コピーは OSC52 のため外部コマンドは不要ですが、端末（tmux 経由の場合は tmux も）の OSC52 対応が必要です。
* Tree-sitter は Neovim 同梱、または runtimepath に置いた parser/query を使います。外部コマンドは不要で、無い言語は標準 syntax になります。

### Optional: Tree-sitter parsers

`:TreesitterBootstrap` を実行した場合のみ必要です。実行しなければ以下は一切使いません。

| コマンド | 用途 |
| --- | --- |
| `git` | nvim-treesitter の取得 |
| C コンパイラ（`cc`・`gcc`・`clang`、`$CC`） | parser のビルド |
| `curl`・`tar` | parser のダウンロード（`master` は `git` でも可） |
| `tree-sitter`（tree-sitter-cli 0.26.1 以降、npm 版は不可） | parser のビルド（`main` = 0.12 以降のみ） |

### Optional: LSP

`:MasonBootstrap` を実行した場合のみ必要です（Mason は 0.10 以降）。実行しなければ以下は一切使いません。

| コマンド | 用途 |
| --- | --- |
| `git` | mason.nvim の取得 |
| `curl`（または `wget`）・`tar`・`gzip`・`bash` | Mason によるダウンロード・展開 |
| `unzip` | zip 配布のサーバー（clangd など） |
| `npm`・`go`・`cargo`・`java`・`python3` など | サーバーごとの実行環境。詳細は [LSP](#lsp-optional-mason) の言語一覧 |

### Scripts

| スクリプト | 操作 |
| --- | --- |
| `bin/check.sh` | Neovim のバージョン、上記の外部コマンド、クリップボード、Tree-sitter parser、LSP サーバーの利用可否を表示。読み取りのみ |
| `bin/clear.sh` | Neovim の実行で生成された data・state・cache（`~/.local/share/nvim` など）を確認後に削除。`-n` で対象の表示のみ、`-y` で確認なし |

* どちらも `XDG_*_HOME` と `NVIM_APPNAME` に従います。設定ディレクトリは削除しません。
* `check.sh` は設定ファイル（`lua/conf.d/environment.lua`・`lua/lsp/servers/*.lua`・`lua/tree-sitter/languages.lua`）を読み込んで判定します。 \
  `CHECK_NVIM=<path>` で確認に使う nvim を指定できます（`$NVIM` は Neovim が `:terminal` などに設定するため使いません）。 \
  Neovim 内からは `:ConfigCheck` で実行できます（[Commands](#commands)）。
* `clear.sh` は undo 履歴・shada（履歴・マーク・レジスタ）・Mason と LSP サーバーも削除します。

## Basic Settings

- `lua/ex/` はプラグイン代替実装
- `lua/conf.d/` は標準設定範囲のもの
- `lua/config.lua` は基本設定
- `lua/compat.lua` は旧バージョン向けの代替実装
- `lua/command/` はユーザーコマンド

カラースキームは Neovim 標準の `slate` です。外部テーマは使いません。 \
構文・Tree-sitter・LSP の文字色には、暖色寄りの独自配色を上書きします。 \
文字列は緑、関数は青、キーワードは紫、型は黄、定数はオレンジを基本とします。 \
外部テーマのコード・配色定義はコピーしていないため、`onedark warmer` と完全には一致しません。 \
本文・カーソル行・ステータスライン・ポップアップなどの背景を透過し、選択範囲の背景は残します。 \
検索結果は黄色系の背景、補完候補の選択行は青い背景に白文字で表示します。 \
これらの表示調整は `lua/conf.d/highlight.lua` にまとめ、`:colorscheme` で変更した場合も再適用します。

## Commands

`lua/command/init.lua` が `lua/command/*.lua` を読み込み、各モジュールの `setup()` を呼びます。 \
コマンドを追加する場合は、`setup()` でユーザーコマンドを定義するモジュールをこのディレクトリに置きます。

| コマンド | ファイル | 操作 |
| --- | --- | --- |
| `:ConfigCheck` | `check.lua` | `bin/check.sh` を実行し、結果を下部の分割ウィンドウに表示。`q` で閉じる、`R` で再実行 |

* `:ConfigCheck` は別プロセスとして非同期に実行するため、確認中も編集を続けられ、使用中のセッションの状態は変わりません。 \
  確認には実行中の nvim と同じものを使います。`bash` が必要です。

## Clipboard

`lua/conf.d/environment.lua` で WSL・Windows・macOS・tmux・SSH・利用可能なコマンドを判定します。 \
コピーは全環境で Neovim 標準のOSC52を使用、 コピー用の外部コマンドやプラグインは不要です。 \
`unnamedplus` により通常の yank/delete も`+`レジスタに接続します。

貼り付け用のコマンドは存在するものだけを選択します。

| 環境 | 貼り付け元 |
| --- | --- |
| WSL / Windows | win32yank.exe、なければ利用可能な Windows PowerShell |
| macOS | pbpaste |
| Wayland | WAYLAND_DISPLAY がある場合の wl-paste |
| X11 | DISPLAY がある場合の xclip |
| SSH または取得コマンドなし | この Neovim 内で最後にコピーしたレジスタ内容 |

* WSL で Windows コマンドがなければ Wayland/X11 も候補。
* PowerShell は UTF-8 で出力し、 CRLF は LF に正規化します。コマンドは貼り付け時だけ実行し、2秒でタイムアウトさせます。
* 失敗時はキャッシュを使い、同じ内容であれば元の文字・行・矩形レジスタの種類を保ちます。
* OSC52 による読み取り要求は出さないため、端末の応答待ちは発生しません。

* キャッシュのみの環境では、他のアプリでコピーした文字を `p` で取得できません。
  - その場合は端末側の貼り付けショートカットを使ってください。WSL の Windows コマンド呼び出しには
  - [Windows 実行ファイルとの相互運用](https://learn.microsoft.com/en-us/windows/dev-environment/wsl-interop)
  - が利用可能である必要があります。

tmux 側は下記の設定を既存の設定ファイルに追加してください。

```tmux
set -s set-clipboard on
```

tmux 内のアプリからのコピーを許可するため `on` を使います。`external` では許可されません。 \
外側の端末も OSC52 に対応し、利用を許可している必要があります。`tmux info` の `Ms` が `[missing]` の場合は、tmux 3.2以降なら外側の実際の TERM に合う `terminal-features` を追加します。 \
例えば外側が xterm-256color なら `set -as terminal-features ',xterm-256color:clipboard'` が候補です。

詳細は [tmux 公式ガイド](https://github.com/tmux/tmux/wiki/Clipboard) を参照してください。 \
この設定は tmux の通常の OSC52 処理を使い、DCS passthrough は使いません。 \
Neovim から tmux・端末・Windows の設定は自動変更しません。

## Optional Tree-sitter

`lua/tree-sitter/` で、互換性のある言語 parser と `highlights` query が runtimepath に存在する場合だけ、標準 API の Tree-sitter 強調を有効にします。 \
不足・非互換の場合は標準 syntax のままです。通常の編集バッファとヘルプが対象で、検索プレビューなどの特殊バッファは既存の表示を維持します。 \
parser の取得用に nvim-treesitter だけを任意で利用します（LSP における Mason と同じ扱い）。

| ファイル | 役割 |
| --- | --- |
| `lua/tree-sitter/init.lua` | 強調の開始、nvim-treesitter の読み込み、コマンド定義 |
| `lua/tree-sitter/nvim-treesitter.lua` | nvim-treesitter の取得・読み込み・parser のインストール |
| `lua/tree-sitter/languages.lua` | `:TreesitterInstall` で取得する言語の一覧 |

| コマンド | 操作 |
| --- | --- |
| `:TreesitterBootstrap[!]` | nvim-treesitter を `git clone` で取得して読み込む。`!` で取得し直す |
| `:TreesitterInstall [言語...]` | 未取得の parser をインストール。省略時は `languages.lua` の全て |

* nvim-treesitter は `stdpath("data")/site/pack/ex/opt/nvim-treesitter` に置き、存在する場合だけ起動時に読み込みます。 \
  `:TreesitterBootstrap` を実行するまではダウンロード・通信は行わず、同梱の parser だけで動作します。
* nvim-treesitter は `main`（0.12 以降）と `master`（0.10・0.11 向けに凍結）で互換性がないため、Neovim のバージョンに合うブランチを取得します。 \
  Neovim を更新してブランチが合わなくなった場合は起動時に警告し、`:TreesitterBootstrap!` で取得し直します（`master` の parser も削除されます）。
* parser の保存先は `main` が `stdpath("data")/site/parser`、`master` が nvim-treesitter 内の `parser/` です。
* インストールが完了すると、開いているバッファにも再起動なしで反映します。必要なコマンドが無い場合は開始前に通知します。
* nvim-treesitter を読み込むと、同梱の言語も nvim-treesitter の query が優先されます。`languages.lua` には同梱の言語も含めているので、`:TreesitterInstall` で parser も合わせて更新してください。
* 折り畳み・インデント・文脈表示は有効にしません。

## Sidebar

`Ctrl-e` で Sidebar を開閉します。初回は File Tree を表示し、次回以降は閉じた時の View・カーソル位置・スクロール位置を復元します。Sidebar 内では `Ctrl-n` / `Ctrl-p` で登録済み View を順方向 / 逆方向に切り替え、各 View の位置も保持します。Sidebar はタブごとに1ウィンドウで、View を切り替えてもウィンドウは増えません。

## File Tree

File Tree はタブごとに最大1つの共通 Sidebar に表示します。Symbol Tree に切り替えてもウィンドウは増えず、ツリーの展開状態を保持します。

| キー | 操作 |
| --- | --- |
| Ctrl-e | Sidebar の開閉。初回は File Tree、以後は最後に閉じた View を復元 |
| `:Ex` | File Tree の表示・開閉 |
| Return | ファイルを開く、ディレクトリの展開・折り畳み |
| Tab | ツリーにフォーカスを残してプレビュー |
| Ctrl-v | 垂直分割で開く |
| Ctrl-x | 水平分割で開く |
| a | 新規作成。末尾 `/` でディレクトリ作成 |
| d | 確認後に削除。ディレクトリは内容も削除 |
| r | リネーム。開いているバッファのパスも更新 |
| R | 再読み込み（Git の状態も再取得） |
| - | ルートを親ディレクトリへ移動し、タブの作業ディレクトリ（`:tcd`）も変更 |
| Ctrl-] | 選択したディレクトリ（ファイルなら親）をルートにし、`:tcd` で作業ディレクトリも変更 |
| q | ツリーを閉じる |

表示先は現在のタブ内の通常の編集ウィンドウから選びます。複数ある場合は各ウィンドウのステータスラインに出る文字で選択し、Escape で中止します。

### Git Status

nvim-tree と同様に、Git の状態を名前の色と右端の記号で表示します。`git` が無い環境では Git Signs と同じく何もしません。

| 記号 | 状態 | 色 |
| --- | --- | --- |
| ✓ | ステージ済み | Git Signs の追加行と同じ |
| ✗ | 未ステージの変更。ディレクトリは配下に変更あり | Git Signs の変更行と同じ |
| ➜ | 名前変更 | 紫 |
| ✚ | 未追跡 | シアン |
| ✖ | 削除 | Git Signs の削除行と同じ |
| ! | 競合 | 橙 |
| ◌ | 無視（`.gitignore`）。無視されたディレクトリの配下も含む | コメントと同じ |

* `git status --porcelain=v1 --ignored=matching -u` を非同期に実行して取得します。ルートと展開中のディレクトリが属するリポジトリが対象です（複数可）。
* ツリーを開いたとき・`R`・作成/削除/リネーム・ルート変更・新しいリポジトリ内のディレクトリを展開したとき、 \
  およびファイル保存・フォーカス復帰・端末や `:!` の終了後に、表示中のツリーを更新します。
* nvim-tree の記号のうち `★` と Nerd Font の記号は `ambiwidth=double` で幅が変わるため、`✚`・`✖`・`!` に置き換えています。 \
  記号と色は `lua/ex/tree.lua` 冒頭の `git_icons` で変更できます。
* 削除済みのファイルはツリーに表示されないため、親ディレクトリの ✗ でのみ分かります。

## Terminal

| キー・コマンド | 操作 |
| --- | --- |
| Ctrl-t | ノーマル・挿入・端末モードで下部端末を開閉 |
| Space t f | ノーマルモードで独立したフロート端末を開閉 |
| Escape | 端末入力からノーマルモードへ移動 |
| `:ToggleTerm [horizontal\|float]` | 指定した端末を開閉。省略時は下部端末 |

初回起動時の作業ディレクトリで、設定済みのシェルを起動します。 非表示にしてもプロセス・出力・シェルの作業ディレクトリを保持し、再表示時は入力モードに戻ります。 \
下部端末の初期高さは画面の30%で、手動変更した高さを保持します。 \
フロートは最大120列・30行で、画面内に収まるよう中央に配置します。 \
閉じると元のウィンドウに戻り、シェル終了時には対応する端末表示を閉じます。再度開くと新しいシェルが起動します。各種類のシェルはタブ間で共有し、表示ウィンドウはタブごとに管理します。

## Symbol Tree

Symbol Tree は Neovim 標準 LSP の `textDocument/definition` と `textDocument/documentSymbol` を使います。定義候補はファイル単位で整理し、ファイル内シンボルは LSP が返す親子関係を表示します。サーバーが未接続の場合は通知して終了します。

| キー・コマンド | 操作 |
| --- | --- |
| `gd` | カーソル位置の定義候補を表示。既存マッピングがある場合は上書きしません |
| `:SymbolTree` / `:SymbolTree document` | 現在ファイルのシンボルを表示 |
| `:SymbolTree definition` | カーソル位置の定義候補を表示 |
| Enter | グループの展開・折りたたみ、または定義位置へ移動 |
| Tab | 定義位置をプレビューし、Sidebar にフォーカスを戻す |
| Ctrl-v / Ctrl-x | 垂直 / 水平分割で開く |
| R | LSP から再取得 |
| q | Sidebar を閉じる |

File Tree と同じ Sidebar を共有します。View を切り替えてもウィンドウは増えません。問い合わせ後にタブや View を切り替えた場合、古い LSP 応答で現在の表示を上書きしません。

## Pairs

- `()`・`[]`・`{}`・ダブルクォート・シングルクォート・バッククォートを自動補完します。
- 閉じ文字と同じ文字が直後にある場合は、重複挿入せず右へ移動します。
- 空のペアの間で Backspace を押すと両方を削除します。
- エスケープされた引用符、単語直後の引用符はそのまま挿入します。
- 現在行の同じ引用符で囲まれた範囲内では、引用符をそのまま挿入します。
- 後ろに本文がある場合は開始文字だけを挿入します。空白・閉じ括弧・カンマ・セミコロン・
  コロンの直前ではペア補完します。
- Enter は変更しません。端末入力・特殊バッファ・paste モードでは補完しません。

引用符の判定は行単位です。構文に応じた判定・選択範囲の囲み・補完候補確定との連携は含みません。

## Jump

ノーマルモードの Ctrl-f で現在の編集ウィンドウ内に見える単語の先頭にラベルを表示し、ラベルを入力すると移動します。 \
単語はバッファの `iskeyword` に従います。 \
本文を書き換えずにラベルを描画し、選択後は消去します。バッククォート2回で移動前の位置に戻れます。 \
同じバッファを別ウィンドウで表示していても、ラベルは操作中のウィンドウだけに表示します。

## Scope

`f`/`t` または `F`/`T` を押すと、対象文字の入力待ちの間、 現在行の進行方向にある移動先の候補文字を強調します。

## Git Signs

Git 管理中のファイルを index（ステージ済み内容）と比較します。 \
未保存の編集も含め、行番号の横に印を表示し、対象の行番号にも色を付けます。 \
キーマップや Git 操作は追加しません。

| 印 | 意味 |
| --- | --- |
| + | 追加行 |
| │ | 変更行 |
| _ | この行の後ろに削除あり |
| ‾ | ファイル先頭に削除あり |
| ~ | 行の変更に加えて削除あり |

## Text Search

Leader + fg の本文検索を実装しています。 \
`rg` が利用可能なら ripgrep で検索し、ない場合は Neovim のファイル API と正規表現を使います。 \
開始時の作業ディレクトリを検索します。

検索画面には検索語、拡張子、追加の除外条件の3つの入力欄があります。拡張子には `php,js` のようにカンマ区切りで指定します（空欄なら全拡張子）。除外条件には `*.json,node_modules/` のようにファイル glob または末尾 `/` のディレクトリ名を指定します。既定の除外は常に適用されます。

| キー | 操作 |
| --- | --- |
| Ctrl-n / 下矢印 | 次の候補 |
| Ctrl-p / 上矢印 | 前の候補 |
| Return | 選択した候補の行・列へ移動 |
| Ctrl-v / Ctrl-x | 左右分割 / 上下分割で開く |
| Tab | 検索語 → 拡張子 → 除外条件 → 結果一覧の順に移動 |
| Ctrl-d / Ctrl-u | プレビューを下 / 上へスクロール |
| Ctrl-q | 現在の候補を quickfix に送る |
| Escape / Ctrl-c | 閉じて検索を中止 |

検索語は `rg` がある場合は ripgrep の正規表現、ない場合は Vim の正規表現です。どちらも大文字を含まなければ大文字小文字を区別せず、含む場合は区別します。 \
一致した行ごとに最初の一致位置を1候補として表示します。保存済みファイルを検索するため、 未保存の編集は含みません。複数行の貼り付けは空白でつなぎます。 \
隠しファイル・ignore 対象も検索しますが、`.git`・`.cache`・`Library`・`node_modules` という名前のディレクトリは除外します。シンボリックリンク、読めないファイル、NUL を含むバイナリ、 \
1MiB超のファイルも除外します。結果は最大500行です。上限に達したらパターンを絞り込んでください。 \
タイトルに進行状況を表示します。画面サイズ変更時は検索画面を閉じます。

## LSP (Optional Mason)

`lua/lsp/` に Neovim 標準の `vim.lsp.config` / `vim.lsp.enable` による LSP 設定を置きます。 \
0.10 以前は `lua/lsp/fallback.lua` が `vim.lsp.start` で同じ設定・同じ動作（filetype と root_markers による自動接続）を再現します。 \
プラグインマネージャーは使わず、言語サーバーの取得用に mason.nvim だけを任意で利用します。

| ファイル | 役割 |
| --- | --- |
| `lua/lsp/init.lua` | 言語ファイルの読み込み、有効化、コマンド定義 |
| `lua/lsp/mason.lua` | mason.nvim の取得・読み込み |
| `lua/lsp/fallback.lua` | `vim.lsp.config` / `vim.lsp.enable` が無い環境（0.10 以前）向けの代替実装 |
| `lua/lsp/servers/<言語>.lua` | 言語ごとのサーバー設定 |

| コマンド | 操作 |
| --- | --- |
| `:MasonBootstrap` | mason.nvim を `git clone` で取得して読み込む |
| `:LspInstall [言語...]` | `servers/` に定義したサーバーを Mason でインストール。省略時は全て |

* mason.nvim は `stdpath("data")/site/pack/ex/opt/mason.nvim` に置き、存在する場合だけ起動時に読み込みます。 \
  `:MasonBootstrap` を実行するまではダウンロード・通信は行わず、プラグインなしの状態を保ちます。
* サーバーは実行ファイルが見つかる場合だけ有効にします。Mason 以外で PATH に入れたものも使えます。 \
  Mason でインストールが完了すると、再起動なしで有効になります。
* npm・Go などサーバーごとに必要な実行環境は自動では入れません。
* 削除する場合は `stdpath("data")` 配下の `site/pack/ex/opt/mason.nvim` と `mason/` を消します。

用意済みの言語と、Mason でのインストールに必要な実行環境です。

| ファイル | 対象 | サーバー | 必要な実行環境 |
| --- | --- | --- | --- |
| `c.lua` | C / C++ | clangd | unzip、標準ヘッダ用に gcc または clang |
| `asm.lua` | Assembly | asm-lsp | cargo |
| `python.lua` | Python | pyright | npm |
| `typescript.lua` | TypeScript / JavaScript | TypeScript 7+ の `tsc --lsp --stdio` | npm、プロジェクト内または `PATH` 上の TypeScript 7+ |
| `lua.lua` | Lua | lua-language-server | なし |
| `php.lua` | PHP / CakePHP | intelephense | npm |
| `bash.lua` | sh / bash | bash-language-server | npm |
| `java.lua` | Java | jdtls | Java 21 以上、python3 |
| `go.lua` | Go | gopls | go |
| `rust.lua` | Rust | rust-analyzer | 解析に cargo / rustc |
| `kotlin.lua` | Kotlin | kotlin-lsp | なし |
| `swift.lua` | Swift | sourcekit-lsp | Mason 対象外。Swift ツールチェーン同梱のものを使用 |

言語の追加は `lua/lsp/servers/<言語>.lua` を作り、以下の形式で返します（`lua.lua` を参照）。

```lua
return {
    name = "lua_ls",                 -- vim.lsp.config / enable に渡す名前
    package = "lua-language-server", -- Mason のパッケージ名（Mason を使わないなら省略可）
    requires = {},                   -- 必要な外部コマンド。"a|b" はいずれか（bin/check.sh が参照）
    -- executable = "...",           -- cmd が関数の場合に有効化判定へ使う実行ファイル名（java.lua を参照）
    config = {                       -- :help lsp-config
        cmd = { "lua-language-server" },
        filetypes = { "lua" },
        root_markers = { ".git" },
    },
}
```

TypeScript はプロジェクトの `node_modules/.bin/tsc` を優先し、なければ `PATH` 上の `tsc` を使います。バージョン 7 以降が必要です。Mason の `:LspInstall` は TypeScript 本体をインストールしません。 \
LSP 接続時に `K` は現在行の診断を優先表示し、診断がなければ Hover を表示します。フロート内の `Esc` で閉じ、Hover 内の `Ctrl-v` / `Ctrl-x` で縦 / 横分割します。`<leader>le`、`[d`、`]d` も使用できます。その他のキーマップと補完は Neovim の既定です。 \
診断（エラー・警告）は全バージョンで行末に表示します（`virtual_text`。既定値が 0.11 以降は非表示、0.10 以前は表示と異なるため明示）。

### CakePHP

`composer.json` の `require` に `cakephp/cakephp` があるプロジェクトでは、Intelephense が `.ctp` テンプレートも解析対象にし、`webroot/` があれば document root として使用します。`.ctp` は Neovim でも PHP として開きます。CakePHP 4 以降の通常の `.php` テンプレートも解析対象です。 \
CakePHP の動的なプロパティやメソッドは LSP 設定だけでは型が分からない場合があります。プロジェクトの PHPDoc を整えるか、必要に応じて `dereuromark/cakephp-ide-helper` などで注釈を生成してください。警告の一括無効化はしていません。

## Completion

`lua/completion/` で、入力中に LSP・パス・バッファ内の単語の候補を自動で表示します（nvim-cmp・cmp-path・cmp-buffer 相当）。 \
表示には組み込みのポップアップメニュー（`vim.fn.complete()`）を使い、プラグインは使いません。

| ファイル | 役割 |
| --- | --- |
| `lua/completion/init.lua` | オプション・キーマップ・自動表示のきっかけ（入力・削除） |
| `lua/completion/engine.lua` | 各ソースの候補を集めて絞り込み（あいまい一致）・結合して表示 |
| `lua/completion/sources/lsp.lua` | 接続中の LSP サーバーの `textDocument/completion` |
| `lua/completion/sources/path.lua` | `./`・`../`・`~/`・`/` などで始まるパスの中身。相対パスは編集中のファイルの位置が基準 |
| `lua/completion/sources/buffer.lua` | 現在のバッファ内の単語（3文字以上） |

| キー（挿入モード） | 操作 |
| --- | --- |
| Tab / Ctrl-n | 次の候補（メニューが無い場合は通常の動作） |
| Shift-Tab / Ctrl-p | 前の候補（同上） |
| Return | 選択中の候補で確定。未選択なら閉じて改行 |
| Ctrl-Space | 手動で開く |
| Ctrl-e / Backspace / Escape | キャンセルして入力していた文字に戻す（Escape はそのままノーマルモードへ） |

* 候補は LSP・パス・バッファの順に並べ、同じ文字列は先のものだけを残します。
* LSP への要求は単語の入力中・サーバーのトリガー文字（`.` など）・手動の場合のみで、入力が続く間はまとめて送ります。
* LSP の候補が置き換え範囲（`textEdit`）を持つ場合はその範囲に従います（`items.f` → `items.fill` など）。
* Return で確定した LSP の候補は、スニペットを展開し（`vim.snippet`、0.10 以降。0.9 は文字列のみ挿入）、import などの追加の編集も適用します。
* キャンセル後は、次に文字を入力するまで自動では開きません。Backspace は、候補を選んでいなければ Pairs の動作（空のペアの削除）のままです。
* 0.12 の `'autocomplete'` は、LSP（非同期）の結果が他の候補を置き換えてしまい LSP・パス・バッファを1つにまとめられないため使わず、全バージョンで同じ実装を使います。 \
  候補の説明の表示（`completeopt` の `popup`）は 0.10 以降です。あいまい一致の順位は Neovim の `matchfuzzy()` に従うため、バージョンにより多少異なります。
