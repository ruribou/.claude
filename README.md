# .claude

どのプロジェクトでも流用できる、汎用の [Claude Code](https://docs.claude.com/en/docs/claude-code) 設定テンプレート集。

言語・フレームワーク・デプロイ先に依存しない形で、エージェント・スラッシュコマンド・レビュー観点・トラブルシュート置き場を揃えている。任意のリポジトリのルートに `.claude/` ディレクトリとして配置するだけで使える。

## セットアップ

任意のプロジェクトのルートで、このリポジトリを `.claude/` として取り込む。

```bash
# 新規に取り込む場合
git clone git@github.com:ruribou/.claude.git .claude

# すでに .claude がある場合は中身を上書き / マージ
```

以降、Claude Code を起動するとこのディレクトリの設定が自動で読み込まれる。

## ディレクトリ構成

```
.claude/
├── README.md              このファイル
├── settings.json          共有してよい権限設定（git / gh を許可し、範囲外の操作を deny、git-guard Hook を登録）
├── settings.local.json    ユーザーローカル設定（共有しない / .gitignore 推奨）
├── review-patterns.md     言語非依存のレビュー観点チェックリスト
├── verify.conf.example    検証アダプター設定の例（プロジェクト側で verify.conf にコピー）
├── agents/
│   ├── task-planner.md    対話ヒアリング → 実装計画ドキュメント作成
│   └── implementer.md     実装フローから 1 単位を受け取り実装・コミット
├── commands/
│   ├── create-task.md     /create-task  タスク（実装計画）作成
│   ├── start-with-plan.md /start-with-plan <path>  計画ファイルから実装フローを開始（互換入口）
│   ├── code-review.md     /code-review  並列レビュー
│   ├── pr-create.md       /pr-create    PR 作成
│   └── clean-branch.md    /clean-branch マージ済みブランチ整理
├── scripts/
│   ├── checkpoint         実装フローの進行状態の保存・再開時の照合
│   ├── checkpoint.md      段階・照合・保存先の仕様
│   ├── git-guard          git / gh を実行直前の状態と照合する Hook
│   ├── git-guard.md       自律実行の判断基準・停止条件・判定表
│   ├── verify             検証の共通入口（明示した検証の実行と証跡記録）
│   └── verify.md          アダプター設定・結果・証跡の仕様
└── skills/
    ├── SKILL.md           プロジェクト固有トラブルシュート置き場（テンプレート）
    ├── implement-issue/SKILL.md  /implement-issue <issue>  1 Issue の実装フロー（手順の正本）
    └── verify/SKILL.md    /verify  検証を手動実行して結果を報告
```

## 想定ワークフロー

普段の入口は `/implement-issue <issue番号>`。1 件の Issue を、仕様確認から PR まで進める。

```
/implement-issue 12             # Issue の目的・受入条件・対象外を確認
  ├─ implementer                # 小さな実装単位ごとに実装・コミット
  ├─ .claude/scripts/verify     # 明示した検証を実行し、証跡を残す
  ├─ reviewer                   # 読み取り専用の独立レビュー（指摘は implementer が修正 → 再検証・再レビュー）
  └─ push → PR                  # 最終 commit の検証・レビュー後に push。--merge で条件を満たせば統合まで
```

計画ファイルから始める場合:

```
/create-task "やりたいこと"     # task-planner が対話でヒアリング → docs/tasks/*.md を生成
        ↓
/start-with-plan <file>         # 上と同じフローを、計画ファイルを入力にして進める
```

- フローを進めるのはメイン側（Skill を実行している会話）。implementer → verify → reviewer を順に呼び、subagent から subagent は起動しない
- 進行状態は `.claude/scripts/checkpoint` が worktree ごとのローカル checkpoint（`<git-dir>/claude-run/`）に保存する。中断後に同じコマンドを実行すると再開する
- 再開時は branch・worktree・remote・Issue 本文 / 計画を照合し、一致しない checkpoint は使わない。編集・commit・rebase で古くなった verify / review は無効化され、その段階からやり直す
- 修正サイクルが上限（既定 3 回）を超えた、解消できない指摘・権限・要件の不足がある場合は、理由と必要な判断を示して BLOCKED で止まる
- 完了と報告するのは、受入条件・verify・review・push・PR の証跡が揃ったときだけ。checkpoint には会話・Issue 本文・権限を保存しない

詳細は [`skills/implement-issue/SKILL.md`](skills/implement-issue/SKILL.md) と [`scripts/checkpoint.md`](scripts/checkpoint.md)。レビューの `/review-issue`・`.claude/scripts/review`・`agents/reviewer.md` は #4 で追加される（無い環境ではレビュー段階が BLOCKED になる）。

補助コマンド:

- `/verify` — プロジェクトが明示した検証を実行し、現在の差分に結び付いた証跡を残す（`/implement-issue` も同じ入口を使う）
- `/code-review`・`/pr-create` — レビュー・PR 作成だけを単独で行う
- `/clean-branch` — マージ済みのローカルブランチを安全に整理する

## 検証の設定

検証コマンドは推測せず、プロジェクト側で明示する。

```bash
cp .claude/verify.conf.example .claude/verify.conf   # check 行を書く
.claude/scripts/verify suggest                       # 候補の表示だけ（実行しない）
.claude/scripts/verify run                           # 0=PASS 1=FAIL 2=BLOCKED
.claude/scripts/verify status                        # 最新の証跡が現在の差分で有効か
```

証跡とログは `<git-dir>/claude-verify/` に置かれ、コミットや送信はされない。`/implement-issue`（`/start-with-plan`）・`/code-review`・`/pr-create` はこの共通入口を使う。詳細は [`scripts/verify.md`](scripts/verify.md)。

## 設計方針

- **言語非依存**: TypeScript / React / Python / Go / Rust など、どのスタックでも動くように書かれている。検証コマンド（lint / type check / test / build）はプロジェクト側の `.claude/verify.conf` で明示し、`scripts/verify` が実行する。自動検出は初回設定の候補提示（`verify suggest`）にとどめる
- **ブランチ運用**: `develop` → `main` の 2 段階を前提にベースブランチを自動検出する。`develop` が無ければ `main` を使う
- **タスクドキュメントの置き場**: `docs/tasks/{kebab-case}.md`。ディレクトリが無ければエージェントが作成する
- **レビュー観点**: 言語固有のアンチパターンではなく、セキュリティ / 設計 / 正確性・並行性 / 規約 の 4 軸で抽象的に定義
- **プロジェクト固有の知識**: `skills/SKILL.md` に追記して蓄積する。ここだけはプロジェクトごとに書き換える前提

## 権限設定

### 共有設定（`settings.json`）

- `Bash(git:*)` と `Bash(gh:*)` を自動許可する。git / gh 以外のシェルコマンド（lint / test / build、ファイル操作など）は Claude Code の権限確認を経て実行される
- 認証・秘密情報・repo 管理・個人設定を変える `gh` / `git` の一部は `permissions.deny` で拒否する
- PreToolUse / PostToolUse に `scripts/git-guard` を登録し、git / gh を実行直前の状態（作業ツリー、remote の先端、PR の状態など）と照合する。通常の branch 作成・commit・push・rebase・期待 OID 付き `--force-with-lease`・条件を満たした PR の merge は止めず、変更や他者の commit を失う可能性があるときだけ止める
- スラッシュコマンドの `allowed-tools` も `Bash` を無制限には指定せず、必要な `Bash(git:*)` / `Bash(gh:*)` に限定している

判断基準・停止条件・判定表は [`scripts/git-guard.md`](scripts/git-guard.md)。Hook は `jq` を使う（無い場合は git / gh を含むコマンドを確認に回す）。

### 追加の許可を置く場所

| 置き場所 | 用途 | 共有 |
| --- | --- | --- |
| `.claude/settings.json` | プロジェクト全員に必要な許可（このテンプレート） | する |
| `.claude/settings.local.json` | そのプロジェクトでの個人的な許可（`.gitignore` 済み） | しない |
| `~/.claude/settings.json` | 全プロジェクト共通の個人的な許可 | しない |

プロジェクト固有のビルド・テストコマンドなどは、共有が必要なら `settings.json` に、個人の好みなら `settings.local.json` に追記する。統合ブランチの名前が `main` / `master` / `develop` 以外なら、`settings.json` の `env` に `CLAUDE_GIT_GUARD_PROTECTED` を設定する。

### 設定を有効にする際の確認手順

1. Claude Code を起動して信頼ダイアログを承認し、`/permissions` と `/hooks` で有効な許可ルール・Hook とその出所（共有 / ローカル / ユーザー）を確認する（未信頼のワークスペースでは `permissions.allow` が無視される）
2. 必要に応じて `claude --setting-sources project` で共有設定だけを読み込んだ状態で起動し、git / gh 以外のコマンドで確認が求められること、`git push --force` が git-guard に止められることを確かめる

### 注意

この権限設定と git-guard は、Claude Code が確認なしに実行できる操作の範囲と、その直前の状態確認を調整するものであり、OS レベルの隔離（サンドボックス）や、悪意あるコード・プロンプトインジェクションに対する完全な防御を保証するものではない。git-guard はシェルの完全な構文解析ではなく、解析できない形は確認に回すが、すべての迂回を防げるとは限らない。

## カスタマイズ

プロジェクト固有のルール（例: フレームワーク特有のアンチパターン、独自のブランチ戦略、デプロイ手順のハマりどころ）は、汎用テンプレートを直接書き換えるのではなく、以下のいずれかで追加するのが望ましい。

- `skills/SKILL.md` にトラブルシュートを追記
- `review-patterns.md` に該当プロジェクト固有の観点を追記
- プロジェクトのルート `CLAUDE.md` にプロジェクト固有の指示を書く（このテンプレートと併用できる）

## 含めないもの

- 特定の言語・フレームワークに依存するコーディング規約
- 絶対パスやユーザー固有の許可リスト（`settings.local.json` に寄せる）
- MCP サーバー固有の設定
