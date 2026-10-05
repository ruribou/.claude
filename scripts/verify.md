# verify — 検証アダプターと証跡の仕様

`scripts/verify`（配置後は `.claude/scripts/verify`）は、プロジェクトが明示した検証だけを実行し、その結果を検証対象のスナップショットに結び付けて記録する共通入口。共通側は特定の言語・パッケージマネージャーに依存せず、`bash` と `git` だけを使う。

## コマンド

| コマンド | 内容 | 終了コード |
| --- | --- | --- |
| `verify run` | 設定済みの検証をすべて実行し、証跡を記録する | `0`=PASS / `1`=FAIL / `2`=BLOCKED |
| `verify status` | 最新の証跡が現在のスナップショットに対する PASS か判定する（再実行しない） | `0`=VALID / `1`=STALE・NOT_PASS・NONE |
| `verify suggest` | 初回設定用に検証コマンドの候補を表示する（実行も書き込みもしない） | `0` |
| `verify fingerprint` | 現在のスナップショットの構成要素を表示する | `0` |

いずれもリポジトリ内の任意のディレクトリから実行できる（ルートは `git rev-parse --show-toplevel` で決まる）。

## アダプター設定（プロジェクト側）

既定のパスは `<repo>/.claude/verify.conf`。`--config <path>` または `CLAUDE_VERIFY_CONFIG` で差し替えられる。書式例は [`verify.conf.example`](../verify.conf.example)。

```
# 行頭 # はコメント
check <id> <作業ディレクトリ> <argv...>
input <追加入力パス>
```

- `check`: 必須検証を 1 つ宣言する。宣言した順に、すべて実行する
  - `<id>`: 英数字で始まる `[A-Za-z0-9_.-]`。重複不可。証跡とログ名に使う
  - `<作業ディレクトリ>`: リポジトリルートからの相対パス（`.` 可、`..` / 絶対パス不可）
  - `<argv...>`: 空白区切りでそのまま argv になる。**引用符・変数・グロブ・パイプなどのシェル展開は一切しない**。シェルの機能が必要なら検証スクリプトを用意して、そのパスを書く
- `input`: git が追跡しない（ignore 済みの）ビルド入力を追加で宣言する。ファイルまたはディレクトリ（再帰）。宣言した範囲だけを見て、内容はハッシュとしてのみ扱う

設定ファイルは宣言として読むだけで、`eval` / `source` しない。Issue 本文や会話中の文字列を検証コマンドとして評価しない。

### 自動検出の扱い

`verify suggest` は `package.json` / `Makefile` / `justfile` / `Cargo.toml` / `go.mod` / `pyproject.toml` から候補をコメント行として表示するだけ。候補はユーザーが確認して `verify.conf` に書いて初めて実行対象になる。設定がない状態で推測したコマンドを実行することはない。

## 結果

各 check と全体の結果は `PASS` / `FAIL` / `BLOCKED` のいずれか。未実行を PASS にしない。

| 結果 | reason | 意味 |
| --- | --- | --- |
| PASS | `ok` | 終了コード 0 |
| FAIL | `nonzero_exit` | 終了コード非 0 |
| BLOCKED | `command_missing` | check に argv がない |
| BLOCKED | `cwd_missing` | 作業ディレクトリが存在しない |
| BLOCKED | `executable_not_found` | argv[0] が PATH 上 / 指定パスに実行可能ファイルとして存在しない |

全体の結果:

| 結果 | reason | 条件 |
| --- | --- | --- |
| BLOCKED | `config_missing` | 設定ファイルがない |
| BLOCKED | `config_invalid` | 設定ファイルの書式エラー（`config_error` に行番号） |
| BLOCKED | `no_checks` | check が 1 つもない |
| FAIL | `check_failed` | FAIL の check がある |
| BLOCKED | `check_blocked` | FAIL はないが BLOCKED の check がある |
| BLOCKED | `inputs_changed_during_run` | 実行前後でスナップショットが変わった（check の結果に関わらず） |
| PASS | `ok` | すべての check が PASS かつスナップショットが不変 |

## スナップショット

次の要素のハッシュから `fingerprint` を作る。いずれかが変われば別のスナップショットになる。

| 要素 | 内容 |
| --- | --- |
| `head` | `HEAD` のコミット（未作成なら `unborn`） |
| `staged` | `git diff --cached --binary`（追加・削除・モード変更を含む） |
| `unstaged` | `git diff --binary`（同上） |
| `untracked` | ignore されていない未追跡ファイルのパス・実行ビット・内容ハッシュ |
| `inputs` | `input` で宣言したパスの種別・実行ビット・内容ハッシュ |
| `config` | アダプター設定ファイルの内容ハッシュ |

ハッシュは `git hash-object` で計算する。ignore 済みで `input` に宣言していないファイルは対象外。検証で生成されるビルド成果物は ignore しておく（ignore されていない成果物が増えると `inputs_changed_during_run` になる）。

## 証跡

保存先は既定で `<git-dir>/claude-verify/`（`CLAUDE_VERIFY_STATE_DIR` で変更可）。作業ツリーの外なのでコミットされず、どこにも送信しない。

```
<git-dir>/claude-verify/
├── latest                    最新 run の要約（key=value）
└── runs/<run_id>/
    ├── evidence.json         証跡
    └── <check id>.log        check ごとの stdout / stderr
```

`latest`（後続のレビューや Hook が `verify status` 経由で使う）:

```
schema=claude-verify/v1
run_id=<run_id>
result=PASS|FAIL|BLOCKED
reason=<reason>
fingerprint=<実行前の fingerprint>
evidence=<evidence.json の絶対パス>
```

`evidence.json`:

```json
{
  "schema": "claude-verify/v1",
  "run_id": "20261005T070953Z-43075",
  "started_at": "2026-10-05T07:09:53Z",
  "finished_at": "2026-10-05T07:09:54Z",
  "config": ".claude/verify.conf",
  "config_error": null,
  "result": "PASS",
  "reason": "ok",
  "snapshot": { "fingerprint": "…", "head": "…", "staged": "…", "unstaged": "…", "untracked": "…", "inputs": "…", "config": "…" },
  "snapshot_after": { "fingerprint": "…", "…": "…" },
  "checks": [
    { "id": "lint", "cwd": ".", "result": "PASS", "reason": "ok", "exit_code": 0, "log": "runs/20261005T070953Z-43075/lint.log" }
  ]
}
```

- `exit_code` / `log` は実行しなかった check では `null`
- argv 本文・追加入力の本文は保存しない（引数に秘密を含めても証跡には残らない。ログには検証コマンド自身の出力が残る）
- 証跡が有効なのは `result=PASS` かつ `fingerprint` が現在のスナップショットと一致するときだけ。`verify status` がこれを判定する

## 対象外

全言語向けの自動検出、CI 基盤、検証結果の改ざん防止、環境全体（ツールのバージョン・環境変数など）の再現。
