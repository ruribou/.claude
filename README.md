# .claude

どのプロジェクトでも流用できる、汎用の [Claude Code](https://docs.claude.com/en/docs/claude-code) 設定テンプレート集。

言語・フレームワーク・デプロイ先に依存しない形で、エージェント・スラッシュコマンド・レビュー観点・プロジェクト固有知識の参照 Skill を揃えている。任意のリポジトリのルートに `.claude/` ディレクトリとして配置するだけで使える。

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
├── agents/
│   ├── task-planner.md    対話ヒアリング → 実装計画ドキュメント作成
│   └── implementer.md     実装計画に沿ってステップ実行
├── commands/
│   ├── create-task.md     /create-task  タスク（実装計画）作成
│   ├── start-with-plan.md /start-with-plan <path>  実装開始
│   ├── code-review.md     /code-review  並列レビュー
│   ├── pr-create.md       /pr-create    PR 作成
│   └── clean-branch.md    /clean-branch マージ済みブランチ整理
└── skills/
    └── project-knowledge/ プロジェクト固有知識を必要時に参照する Skill
        ├── SKILL.md       読み込み手順（共有テンプレートが管理）
        ├── templates/     索引・トラブルシュート・レビュー事例の書式
        └── references/    知識本文（利用側リポジトリが作成・管理。テンプレートには含めない）
```

## 想定ワークフロー

```
/create-task "やりたいこと"     # task-planner が対話でヒアリング → docs/tasks/*.md を生成
        ↓
/start-with-plan <file>         # implementer がステップごとに実装・検証・コミット
        ↓
/code-review                    # 4観点で並列レビュー → 指摘を修正
        ↓
/pr-create                      # ベースブランチ自動検出で PR 作成
```

補助コマンド:

- `/clean-branch` — マージ済みのローカルブランチを安全に整理する

## 設計方針

- **言語非依存**: TypeScript / React / Python / Go / Rust など、どのスタックでも動くように書かれている。検証コマンド（lint / type check / test / build）は `package.json` / `Makefile` / `justfile` / `Cargo.toml` / `pyproject.toml` 等から自動検出する
- **ブランチ運用**: `develop` → `main` の 2 段階を前提にベースブランチを自動検出する。`develop` が無ければ `main` を使う
- **タスクドキュメントの置き場**: `docs/tasks/{kebab-case}.md`。ディレクトリが無ければエージェントが作成する
- **レビュー観点**: 言語固有のアンチパターンではなく、セキュリティ / 設計 / 正確性・並行性 / 規約 の 4 軸で抽象的に定義
- **プロジェクト固有の知識**: `skills/project-knowledge/references/` に利用側リポジトリで置く。共有テンプレートには個別事例を含めず、自動追記もしない

## カスタマイズ

プロジェクト固有のルール（例: フレームワーク特有のアンチパターン、独自のブランチ戦略、デプロイ手順のハマりどころ）は、汎用テンプレートを直接書き換えるのではなく、以下のいずれかで追加するのが望ましい。

- トラブルシュート・レビュー事例は `skills/project-knowledge/references/` に追加する（後述）
- プロジェクトのルート `CLAUDE.md` にプロジェクト固有の指示を書く（このテンプレートと併用できる）。ただし常時ロードされるため短く保つ

## プロジェクト固有知識（project-knowledge Skill）

### 読み込みの境界

| 区分 | 対象 | いつ読まれるか |
| --- | --- | --- |
| 常時ロード | ルート `CLAUDE.md`、各 Skill の `name` / `description` | セッション開始時から常に文脈に入る |
| 必要時に読む手順 | `skills/project-knowledge/SKILL.md` 本文 | description に合うタスク（エラー調査・レビュー等）で Claude が呼び出したとき、または `/project-knowledge` 実行時 |
| 必要時に読む知識本文 | `references/index.md` → 条件に合う `references/*.md` だけ | Skill の手順の中で、索引の「読む条件」に合うものだけ |
| 結果ログ | `docs/tasks/*.md`、レビューレポート、PR 本文 | 自動では読まれない。コマンド実行時に明示的に指定したものだけ |

- `CLAUDE.md` から Skill や `references/` を `@` import しない（import すると常時ロードになる）
- `CLAUDE.md` に書くなら「固有のハマりどころは project-knowledge Skill を参照」程度の 1 行にとどめる

### 知識の追加

1. `templates/index.md` を `references/index.md` にコピーし、不要な例の行を消す
2. `templates/troubleshooting.md` / `templates/review-case.md` を `references/` にコピーして記入する。領域ごとにファイルを分ける
3. `references/index.md` に「読む条件」を具体的に書いて 1 行登録する

`SKILL.md` と `templates/` は共有テンプレート側の管理対象なので、ここには個別事例を書かない。テンプレート更新時に取り込んでも `references/` とは衝突しない。蓄積先を増やす場合も Skill は増やさず、`references/` 内のファイルを増やす。

一般的（言語非依存）なレビュー観点は `review-patterns.md`、リポジトリ固有の事例は `references/` に分ける。

### 旧 `skills/SKILL.md` からの移行

旧 `skills/SKILL.md` は Skill のディレクトリ構造・frontmatter を持たないため、Claude Code に Skill として認識されていなかった。追記済みのエントリがある場合は次の手順で移す。

1. 旧ファイルのエントリを領域ごとに `skills/project-knowledge/references/troubleshooting-{領域}.md` へ移す
2. `references/index.md` を作成し、移したファイルを読む条件付きで登録する
3. 旧 `skills/SKILL.md` を削除する（残すと `skills/` 直下に Skill ではないファイルが残り、どちらが正か曖昧になる）

### ロード範囲の確認方法

自動選択は description とタスク内容の照合で決まるため、必ず呼ばれる・必ず呼ばれないことは保証しない。採用したロード範囲は次の手順で確認する。

1. Claude Code で `/skills` を実行し、`project-knowledge` が一覧に出ることを確認する（出ない場合は `.claude/skills/project-knowledge/SKILL.md` の配置と frontmatter を確認）
2. 無関係なタスク（例: 「この関数名をリネームして」）の後に `/context` を実行し、`references/` の内容が読み込まれていないことを確認する
3. 関連タスク（例: 索引に登録したエラーメッセージを提示して原因を聞く）を実行し、Skill が呼ばれ、報告された参照ファイルが索引の条件に合うものだけであることを確認する
4. 確実に使いたい場合は `/project-knowledge <状況>` で明示的に呼び出す

## 含めないもの

- 特定の言語・フレームワークに依存するコーディング規約
- 絶対パスやユーザー固有の許可リスト（`settings.local.json` に寄せる）
- MCP サーバー固有の設定
