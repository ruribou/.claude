# review — 読み取り専用レビューの packet と結果の仕様

`scripts/review`（配置後は `.claude/scripts/review`）は、読み取り専用の `reviewer` エージェント（`agents/reviewer.md`）に渡すレビュー対象を用意し、レビュー結果を対象スナップショットに結び付けて記録する。`/implement-issue`・`/review-issue`・`/code-review` が共通で使う。`bash` と `git` だけを使い（Issue 番号指定時のみ `gh`）、作業ツリー・index・HEAD を変更しない。

レビュアー自身は Read / Glob / Grep しか持たないため、差分の取得・検証証跡の確認・結果の保存は呼び出し側がこのスクリプトで行う。

## 流れ

```
verify status / run          検証は共通入口で（レビュアーは実行しない）
        ↓
review build                 packet を作る（差分・未追跡ファイル・検証証跡・Issue 本文）
        ↓
reviewer エージェント        packet を読んで VERDICT と根拠を返す（読み取り専用）
        ↓
review record <id>           結果を保存し、PASS の条件を機械的に確認する
        ↓
review status                現在の入力で結果が有効か判定する
```

## コマンド

| コマンド | 内容 | 終了コード |
| --- | --- | --- |
| `review build [--base <ref>] [--issue <n> \| --issue-file <path>] [-- <pathspec>...]` | packet を作り、`review_id` と packet のパスを表示する | `0` / エラー時 `2` |
| `review record <review_id>` | stdin のレビュー結果を記録し、最終判定を表示する | `0`=PASS / `1`=CHANGES_REQUESTED / `2`=BLOCKED |
| `review status [<review_id>]` | 結果が現在の入力に対して有効な PASS か判定する（省略時は最新） | `0`=VALID / `1`=STALE・NOT_PASS・NONE |

## レビュー対象（packet）

| 項目 | 内容 |
| --- | --- |
| base | `--base` の ref（省略時は `origin/develop` → `origin/main` → `develop` → `main`）と HEAD の merge-base。ベースがなければ空ツリー |
| head | `HEAD` のコミットに、staged / unstaged の変更と ignore されていない未追跡ファイルを加えたスナップショット |
| 差分 | `git diff <base>`（追跡ファイルの追加・削除・モード変更）と、未追跡ファイルの全内容（`/dev/null` との差分） |
| 範囲 | pathspec を指定すればその範囲だけ。変更ファイル一覧（`tracked` / `untracked`）を packet と結果に明記する |
| fingerprint | `verify fingerprint` と同じスナップショット識別子 |
| 検証証跡 | `verify status` の結果（`VALID` / `STALE` / `NOT_PASS` / `NONE`、verify がなければ `UNAVAILABLE`）と `evidence.json` |
| Issue | `--issue <n>` は `gh issue view` で、`--issue-file` はファイルから取得した本文。取得できなければ `unavailable` |

Issue 本文と差分は、build ごとに変わる境界文字列（`UNTRUSTED-…`）で囲んだデータとして packet に入れる。スクリプトはこれらを評価・実行しない。

## 結果

レビュアーは `agents/reviewer.md` の出力形式で返し、呼び出し側はそれを変更せずに `record` の stdin に渡す。`record` は次の順で最終判定を決める。

| 最終判定 | reason | 条件 |
| --- | --- | --- |
| BLOCKED | `malformed_result` | `VERDICT: PASS\|CHANGES_REQUESTED\|BLOCKED` 行がない |
| BLOCKED | `review_id_mismatch` | `REVIEW_ID:` が対象の review と一致しない |
| BLOCKED | `findings_without_location` | CHANGES_REQUESTED なのに `- [Critical\|Warning\|Info] <path>:<line>` 形式の指摘がない |
| CHANGES_REQUESTED | `pass_with_findings` | PASS なのに Critical / Warning の指摘がある |
| BLOCKED | `empty_scope` | PASS だが変更ファイルがない |
| BLOCKED | `verification_not_valid` | PASS だが build 時の検証証跡が `VALID` でない |
| BLOCKED | `acceptance_criteria_missing` | PASS だが Issue モードで Issue を取得できていない |
| BLOCKED | `inputs_changed_during_review` | build から record までの間に入力が変わった（CHANGES_REQUESTED はそのまま残す） |
| PASS / CHANGES_REQUESTED / BLOCKED | `ok` / `reviewer_changes_requested` / `reviewer_blocked` | 上記以外はレビュアーの判定どおり |

## 鮮度

build 時に次の入力から `input_key` を作り、`record` と `status` で再計算して比較する。

- base の merge-base
- fingerprint（HEAD・staged・unstaged・未追跡ファイル・verify の追加入力・verify 設定）
- 検証証跡の状態と run_id
- Issue の取得状態と本文のハッシュ
- pathspec

どれかが変われば `status` は `STALE` を返し、以前の PASS は無効になる。レビュー後の編集・再検証・ベースの更新・Issue 本文の編集がこれに当たる。

## 保存先

既定で `<git-dir>/claude-review/`（`CLAUDE_REVIEW_STATE_DIR` で変更可）。作業ツリーの外なのでコミットされず、どこにも送信しない。

```
<git-dir>/claude-review/
├── latest                 最新の review_id
└── <review_id>/
    ├── packet.md          レビュアーに渡す packet
    ├── diff.patch         差分（packet にも含まれる）
    ├── meta               build 時の条件（key=value）
    ├── pathspec           pathspec（1 行 1 件）
    ├── result.md          レビュアーの出力（そのまま）
    └── result             最終判定（key=value: result / reason / reviewer_verdict / findings / input_key）
```

linked worktree では `<git-dir>` が作業ディレクトリの外にある。レビュアーが packet を Read できない場合は `BLOCKED` を返すので、必要なら Claude Code の `additionalDirectories` にそのディレクトリを加える。

## 対象外

人間レビューの置き換え、検出率の保証、自動 approve / merge / PR コメント投稿、レビュー結果の改ざん防止。PASS は確認した範囲の結果であり、人間の承認や完全な正しさの保証ではない。
