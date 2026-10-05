# git / gh の自律実行と git-guard

開発に必要な git / gh 操作は、状態を自分で確認したうえで利用者への承認なしに進める。操作名だけを理由に止めず、**対象違い・他者の更新の消失・未保存変更の破棄** が起こりうるときだけ止める。

- 権限: `settings.json` が `Bash(git:*)` / `Bash(gh:*)` を許可し、範囲外の操作（認証・秘密・repo 管理・個人設定）を `deny` する
- 状態確認: `scripts/git-guard` を PreToolUse / PostToolUse の Hook として登録し、実行直前の状態と照合する
- Hook は `allow` を返さない（権限を広げない）。止めるときだけ `deny`（Claude 自身が手順を直せる）か `ask`（利用者の判断が必要）を返す

## 3 段階の判断

### 1. 確認できることは自分で確認する

会話の記憶や checkpoint ではなく、実際の git / gh から取得する。全履歴を読み直さず、判断に必要な現在状態と限定した差分だけを見る。

| 確認すること | 取得方法の例 |
| --- | --- |
| repo / remote / 作業 branch / 統合先 | `git remote -v`、`git branch --show-current`、統合先は `develop` → `main` の順 |
| 作業対象の変更と既存の無関係な変更の区別 | `git status --short`（staged / unstaged / untracked） |
| remote の最新とローカルの差 | `git fetch` 後に `git rev-list --left-right --count origin/<b>...HEAD`、必要なら `git ls-remote` |
| 検証が公開・統合する差分に対応しているか | `.claude/scripts/verify status`（あれば） |
| 対象 PR・統合先・CI・レビュー条件 | `gh pr view <n> --json baseRefName,headRefName,headRefOid,mergeStateStatus,reviewDecision,statusCheckRollup` |

### 2. 条件を満たせば通常操作として実行する

| 操作 | 進めてよい条件・手順 |
| --- | --- |
| 読み取り、`fetch`、branch 作成 / 切替 | なし |
| `add` / `commit` | 作業対象のファイルだけをパス指定で add する。既存の無関係な変更は含めない。統合ブランチに直接 commit しない |
| 通常の `push`、PR 作成・更新 | 作業 branch への push。統合ブランチへ直接 push しない |
| 作業 branch の `rebase` | 1) `git status` で未コミット変更が無いこと（作業対象ならコミット、無関係なら保全方法を確認。保全できなければ停止）<br>2) `git update-ref refs/claude-backup/<branch>/<UTC時刻> HEAD` で開始前の commit を指す永続的な ref を残す<br>3) `git rebase <base>`。競合でどちらの意図を採るか判断できなければ `git rebase --abort` して停止 |
| rebase 後の push | `git push --force-with-lease=<branch>:<確認したリモートの OID> origin <branch>`。期待 OID は直前に `git fetch` / `git ls-remote` で確認した値を明示する。書き換え前のリモートにあった commit が書き換え後に含まれる（`git cherry` で `+` が出ない）ことを確認する |
| PR の merge | 統合先・PR head・ローカルの検証対象が一致し、CI 完了・成功、レビュー条件・保護ルールを満たすとき `gh pr merge <n> --merge`（プロジェクトの統合方式に従う）。`--admin` は使わない |
| マージ済み branch の整理 | 統合先に取り込まれていること、他 worktree で使われていないことを確認して `git branch -d` |

退避 ref（`refs/claude-backup/`）は commit しか守らない。未コミット・未追跡ファイルのバックアップにはならないため、それらは別途保全を確認する。

通常操作は利用者が指定したタスクと repo の範囲に限る。権限があることだけを根拠に、無関係な Issue・repo・変更を処理しない。

### 3. 判断が必要なときだけ停止・確認する

- 他者の更新や未保存変更を失う可能性が残り、安全な別手順でも解消しない
- lease 不一致や想定外の remote 更新。無条件 force へ切り替えず、新しい先端を取り直して上書きするだけの自動再試行もしない
- repo / branch / PR / 統合先が曖昧、既存差分の所有範囲が不明、競合でどちらの意図を採るか判断できない
- repository の削除、未統合データの消去、公開範囲・権限・秘密情報・認証の変更など、通常の実装範囲を越える
- 保護ルールを回避しないと進められない、必要な検証が不足している

「確認できない」は成功扱いにしない。停止時は次を短く示す。

```
停止: <未確定事項>
行おうとした操作: <コマンドと対象 ref>
失う可能性のあるもの: <commit / ファイル / 他者の更新>
安全な選択肢: <例: fetch して差分を確認する / 退避してから進める / 利用者が統合方式を決める>
```

## git-guard の判定

`deny` は Claude が手順を直せば進められるもの（理由に次の手順を含める）、`ask` は利用者の判断が要るものに使う。

| 状況 | 判定 |
| --- | --- |
| `push --force` / `-f` / `+refspec` | deny（`--force-with-lease=<ref>:<OID>` を使う） |
| 期待 OID を省略した `--force-with-lease` | deny |
| lease の期待 OID と remote の現在値が違う（`git ls-remote` で確認） | deny（停止して報告） |
| 書き換え後に、remote にあった commit が含まれない | ask |
| 統合ブランチへの push / commit / ローカル merge / rebase | ask。統合ブランチの書き換え・削除は deny |
| 退避 ref の無い rebase、未コミット変更がある rebase | deny |
| 未コミット変更がある `reset --hard` | deny |
| どの ref からも辿れなくなる commit が出る `reset` / `branch -D` / `branch -f` / `switch -C` | ask |
| 変更を上書きする `checkout -- <path>` / `restore` / `switch -f`、未追跡ファイルを消す `clean` | ask |
| `stash drop|clear`、退避 ref の削除、`reflog expire`、`gc --prune`、`filter-branch` 等 | ask |
| `--no-verify`、`-c alias.*` / `core.hooksPath` 等、`--git-dir` / `--work-tree` | ask |
| `git config --global|--system`、`gh auth`（status 以外）、`gh secret|variable|ssh-key|gpg-key` の変更、`gh repo delete|edit|archive|rename|deploy-key`、権限・秘密・保護に関わる `gh api` の変更 | deny |
| その他の `gh api` 書き込み（`-X` 非 GET、`-f` 等）、GraphQL mutation | ask |
| `gh pr merge`: `--admin` / 状態が OPEN でない / draft / head とローカルの不一致 / 未コミット変更 / CI 失敗・未完了 / レビュー未達 / BLOCKED・BEHIND・DIRTY / 検証証跡が無効 | deny |
| `gh pr merge`: 統合先が想定と違う / merge 可否が UNKNOWN / 検証の仕組み（`scripts/verify`）が無い | ask |
| プロジェクト外の repo（`git -C`、`cd`、`gh -R`）への書き込み | ask |
| 前段で HEAD / ブランチを変える連結コマンド（`git switch x && git commit`） | deny（分けて実行する） |
| `bash -c` / `eval` / `xargs` 等を経由した git / gh、動的なコマンド名・引数、解析できない構文 | ask |

保護対象の統合ブランチは既定で `main master develop` と `origin/HEAD`。環境変数 `CLAUDE_GIT_GUARD_PROTECTED` で置き換えられる。`gh pr merge` で検証証跡を求めない場合は `CLAUDE_GIT_GUARD_REQUIRE_VERIFY=0`。

## 記録

`<git-common-dir>/claude-guard/log.jsonl` に JSON Lines で残す。コミットや送信はしない。

- `pre`: 判定（`pass` / `ask` / `deny`）、規則名、理由、操作名、repo、branch、HEAD、対象 ref、確認した OID（lease push は `ref:期待OID->新OID`）
- `post`: 実行後の HEAD と対象 ref の OID（pre で pass / ask だったもの）

コマンド本文は記録しない（引数に秘密が含まれうるため）。読み取り系の操作は記録しない。

## 限界

- シェルの完全な構文解析ではない。引用符・エスケープ・コマンド置換・heredoc・連結・リダイレクトを区切って判定し、解析できない形は ask に倒すが、未知の構文・option の並べ替え・alias 等をすべて防げるとは限らない
- 状態は実行直前の 1 時点で確認する。確認と実行の間に remote が更新される競合は、lease（git 自身の検査）が最後の防御になる
- `deny` / `ask` は Claude Code の Hook と権限設定の範囲で働く。OS レベルの隔離や、Hook を経由しない操作（利用者自身の端末操作、別ツール）は対象外
- PR の保護ルール・必須レビューの最終判定は GitHub 側。git-guard はそれを迂回しないための事前確認にとどまる
