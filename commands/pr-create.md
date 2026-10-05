---
description: PRを作成する
allowed-tools: [Read, Grep, Glob, "Bash(git:*)", "Bash(gh:*)", "Bash(.claude/scripts/verify:*)"]
---

現在のブランチの変更内容から Pull Request を作成する。

## 手順

1. `git status` と `git log` で現在のブランチの状態と変更内容を確認する
   - 現在のブランチが `main` / `develop` なら作業ブランチを作成してから進める
2. 未コミットの変更を、このタスクの変更と既存の無関係な変更に分ける
   - タスクの変更はパスを指定して add し、コミットする（`git add -A` / `git add .` で無関係な変更を巻き込まない）
   - 所有範囲が判断できない変更があれば、コミットせず利用者に確認する
3. ベースブランチを特定する（`develop` → `main` の順で存在するものを使う。以降 `<base>`）
4. `git diff origin/<base>...HEAD` でベースブランチからの差分を確認する
5. `.claude/scripts/verify status` で現在の差分に対する検証証跡を確認する。`VALID` でなければ `.claude/scripts/verify run` を実行する
   - 結果が `PASS` でなければ（`FAIL` / `BLOCKED`）PR 作成を中断し、理由を報告する
   - 検証コマンドを manifest から推測して独自に実行しない
6. 変更内容を分析し、PR のタイトルとサマリを作成する
7. `git fetch` してリモートの作業ブランチとの差を確認し、push する
   - 未 push なら `git push -u origin <branch>`
   - rebase などで履歴を書き換えた場合は `git push --force-with-lease=<branch>:<確認したリモートの OID> origin <branch>`。リモートに自分の知らない commit があれば上書きせず停止する（`.claude/scripts/git-guard.md`）
8. `gh pr create` で PR を作成する

## PR 作成フォーマット

`.github/pull_request_template.md` が存在する場合はそのテンプレートに従う。存在しない場合は以下のフォーマットを使用する。

```
gh pr create --base <base> --title "<タイトル>" --body "$(cat <<'EOF'
## 概要
<変更の目的と概要>

## 細かい変更点
<具体的な変更点の箇条書き>

## 影響範囲・懸念点
<影響範囲や懸念点。なければ「なし」>

## その他
<その他伝えておきたいこと。なければ「なし」>
EOF
)"
```

## ルール

- タイトルは 70 文字以内で簡潔にする
- ベースブランチは自動検出する（`develop` があれば `develop`、なければ `main`）
- PR の URL を最後に表示する
