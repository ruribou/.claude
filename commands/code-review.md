---
description: （互換入口）Issue を指定せず、現在のブランチ差分を読み取り専用でレビューする
allowed-tools:
  [
    Agent,
    Read,
    "Bash(.claude/scripts/verify:*)",
    "Bash(.claude/scripts/review:*)",
  ]
argument-hint: "[-- <pathspec>...]"
---

Issue を指定しないブランチ差分レビューの互換入口。手順はここに持たず、`.claude/commands/review-issue.md` を正本とする（同じ `reviewer` エージェント・同じ `.claude/scripts/review`・同じ判定）。通常の Issue 実装では `/implement-issue <issue>` がレビューまで行うため、このコマンドを手動で実行する必要はない。

## 引数

- `$ARGUMENTS`（任意）: `-- <pathspec>...` でレビュー範囲を絞る。Issue 番号は受け付けない（Issue に対してレビューする場合は `/review-issue <issue>`）

## 手順

1. `.claude/commands/review-issue.md` を読み、**Issue 指定なし** としてその手順どおりに進める
   - packet は `--issue` / `--issue-file` を付けずに作る。受入条件の照合は行わない
2. 指摘の修正・コミット・投稿はしない（`/review-issue` と同じ）
