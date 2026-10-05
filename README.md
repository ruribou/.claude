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
├── settings.json          共有してよい権限設定（git / gh を許可し、範囲外の操作を deny、git-guard Hook を登録）
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
│   ├── git-guard          git / gh を実行直前の状態と照合する Hook
│   ├── git-guard.md       自律実行の判断基準・停止条件・判定表
│   ├── verify             検証の共通入口（明示した検証の実行と証跡記録）
│   ├── verify.md          アダプター設定・結果・証跡の仕様
│   ├── review             レビュー packet の作成と結果の記録・鮮度判定
│   └── review.md          packet・判定・鮮度の仕様
└── skills/
    ├── project-knowledge/ プロジェクト固有知識を必要時に参照する Skill
    │   ├── SKILL.md       読み込み手順（共有テンプレートが管理）
    │   ├── templates/     索引・トラブルシュート・レビュー事例の書式
    │   └── references/    知識本文（利用側リポジトリが作成・管理。テンプレートには含めない）
    └── verify/SKILL.md    /verify  検証を手動実行して結果を報告
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
- **プロジェクト固有の知識**: `skills/project-knowledge/references/` に利用側リポジトリで置く。共有テンプレートには個別事例を含めず、自動追記もしない

## 権限設定

### 共有設定（`settings.json`）

- `Bash(git:*)` と `Bash(gh:*)` を自動許可する。git / gh 以外のシェルコマンド（lint / test / build、ファイル操作など）は Claude Code の権限確認を経て実行される
- 認証・秘密情報・repo 管理・個人設定を変える `gh` / `git` の一部は `permissions.deny` で拒否する
- PreToolUse / PostToolUse に `scripts/git-guard` を登録し、git / gh を実行直前の状態（作業ツリー、remote の先端、PR の状態など）と照合する。通常の branch 作成・commit・push・rebase・期待 OID 付き `--force-with-lease`・条件を満たした PR の merge は止めず、変更や他者の commit を失う可能性があるときだけ止める
- スラッシュコマンドの `allowed-tools` も `Bash` を無制限には指定せず、必要な `Bash(git:*)` / `Bash(gh:*)` / `Bash(.claude/scripts/verify:*)` / `Bash(.claude/scripts/review:*)` に限定している。`reviewer` エージェントには Bash を与えない

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

- トラブルシュート・レビュー事例は `skills/project-knowledge/references/` に追加する（後述）
- プロジェクトのルート `CLAUDE.md` にプロジェクト固有の指示を書く（このテンプレートと併用できる）。ただし常時ロードされるため短く保つ

## プロジェクト固有知識（project-knowledge Skill）

### 読み込みの境界

| 区分 | 対象 | いつ読まれるか |
| --- | --- | --- |
| 常時ロード | ルート `CLAUDE.md`、各 Skill の `name` / `description`（`disable-model-invocation: true` の `verify` を除く） | セッション開始時から常に文脈に入る |
| 必要時に読む手順 | `skills/project-knowledge/SKILL.md` 本文 | description に合うタスク（エラー調査等）で Claude が呼び出したとき、または `/project-knowledge` 実行時。`reviewer` エージェントは Skill を使わず、`review-patterns.md` の案内に従って索引を直接読む |
| 必要時に読む知識本文 | `references/index.md` → 条件に合う `references/*.md` だけ | Skill の手順（または reviewer）の中で、索引の「読む条件」に合うものだけ |
| 結果ログ | `docs/tasks/*.md`、検証証跡（`<git-dir>/claude-verify/`）、レビュー結果（`<git-dir>/claude-review/`）、PR 本文 | 自動では読まれない。コマンドやスクリプトが明示的に参照したものだけ |

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
