---
description: 現在のブランチの差分を読み取り専用でレビューする（修正・コミットはしない）
allowed-tools:
  [
    Agent,
    Read,
    "Bash(.claude/scripts/verify:*)",
    "Bash(.claude/scripts/review:*)",
  ]
---

現在のブランチの変更内容（未コミット・未追跡のファイルを含む）を、`/review-issue` と同じ `reviewer` エージェントで読み取り専用レビューする。Issue を指定しないブランチ差分レビューの入口で、受入条件の照合を除けば `/review-issue` と同じ手順・同じ判定になる。

## 引数

- `$ARGUMENTS`（任意）: `-- <pathspec>...` でレビュー範囲を絞る。Issue に対してレビューする場合は `/review-issue <issue>` を使う

## 手順

1. `.claude/scripts/verify status` で現在の差分に対する検証証跡を確認する。`VALID` でなければ `.claude/scripts/verify run` を実行する
   - lint / test などの検証はこの共通入口だけで行う。検証コマンドを manifest から推測して独自に実行しない
   - 結果が `FAIL` / `BLOCKED` でもレビューは続ける（packet に記録され、PASS にはならない）
2. `.claude/scripts/review build [-- <pathspec>...]` で packet を作る
   - ベースは `develop` → `main` の順で自動検出する。別のベースは `--base <ref>` で指定する
   - 出力の `review_id` と `packet` のパスを控える。packet の中身はここで読まない
3. Agent ツールで `subagent_type: reviewer` を起動する。プロンプトには次だけを渡す
   ```
   review_id: <review_id>
   packet: <packet のパス>
   この packet をレビューし、定義どおりの形式で結果を返してください。
   ```
   - 実装の経緯・会話の要約は渡さない
4. reviewer の出力を変更せずに `.claude/scripts/review record <review_id>` の標準入力に渡す（heredoc を使う）
5. 次をユーザーに報告する
   - `record` が出した最終判定（`PASS` / `CHANGES_REQUESTED` / `BLOCKED`）と理由
   - reviewer の「レビュー範囲」「指摘」（Critical / Warning / Info、ファイル・行付き）「未確認事項」
   - 結果ファイルのパス

観点は `.claude/review-patterns.md`、判定基準と出力形式は `.claude/agents/reviewer.md` にある。

## 指摘の修正

このコマンドは指摘を修正しない・コミットしない・PR にコメントしない。修正が必要な場合は、ユーザーの指示を受けて明示的な実装ステップ（`/start-with-plan` や個別の修正依頼）で行い、その後もう一度 `/code-review` を実行する。レビュー後に差分や検証証跡が変わると、`.claude/scripts/review status` は以前の結果を `STALE` と判定する。
