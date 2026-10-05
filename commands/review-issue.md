---
description: Issue の受入条件に対して現在の差分を読み取り専用でレビューする
allowed-tools:
  [
    Agent,
    Read,
    "Bash(.claude/scripts/verify:*)",
    "Bash(.claude/scripts/review:*)",
  ]
argument-hint: "<issue> [-- <pathspec>...]"
---

指定した Issue の受入条件に対して、現在のブランチの差分（未コミット・未追跡のファイルを含む）を `reviewer` エージェントで読み取り専用レビューする。この入口は修正・コミット・投稿を行わない。

単独レビューの **手順の正本**。`/code-review`（Issue 指定なしの互換入口）はこの手順を参照する。`/implement-issue` の中のレビューも同じ `.claude/scripts/review` と `reviewer` を使うため、通常の Issue 実装ではこのコマンドを手動で実行する必要はない。

## 引数

- `$ARGUMENTS`: Issue 番号（例: `4` / `#4`。先頭の `#` は外して渡す）。続けて `-- <pathspec>...` でレビュー範囲を絞れる（例: `4 -- src/auth`）
- Issue を取得できない環境では `--issue-file <path>` で受入条件のテキストを渡せる
- `/code-review` から呼ばれた場合は Issue 指定なし。手順 2 で `--issue` / `--issue-file` を付けない

## 手順

1. `.claude/scripts/verify status` で現在の差分に対する検証証跡を確認する。`VALID` でなければ `.claude/scripts/verify run` を実行する
   - lint / test などの検証はこの共通入口だけで行う。検証コマンドを manifest から推測して独自に実行しない
   - 結果が `FAIL` / `BLOCKED` でもレビューは続ける（packet に記録され、PASS にはならない）
2. `.claude/scripts/review build [--issue <番号> | --issue-file <path>] [-- <pathspec>...]` で packet を作る
   - ベースは `develop` → `main` の順で自動検出する。別のベースは `--base <ref>` で指定する
   - 出力の `review_id` と `packet` のパスを控える。packet の中身はここで読まない
3. Agent ツールで `subagent_type: reviewer` を起動する。プロンプトには次だけを渡す
   ```
   review_id: <review_id>
   packet: <packet のパス>
   この packet をレビューし、定義どおりの形式で結果を返してください。
   ```
   - Issue 本文・実装の経緯・会話の要約は渡さない（packet に含まれるものだけを根拠にさせる）
4. reviewer の出力を変更せずに `.claude/scripts/review record <review_id>` の標準入力に渡す（引用符付きの heredoc で、区切りは `REVIEW_RESULT_<review_id>` のように本文と衝突しないものにする）
   - `record` は PASS の条件（検証証跡が `VALID`・受入条件を取得済み（Issue 指定時）・変更ファイルあり・Critical / Warning なし・レビュー中に入力が不変）を機械的に確認し、満たさなければ判定を落とす
5. 次をユーザーに報告する
   - `record` が出した最終判定と理由（reviewer の判定と異なる場合は両方）
   - reviewer の「レビュー範囲」「受入条件」「指摘」（Critical / Warning / Info、ファイル・行付き）「未確認事項」
   - 結果ファイルのパス

観点は `.claude/review-patterns.md`、判定基準と出力形式は `.claude/agents/reviewer.md` にある。

## してはいけないこと

- 指摘を修正する・コミットする・Issue / PR にコメントする・approve / merge する
- 修正が必要な場合は、ユーザーの指示を受けて実装側（`/implement-issue <issue>` の再実行や個別の修正依頼）で行う。修正後は再度レビューする

## 結果の鮮度

`.claude/scripts/review status` で、最新の結果が現在の入力（差分・ベース・検証証跡・Issue 本文）に対して有効な PASS かを確認できる。レビュー後にファイルを編集したり検証をやり直したりすると `STALE` になり、古い PASS は使えない。
