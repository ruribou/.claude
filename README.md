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
├── settings.json          共有してよい権限設定（git / gh を許可し、範囲外の操作を deny、git-guard / command-guard Hook を登録）
├── settings.local.json    ユーザーローカル設定（共有しない / .gitignore 推奨）
├── review-patterns.md     言語非依存のレビュー観点チェックリスト
├── bugfix-discipline.md   バグ修正の判断基準（原因の 3 つの問い・修正の種別 A〜E）
├── verify.conf.example    検証アダプター設定の例（プロジェクト側で verify.conf にコピー）
├── stop-hook.settings.example.json  完了前確認 Stop hook の設定例（opt-in・既定では無効）
├── notify.settings.example.json     デスクトップ通知の設定例（opt-in・既定では無効）
├── agents/
│   ├── task-planner.md    対話ヒアリング → 実装計画ドキュメント作成
│   ├── implementer.md     実装フローから 1 単位を受け取り実装・コミット
│   └── reviewer.md        読み取り専用レビュー（Read / Glob / Grep のみ）
├── commands/
│   ├── review-issue.md    /review-issue <issue>  Issue の受入条件に対する読み取り専用レビュー（補助）
│   ├── create-task.md     /create-task  実装計画ファイルの作成だけ（任意）
│   ├── clean-branch.md    /clean-branch マージ済みブランチ整理（任意の保守）
│   ├── watch-pr.md        /watch-pr [PR]  PR の CI を監視し、落ちたら修正・検証・レビューして green まで回す
│   ├── start-with-plan.md /start-with-plan <path>  互換入口 → /implement-issue --plan
│   └── code-review.md     /code-review  互換入口 → /review-issue の手順を Issue 指定なしで
├── scripts/
│   ├── checkpoint         実装フローの進行状態の保存・再開時の照合
│   ├── checkpoint.md      段階・照合・保存先の仕様
│   ├── git-guard          git / gh を実行直前の状態と照合する Hook
│   ├── git-guard.md       自律実行の判断基準・停止条件・判定表
│   ├── command-guard      git / gh 以外の破壊的コマンド（rm -rf / 、dd、mkfs 等）を止める Hook
│   ├── command-guard.md   判定表・限界
│   ├── lib/tokenize.awk   git-guard / command-guard が共有するコマンドの字句解析
│   ├── verify             検証の共通入口（明示した検証の実行と証跡記録）
│   ├── verify.md          アダプター設定・結果・証跡の仕様
│   ├── review             レビュー packet の作成と結果の記録・鮮度判定
│   ├── review.md          packet・判定・鮮度の仕様
│   ├── stop-hook          完了前確認の Stop hook（opt-in。checkpoint の active run だけが対象）
│   ├── stop-hook.md       Stop hook の判定・限界・導入方法の仕様
│   ├── notify             デスクトップ通知（opt-in）
│   └── notify.md          導入方法
└── skills/
    ├── implement-issue/SKILL.md  /implement-issue <issue>  1 Issue の実装フロー（手順の正本）
    ├── project-knowledge/ プロジェクト固有知識を必要時に参照する Skill
    │   ├── SKILL.md       読み込み手順（共有テンプレートが管理）
    │   ├── templates/     索引・トラブルシュート・レビュー事例の書式
    │   └── references/    知識本文（利用側リポジトリが作成・管理。テンプレートには含めない）
    └── verify/SKILL.md    /verify  検証を手動実行して結果を報告
```

## 使い方

普段使う入口は `/implement-issue <issue番号>` の 1 つだけ。1 回の起動で、小さな Issue 1 件を仕様確認から PR 作成まで進める。検証・レビュー・PR 作成のための段階別コマンドを順番に手入力する必要はない。

```
/implement-issue 12
```

親（ロードマップ）Issue を渡した場合は子 Issue の一覧を示して止まる。1 件ずつ指定して実行する。

### 実装フロー

```
/implement-issue 12             # Issue の目的・受入条件・対象外を確認
  ├─ implementer                # 小さな実装単位ごとに実装・コミット
  ├─ .claude/scripts/verify     # 明示した検証を実行し、証跡を残す
  ├─ reviewer                   # 読み取り専用の独立レビュー（指摘は implementer が修正 → 再検証・再レビュー）
  └─ push → PR                  # 最終 commit の検証・レビュー後に push。--merge で条件を満たせば統合まで
```


- フローを進めるのはメイン側（Skill を実行している会話）。implementer → verify → reviewer を順に呼び、subagent から subagent は起動しない
- 進行状態は `.claude/scripts/checkpoint` が worktree ごとのローカル checkpoint（`<git-dir>/claude-run/`）に保存する。中断後に同じコマンドを実行すると再開する
- 再開時は branch・worktree・remote・Issue 本文 / 計画を照合し、一致しない checkpoint は使わない。編集・commit・rebase で古くなった verify / review は無効化され、その段階からやり直す
- 修正サイクルが上限（既定 3 回）を超えた、解消できない指摘・権限・要件の不足がある場合は、理由と必要な判断を示して BLOCKED で止まる
- 完了と報告するのは、受入条件・verify・review・push・PR の証跡が揃ったときだけ。checkpoint には会話・Issue 本文・権限を保存しない

詳細は [`skills/implement-issue/SKILL.md`](skills/implement-issue/SKILL.md) と [`scripts/checkpoint.md`](scripts/checkpoint.md)。レビューは `/review-issue` と同じ `.claude/scripts/review` と `agents/reviewer.md` を使う。

### 中断・再開

中断した場合も、同じ `/implement-issue <issue番号>` をもう一度実行する。checkpoint を照合して途中の段階から再開し、push 済みの commit や作成済みの PR は重複して作らない（既存の PR を更新する）。

### 計画ファイルから始める（任意）

Issue がない作業は、計画ファイルを入力にできる。

```
/create-task "やりたいこと"            # 任意: task-planner が対話でヒアリング → docs/tasks/*.md を生成（実装はしない）
/implement-issue --plan <file>         # 計画ファイルを入力に、上と同じフローで PR まで進める
```

### 単独で確認したいとき（任意）

通常のフローでは手動で実行する必要はない。必要なときだけ単独で使う。

- `/verify` — プロジェクトが明示した検証を実行し、現在の差分に結び付いた証跡を残す（`/implement-issue` も同じ入口を使う）
- `/review-issue <issue>` — Issue の受入条件に対して現在の差分を読み取り専用でレビューする（`/implement-issue` も同じ reviewer を使う）。修正・コミットはしない
- `/watch-pr [PR番号]` — PR 作成後の CI を監視し、失敗したら原因を特定して implementer で修正、verify・reviewer を通してから push する。green になるか、3 サイクルで直らなければ止まる。merge はしない
- `/clean-branch` — マージ済みのローカルブランチを安全に整理する（開発フローとは別の保守操作）

### 旧コマンドからの移行

| 旧入口 | 現在の扱い | 代わりに使うもの・引数の差 |
| --- | --- | --- |
| `/start-with-plan <path>` | 互換入口（残す）。`docs/tasks/` の補完だけ行い、`/implement-issue --plan` の手順へ委譲する | `/implement-issue --plan <path>`。引数は同じ計画ファイルのパス。数字を渡しても Issue 番号としては扱わない |
| `/code-review [-- <pathspec>]` | 互換入口（残す）。`/review-issue` の手順を Issue 指定なしで実行する。修正・コミットはしない | Issue に対するレビューは `/review-issue <issue>`。引数は同じ pathspec |
| `/pr-create` | **廃止**（`commands/pr-create.md` を削除）。PR 作成は `/implement-issue` の公開段階（手順 8）に統合 | 対象 Issue の `/implement-issue <issue>` を再実行する。checkpoint から再開し、検証・レビューの証跡が最新の差分で有効な場合だけ push / PR 作成に進む。同じ branch の open PR があれば新規作成せず更新する。旧 `/pr-create` は引数なしで現在の branch を対象にしていたが、新しい入口は Issue 番号（または `--plan <path>`）が必須。対象の Issue / run を決められない場合は、推測で PR を作らず利用者に確認する |
| `/create-task` | 任意の補助入口（残す）。計画ファイルを作るだけ | 次の手順は `/implement-issue --plan <file>` |
| `/clean-branch` | 任意の保守入口（残す） | 変更なし |

- 互換入口は旧名を残すための薄い委譲で、手順・状態を複製しない。将来の削除は別の変更として告知する
- 導入先に `commands/pr-create.md` の私有コピーや `~/.claude/commands/` の同名コマンドがある場合、このテンプレートの更新では削除しない。不要なら利用者が削除する

## 検証の設定

検証コマンドは推測せず、プロジェクト側で明示する。

```bash
cp .claude/verify.conf.example .claude/verify.conf   # check 行を書く
.claude/scripts/verify suggest                       # 候補の表示だけ（実行しない）
.claude/scripts/verify run                           # 0=PASS 1=FAIL 2=BLOCKED
.claude/scripts/verify status                        # 最新の証跡が現在の差分で有効か
```

証跡とログは `<git-dir>/claude-verify/` に置かれ、コミットや送信はされない。`/implement-issue`（`/start-with-plan`）・`/review-issue`（`/code-review`）はこの共通入口を使う。詳細は [`scripts/verify.md`](scripts/verify.md)。

## レビュー

`/implement-issue`・`/review-issue <issue>`・`/code-review` は同じ `reviewer` エージェントを使う。指摘の修正は reviewer ではなく実装側（`/implement-issue` の implementer）が行い、修正後は検証・レビューの証跡を取り直す。reviewer は Read / Glob / Grep だけを持ち、修正・コミット・投稿をしない。

1. 呼び出し側が `verify status`（必要なら `verify run`）で検証証跡を用意する
2. `.claude/scripts/review build` が base / head・差分（未追跡の新規ファイルを含む）・検証証跡・Issue 本文を packet にまとめる。Issue 本文と差分はデータとして扱う
3. reviewer が packet を読み、`PASS` / `CHANGES_REQUESTED` / `BLOCKED` と根拠（ファイル・行）・未確認事項を返す
4. `.claude/scripts/review record` が結果を保存し、検証証跡が `VALID` でない・受入条件がない・差分がない・レビュー中に入力が変わった場合は PASS にしない

`.claude/scripts/review status` は、レビュー後に差分・ベース・検証証跡・Issue 本文が変わっていれば `STALE` を返す。PASS は確認した範囲の結果であり、人間のレビューや承認の代わりではない。詳細は [`scripts/review.md`](scripts/review.md)。

## 完了前確認の Stop hook（opt-in）

`/implement-issue` の run（`checkpoint start` で開始したもの）を、証跡で裏付けられた `done` か理由付きの `blocked` になる前に終えてしまう取り違えを補助する Stop hook を用意している。**既定では有効化されない。** 内容と下記の限界を確認したうえで、[`stop-hook.settings.example.json`](stop-hook.settings.example.json) の `hooks.Stop` を `.claude/settings.json` か `.claude/settings.local.json` にマージして使う。

- 対象は、この session が開始した active な run だけ。run がない・別 session・別 worktree の停止は止めない（通常の質問への回答はそのまま終わる）
- 判定は `checkpoint check`（`verify status` / `review status`）に委ね、未完了・証跡が古い場合だけ `decision: "block"` で段階・次の作業・止まり方（`checkpoint block`）を返す
- 同じ状態での再 block はせず、1 ターンの block 回数にも上限がある。hook 内では build / test / LLM 呼び出し / commit / push / PR 作成をせず、確認時間に上限（既定 20 秒）を設けている
- **保証の範囲**: hook の不実行・失敗・timeout・利用者の中断ではそのまま停止し、これらを検証・レビュー PASS とはみなさない。merge gate や CI / branch protection の代わりではない

詳細は [`scripts/stop-hook.md`](scripts/stop-hook.md)。

## デスクトップ通知（opt-in）

Claude Code が入力を待っているときと、応答を終えたときにデスクトップ通知を出す（macOS / Linux）。個人の好みなので **既定では有効化されない。** [`notify.settings.example.json`](notify.settings.example.json) の `hooks` を `.claude/settings.local.json` にマージして使う。詳細は [`scripts/notify.md`](scripts/notify.md)。

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

git / gh 以外のコマンドは権限確認を経て実行されるが、権限確認を省略する実行（bypass permissions など）に備えて、PreToolUse に `scripts/command-guard` も登録している。`rm -rf /`・`dd of=/dev/...`・`mkfs`・システム領域への `chmod -R` など取り返しのつかない操作だけを deny / ask し、それ以外のコマンドには関与しない。判定表と限界は [`scripts/command-guard.md`](scripts/command-guard.md)。保護するパスは `env` の `CLAUDE_COMMAND_GUARD_PROTECTED` で追加できる。

### 追加の許可を置く場所

| 置き場所 | 用途 | 共有 |
| --- | --- | --- |
| `.claude/settings.json` | プロジェクト全員に必要な許可（このテンプレート） | する |
| `.claude/settings.local.json` | そのプロジェクトでの個人的な許可（`.gitignore` 済み） | しない |
| `~/.claude/settings.json` | 全プロジェクト共通の個人的な許可 | しない |

プロジェクト固有のビルド・テストコマンドなどは、共有が必要なら `settings.json` に、個人の好みなら `settings.local.json` に追記する。統合ブランチの名前が `main` / `master` / `develop` 以外なら、`settings.json` の `env` に `CLAUDE_GIT_GUARD_PROTECTED` を設定する。

### 設定を有効にする際の確認手順

1. Claude Code を起動して信頼ダイアログを承認し、`/permissions` と `/hooks` で有効な許可ルール・Hook とその出所（共有 / ローカル / ユーザー）を確認する（未信頼のワークスペースでは `permissions.allow` が無視される）
2. 必要に応じて `claude --setting-sources project` で共有設定だけを読み込んだ状態で起動し、git / gh 以外のコマンドで確認が求められること、`git push --force` が git-guard に止められることを確かめる。command-guard は `jq -n --arg c 'rm -rf /' '{tool_input:{command:$c}}' | .claude/scripts/command-guard` で単体確認できる

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
| 常時ロード | ルート `CLAUDE.md`、各 Skill の `name` / `description`（`disable-model-invocation: true` の `implement-issue` / `verify` を除く） | セッション開始時から常に文脈に入る |
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
