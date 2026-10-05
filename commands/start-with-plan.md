---
description: 実装計画ドキュメントに基づいて実装を開始する
allowed-tools:
  [Agent, Bash, Read, Write, Edit, Grep, Glob, TaskCreate, TaskUpdate]
args: path
---

指定された実装計画ドキュメントに基づき、implementer エージェントのワークフローで実装を進める。

## 引数

- `$ARGUMENTS`: 実装計画ドキュメントのパス（例: `docs/tasks/add-overlay-mode.md`）
  - `docs/tasks/` を省略した場合は自動的に補完する

## ワークフロー

1. 実装計画ドキュメント `$ARGUMENTS` を読み込む
   - パスに `docs/tasks/` が含まれていなければ `docs/tasks/$ARGUMENTS` として読む
2. ドキュメントの内容を把握し、実装ステップを TaskCreate で TODO リストとして作成する
3. 各ステップを順番に実装する
   - 既存コードへの影響を確認してから変更する
   - プロジェクトの既存のコード規約・設計に倣う
4. 各ステップ完了時に TaskUpdate でステータスを更新する
5. 全ステップ完了後、`.claude/scripts/verify run` で検証する（implementer エージェントのワークフロー手順 5 と同じ扱い）
   - `FAIL` は修正して再実行する。`BLOCKED` は理由を報告し、PASS として扱わない
6. 適切な粒度でコミットする
7. 完了報告を出力する

## 全体フロー

```
/create-task → /start-with-plan → /code-review → /pr-create
```

実装完了後、`/code-review` でレビューし、`/pr-create` で PR を作成する。
