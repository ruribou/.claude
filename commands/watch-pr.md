---
description: PR の CI を監視し、落ちたら根本原因を直して green になるまで回す
allowed-tools:
  [
    Agent,
    Read,
    Glob,
    Grep,
    "Bash(git:*)",
    "Bash(gh:*)",
    "Bash(.claude/scripts/verify:*)",
    "Bash(.claude/scripts/review:*)",
  ]
argument-hint: "[PR番号]（省略時は現在のブランチの PR）"
---

作成済みの PR の CI（GitHub Actions 等の check）を監視し、失敗したら原因を特定して修正・検証・レビュー・push し、green になるまで繰り返す。`/implement-issue` が PR を作った後の段階を補う入口で、PR 作成や merge はしない。

## 引数

- `$ARGUMENTS`: PR 番号。省略時は `gh pr view --json number -q .number` で現在のブランチの PR を使う
- 対象は自分の作業 branch の PR だけ。他人・bot の PR は push 前に利用者に確認する

## 手順

1. 対象を確定する
   - `gh pr view <n> --json number,url,headRefName,baseRefName,state,isCrossRepository` で PR と head branch を取得する
   - 現在の branch が head branch と一致しなければ停止して報告する（branch を切り替えて進めない）
   - 状態が OPEN でなければ停止する
2. check を待つ
   - `gh pr checks <n> --watch --interval 60` を **バックグラウンドで**実行する（Bash の `run_in_background`）。終了時に再開されるので、フォアグラウンドで待たない
   - check が 1 つも設定されていなければ「CI なし」と報告して終える
3. 結果で分岐する
   - すべて成功 → `gh pr view <n> --json mergeable,mergeStateStatus` を確認し、手順 6 へ。`CONFLICTING` なら競合の状況を報告して止まる（rebase / merge の判断は利用者に委ねる）
   - 失敗あり → 手順 4 へ
4. 失敗を 1 件ずつ調べる
   - ログを読む: `gh run view <run_id> --log-failed`（check の詳細 URL から run_id を取る）。GitHub Actions 以外でログを取れなければ、取れない旨を報告して止まる
   - project-knowledge Skill の索引に、エラーメッセージに合う既知のトラブルシュートがあれば先に読む
   - 原因の仮説を 2〜3 個挙げ、ログで絞る
   - ローカルで再現させる: `.claude/scripts/verify run`。CI と同じ検証が `verify.conf` に無い場合は、その旨を記録し、ログの根拠だけで進める（検証コマンドを推測して実行しない）
   - 再現しない・ログからも原因が絞れない場合は flaky を疑い、`gh run rerun <run_id> --failed` で **1 回だけ**再実行する。それでも落ちれば手順 5 へ。green になっても、時刻依存・順序依存などの原因を報告に残す
   - 原因が CI 基盤・権限・secret の不足など、コードで直せないものなら手順 7 で止まる
5. 修正する（`/implement-issue` の修正段階と同じ流れ）
   - Agent ツールで `subagent_type: implementer` を修正モードで起動する。渡すのは PR 番号・失敗した check 名・ログの抜粋・特定した原因の一文・触らないパス
   - `.claude/scripts/verify run` で検証し、`.claude/scripts/review build` → `reviewer` → `.claude/scripts/review record` でレビューする（手順は `commands/review-issue.md` と同じ）
   - verify が `PASS`、review が `PASS` になってから push する。push は `.claude/scripts/git-guard.md` に従う（作業 branch への通常の push。force push しない）
   - 手順 2 に戻る
6. 報告する（後述の形式）
7. 止まる条件（理由と必要な判断を示して停止する）
   - 修正 push が 3 サイクル（`/implement-issue` の試行上限と同じ既定値）で green にならない
   - 同じ原因に同じ修正をもう一度入れようとしている
   - コードで直せない失敗、競合、保護ルールの回避が必要

## 修正の判断基準

修正は **根本原因** に対して行う。バグ修正の判断は `.claude/bugfix-discipline.md` に従う。

- **根本対処**: 「なぜ落ちたか」の説明が不要になる修正。決め手は、再発条件そのものが消えているか
- **症状パッチ**: 落ちた事実だけを隠す修正（assertion を緩める / テストを skip する / lint の抑制コメントを足す / タイムアウトを延ばす）。これが根本対処である根拠を一文で言えるときだけ選び、その一文を commit メッセージに書く
- commit メッセージには「何が・なぜ落ちたか」を一文で書く
- 1 回目で直らなかった修正の上にパッチを積まない。仮説から立て直す

## 知見の蓄積

原因が **他の PR でも再発しうる一般的なもの** なら、`skills/project-knowledge/templates/troubleshooting.md` の書式で記入案を作り、報告に含める。`references/` への追記は利用者の確認を得てから行う（project-knowledge Skill の「書き込みについて」）。タスク固有のタイポ・実装ミスは対象外。

## 報告形式

```
## /watch-pr: GREEN | BLOCKED
- PR: <URL>
- check: <名前> ✅ / <名前> ✅
- mergeable: <MERGEABLE / CONFLICTING / UNKNOWN>
- 修復サイクル: <n> 回
  - [1] <原因の一文> → <修正内容>（commit <sha>、verify <run_id>、review <review_id>）
- flaky として再実行したもの: <なければ「なし」>
- トラブルシュートの記入案: <なければ「なし」>
- 未確認事項: <...>
```

## してはいけないこと

- 対象 PR の head branch 以外への commit / push、統合ブランチへの操作
- force push（履歴の書き換えが必要なら止まって利用者に確認する）
- CI 設定（`.github/workflows/` など）を変更して check を無効化・緩和する
- `--admin` などで保護ルールを回避する、PR を merge する
- 検証・レビューが `PASS` でない commit を push する
