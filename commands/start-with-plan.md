---
description: （互換入口）実装計画ドキュメントを入力に /implement-issue --plan と同じフローを進める
allowed-tools:
  [
    Agent,
    AskUserQuestion,
    Read,
    Write,
    Edit,
    Grep,
    Glob,
    TaskCreate,
    TaskUpdate,
    "Bash(git:*)",
    "Bash(gh:*)",
    "Bash(.claude/scripts/verify:*)",
    "Bash(.claude/scripts/review:*)",
    "Bash(.claude/scripts/checkpoint:*)",
  ]
args: path
---

実装計画ドキュメントを入力として、`/implement-issue` と同じ実装フローを進める互換入口（旧名を残すための薄い委譲）。手順・状態はここに持たず、`.claude/skills/implement-issue/SKILL.md` を正本とする。新しく使う場合は `/implement-issue --plan <path>` を使う。

## 引数

- `$ARGUMENTS`: 実装計画ドキュメントのパス（例: `docs/tasks/add-overlay-mode.md`）
  - `docs/tasks/` を省略した場合は自動的に補完する（`add-overlay-mode.md` → `docs/tasks/add-overlay-mode.md`）
  - ファイルが無ければ、`docs/tasks/` の候補を示して終了する
  - 引数を Issue 番号として解釈しない（数字だけが渡されても Issue モードに変換せず、`/implement-issue <issue>` を案内して終了する）

## 手順

1. 上記の規則で計画ファイルのパスを決める
2. `.claude/skills/implement-issue/SKILL.md` を読み、入力を `--plan <決めたパス>` として、その手順どおりに進める
   - 中断した run があれば、同じ手順の「既存の checkpoint を確認する」で再開する
