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
├── settings.json          共有してよい権限設定（git / gh 中心の最小許可）
├── settings.local.json    ユーザーローカル設定（共有しない / .gitignore 推奨）
├── review-patterns.md     言語非依存のレビュー観点チェックリスト
├── verify.conf.example    検証アダプター設定の例（プロジェクト側で verify.conf にコピー）
├── agents/
│   ├── task-planner.md    対話ヒアリング → 実装計画ドキュメント作成
│   ├── implementer.md     実装計画に沿ってステップ実行
│   └── reviewer.md        読み取り専用レビュー（Read / Glob / Grep のみ）
├── commands/
│   ├── create-task.md     /create-task  タスク（実装計画）作成
│   ├── start-with-plan.md /start-with-plan <path>  実装開始
│   ├── code-review.md     /code-review  ブランチ差分の読み取り専用レビュー
│   ├── review-issue.md    /review-issue <issue>  Issue の受入条件に対する読み取り専用レビュー
│   ├── pr-create.md       /pr-create    PR 作成
│   └── clean-branch.md    /clean-branch マージ済みブランチ整理
├── scripts/
│   ├── verify             検証の共通入口（明示した検証の実行と証跡記録）
│   ├── verify.md          アダプター設定・結果・証跡の仕様
│   ├── review             レビュー packet の作成と結果の記録・鮮度判定
│   └── review.md          packet・判定・鮮度の仕様
├── skills/
│   ├── SKILL.md           プロジェクト固有トラブルシュート置き場（テンプレート）
│   └── verify/SKILL.md    /verify  検証を手動実行して結果を報告
└── tests/
    ├── verify.test.sh     scripts/verify のテスト
    ├── review.test.sh     scripts/review と reviewer 定義のテスト
    └── fixtures/          合成 fixture（既知の欠陥を含むレビュー対象など）
```

## 想定ワークフロー

```
/create-task "やりたいこと"     # task-planner が対話でヒアリング → docs/tasks/*.md を生成
        ↓
/start-with-plan <file>         # implementer がステップごとに実装・検証・コミット
        ↓
/code-review                    # 読み取り専用レビュー（Issue に対しては /review-issue <issue>）
        ↓                         指摘の修正は明示的な実装ステップで行い、再レビューする
        ↓
/pr-create                      # ベースブランチ自動検出で PR 作成
```

補助コマンド:

- `/verify` — プロジェクトが明示した検証を実行し、現在の差分に結び付いた証跡を残す
- `/review-issue <issue>` — Issue の受入条件に対して現在の差分を読み取り専用でレビューする
- `/clean-branch` — マージ済みのローカルブランチを安全に整理する

## 検証の設定

検証コマンドは推測せず、プロジェクト側で明示する。

```bash
cp .claude/verify.conf.example .claude/verify.conf   # check 行を書く
.claude/scripts/verify suggest                       # 候補の表示だけ（実行しない）
.claude/scripts/verify run                           # 0=PASS 1=FAIL 2=BLOCKED
.claude/scripts/verify status                        # 最新の証跡が現在の差分で有効か
```

証跡とログは `<git-dir>/claude-verify/` に置かれ、コミットや送信はされない。`/start-with-plan`・`/code-review`・`/pr-create` はこの共通入口を使う。詳細は [`scripts/verify.md`](scripts/verify.md)。

## レビュー

`/review-issue <issue>` と `/code-review` は同じ `reviewer` エージェントを使う。reviewer は Read / Glob / Grep だけを持ち、修正・コミット・投稿をしない。

1. 呼び出し側が `verify status`（必要なら `verify run`）で検証証跡を用意する
2. `.claude/scripts/review build` が base / head・差分（未追跡の新規ファイルを含む）・検証証跡・Issue 本文を packet にまとめる。Issue 本文と差分はデータとして扱う
3. reviewer が packet を読み、`PASS` / `CHANGES_REQUESTED` / `BLOCKED` と根拠（ファイル・行）・未確認事項を返す
4. `.claude/scripts/review record` が結果を保存し、検証証跡が `VALID` でない・受入条件がない・差分がない・レビュー中に入力が変わった場合は PASS にしない

`.claude/scripts/review status` は、レビュー後に差分・ベース・検証証跡・Issue 本文が変わっていれば `STALE` を返す。PASS は確認した範囲の結果であり、人間のレビューや承認の代わりではない。詳細は [`scripts/review.md`](scripts/review.md)。

## 設計方針

- **言語非依存**: TypeScript / React / Python / Go / Rust など、どのスタックでも動くように書かれている。検証コマンド（lint / type check / test / build）はプロジェクト側の `.claude/verify.conf` で明示し、`scripts/verify` が実行する。自動検出は初回設定の候補提示（`verify suggest`）にとどめる
- **ブランチ運用**: `develop` → `main` の 2 段階を前提にベースブランチを自動検出する。`develop` が無ければ `main` を使う
- **タスクドキュメントの置き場**: `docs/tasks/{kebab-case}.md`。ディレクトリが無ければエージェントが作成する
- **レビュー観点**: 言語固有のアンチパターンではなく、セキュリティ / 設計 / 正確性・並行性 / 規約 の 4 軸で抽象的に定義（`review-patterns.md`）。レビューと修正は分け、レビューは読み取り専用で行う
- **プロジェクト固有の知識**: `skills/SKILL.md` に追記して蓄積する。ここだけはプロジェクトごとに書き換える前提

## カスタマイズ

プロジェクト固有のルール（例: フレームワーク特有のアンチパターン、独自のブランチ戦略、デプロイ手順のハマりどころ）は、汎用テンプレートを直接書き換えるのではなく、以下のいずれかで追加するのが望ましい。

- `skills/SKILL.md` にトラブルシュートを追記
- `review-patterns.md` に該当プロジェクト固有の観点を追記
- プロジェクトのルート `CLAUDE.md` にプロジェクト固有の指示を書く（このテンプレートと併用できる）

## 含めないもの

- 特定の言語・フレームワークに依存するコーディング規約
- 絶対パスやユーザー固有の許可リスト（`settings.local.json` に寄せる）
- MCP サーバー固有の設定
