# command-guard — git / gh 以外の破壊的コマンドの確認

`scripts/command-guard`（配置後は `.claude/scripts/command-guard`）は PreToolUse の Hook。Bash ツールで実行されるコマンドのうち、**取り返しのつかない削除・初期化・権限の書き換え** だけを実行前に止める。git / gh は [`git-guard`](git-guard.md) が見るので対象外。

`settings.json` は git / gh 以外のコマンドを許可していないため、通常は Claude Code の権限確認が先に出る。この Hook が効くのは、権限確認を省略する実行（bypass permissions、利用者が広い許可を足した場合など）で、確認なしに実行されうるときの最後の歯止めになる。

- Hook は `allow` を返さない（権限を広げない）。止めるときだけ `deny`（対象を直せば進められる）か `ask`（利用者の判断が必要）を返す
- 字句解析は git-guard と共有の [`lib/tokenize.awk`](lib/tokenize.awk)。引用符の中・heredoc の本文に書いただけのコマンド（`echo "rm -rf /"`、コミットメッセージ）は止めない

## 判定

| 状況 | 判定 |
| --- | --- |
| `rm -r` の対象が `/`・`~`・`.`・`..`・`*`・`/*`・`./*`・システム領域（`/usr` `/etc` `/System` `/Users` など） | deny |
| `rm --no-preserve-root` | deny |
| `rm -r` の対象に変数・コマンド置換が含まれる（`rm -rf "$DIR/"`。空になると上位を消す） | ask |
| `dd` の `of=` がデバイス（`/dev/null` などを除く） | deny |
| `mkfs*` / `newfs*` / `wipefs`、`diskutil erase*` 等 | deny |
| `fdisk` / `sfdisk` / `gdisk` / `parted`、`shred` | ask |
| `chmod` / `chown` / `chgrp` の `-R` で対象が `/`・`~`・システム領域 | deny |
| `chmod -R 777`（`a+rwx` 等）をそれ以外の場所に | ask |
| `find` の起点が `/`・`~`・システム領域で、`-delete` か `-exec rm` を伴う | deny |
| `bash -c` / `sh -c` / `eval` / `xargs` / heredoc を渡したシェル経由で、上の破壊的な形を含む | ask |
| リダイレクトでブロックデバイス（`> /dev/sda` など）に書き込む | ask |
| 引用符が閉じていない等で解析できず、対象のコマンド名を含む | ask |
| `jq` が無く、対象のコマンド名を含む | ask |

- `sudo` / `doas` / `env` / `nice` / `ionice` / `timeout` などの前置きと、その引数付きオプション（`sudo -u root` 等）は読み飛ばして本体のコマンドを判定する
- `find` / `chmod` 系では `.` や `./x` のような相対パスは対象にしない（`find . -name '*.pyc' -delete`、`chmod -R u+w .` は日常的に使うため）。`rm -r` だけは `.` と `*` も止める
- 保護するパスは環境変数 `CLAUDE_COMMAND_GUARD_PROTECTED`（空白区切り）で追加できる。`settings.json` の `env` に書く

## 限界

- シェルの完全な構文解析ではない。alias・関数・スクリプトファイルの中身・動的なコマンド名（`$RM -rf /`）は判定しない
- パスは文字列として比べる。シンボリックリンクや `cd` 後の相対パス（`cd / && rm -rf usr`）は解決しない
- プロジェクト固有の危険操作（本番 DB の削除、クラウド資源の破棄など）は対象外。必要なら利用側で別の Hook を足す
- `deny` / `ask` は Claude Code の Hook の範囲で働く。OS レベルの隔離や、Hook を経由しない操作は対象外

## 確認方法

stdin に Hook 入力を渡せば単体で試せる。出力が空なら通過。

```bash
jq -n --arg c 'rm -rf /' '{tool_input:{command:$c}}' | .claude/scripts/command-guard
```
