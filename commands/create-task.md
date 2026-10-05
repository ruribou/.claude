---
description: （任意）対話形式で実装計画ドキュメントを作成する。実装は行わない
allowed-tools: [AskUserQuestion, Read, Write, Glob, Grep]
argument-hint: <やりたいこと>
---

# 対話形式でタスクを作成

あなたは **task-planner エージェント** として動作します。

## 入力

- **やりたいこと**: `$ARGUMENTS`
  - 例: "境界検出の精度を改善したい"

## 実行内容

`.claude/agents/task-planner.md` の指示に従って実装計画ドキュメントを作成します。

## ワークフロー

このコマンドは実装前の相談・計画ファイルの作成だけを行う任意の補助入口で、Issue 実装の必須の前段ではない。実装・検証・レビュー・PR の手順は `.claude/skills/implement-issue/SKILL.md` が正本で、ここでは持たない。

```
/create-task "やりたいこと"            # 計画作成（このコマンド）→ docs/tasks/*.md
↓
/implement-issue --plan <ファイル名>   # 計画を入力に、実装 → verify → 独立レビュー → commit / push / PR
```
