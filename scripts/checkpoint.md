# checkpoint — 実装フローの中断・再開の仕様

`scripts/checkpoint`（配置後は `.claude/scripts/checkpoint`）は、`/implement-issue`（`skills/implement-issue/SKILL.md`）の 1 run の進行状態を小さなローカル checkpoint に保存し、再開時に実際の作業ツリー・証跡と照合する。`bash` と `git` だけを使い、`verify` / `review` の判定を呼び出して使う（証跡形式は再実装しない）。

checkpoint は「どこまで進んだと記録したか」の控えであり、それ自体を成功の根拠にしない。段階を進める・維持する根拠は、毎回 `verify status` / `review status` / git の実際の状態から取り直す。

## 段階（stage）

```
spec → implementing → implemented → verified → reviewed → published → done
                                                                     （blocked は任意の段階から）
```

| stage | 意味 | 進め方 |
| --- | --- | --- |
| `spec` | 対象を確認中。受入条件が未記録 | `criteria` で受入条件と検証方法を記録すると `implementing` |
| `implementing` | 実装単位を進めている | `set stage=implemented` |
| `implemented` | 実装が終わり、検証待ち | `verify run` 後に `record-verify` |
| `verified` | 現在のスナップショットで verify が PASS | `review record` が PASS の後に `record-review <review_id>` |
| `reviewed` | 同じ入力に対して review が PASS | push 後に `record-push` |
| `published` | upstream が HEAD と一致（PR は別途記録） | `set pr=<n>` → `done` |
| `done` | 受入条件・verify・review・push・PR がすべて揃っている | — |
| `blocked` | 理由付きで停止中 | 利用者の判断後に `set stage=implementing` など |

`verified` 以降は証跡を記録するコマンドでしか進めない（`set stage=verified` などは拒否する）。

## コマンド

| コマンド | 内容 | 終了コード |
| --- | --- | --- |
| `start (--issue <n> --issue-file <path> \| --plan <path>) [--remote <name>] [--repo <owner/name>] [--base <ref>] [--max-attempts <n>] [--session <id>]` | run を作る。active な run が終わっていなければ作らない。`--session` の既定は `CLAUDE_CODE_SESSION_ID`（Stop hook の対象判定に使う） | `0` / `3`=active run あり |
| `resume [--issue-file <path>]` | 照合し、証跡で裏付けられる段階まで戻して保存・表示する | `0` / `1`=MISMATCH / `3`=run なし |
| `status [--issue-file <path>]` | `resume` と同じ照合をするが書き換えない | 同上 |
| `check` | `status` と同じ照合結果を key=value で表示する（[Stop hook](stop-hook.md) 用。書き換えない） | `0` / `3`=run なし |
| `criteria` | stdin の `<受入条件> :: <検証方法>` 行で受入条件を置き換える | `0` / `64`=形式違反 |
| `set <key=value>...` | `stage`（`spec` / `implementing` / `implemented`）・`next`・`pr`・`max_attempts` | `0` / `64` |
| `record-verify` | `verify status` が VALID なら最新の verify run を記録して `verified` | `0` / `1` / `2`=verify がない |
| `record-review <review_id>` | `review status <id>` が VALID なら記録して `reviewed` | `0` / `1` / `2`=review がない |
| `record-push` | verify・review が有効で、upstream が HEAD と一致すれば `published` | `0` / `1` |
| `attempt` | 修正サイクルの試行回数を 1 増やす。上限を超えたら `blocked` | `0` / `2`=上限超過 |
| `block <reason> <next>` | 理由と次に必要な判断を記録して `blocked` | `0` |
| `done` | すべての証跡が揃っていれば `done`。足りないものを列挙する | `0` / `1`=NOT DONE |
| `abandon` | active な run を解除する（記録は残す） | `0` |

## 照合（resume / status）

### 1. 作業場所と対象が一致するか（不一致なら MISMATCH）

| 項目 | 記録 | 現在 |
| --- | --- | --- |
| worktree | `start` 時の `git rev-parse --show-toplevel` | 同じ |
| git_dir | `start` 時の git-dir（linked worktree ごとに別） | 同じ |
| branch | `start` 時の branch | `git symbolic-ref HEAD` |
| remote | `start` 時の remote 名と URL | `git remote get-url <remote>` |
| Issue 本文 | `--issue-file` の内容ハッシュ | `resume --issue-file` で渡した最新の本文 |
| 計画ファイル | 内容ハッシュ | 作業ツリーの同じパス |

MISMATCH の checkpoint は成功状態として使わない。対象・branch を確認し直すか、`abandon` して `start` し直す。

### 2. 証跡で裏付けられる段階まで戻す

| 記録した段階 | 有効の条件 | 無効なら |
| --- | --- | --- |
| `published` 以降 | `pushed_oid` = HEAD = `@{upstream}` | `reviewed` へ |
| `reviewed` 以降 | `review status <review_id>` が VALID | `verified` へ |
| `verified` 以降 | `verify status` が VALID かつ最新 run が記録した run | `implemented` へ（未検証の変更あり） |

verify の fingerprint は HEAD・staged・unstaged・未追跡ファイルを含むため、commit・rebase・編集のどれでも古い証跡は無効になる。戻した段階より後の証跡（verify run / review_id / pushed_oid）は checkpoint から消す。`resume` は戻した理由を `notes` に出す。

## 保存先

既定で `<git-dir>/claude-run/`（`CLAUDE_RUN_STATE_DIR` で変更可）。linked worktree では git-dir が worktree ごとに分かれるため、他の worktree の run は見えない。作業ツリーの外なのでコミットされず、どこにも送信しない（`.gitignore` の追加は不要）。

```
<git-dir>/claude-run/
├── active                 active な run_id
└── runs/<run_id>/
    ├── state              key=value（下記）
    ├── criteria           受入条件 :: 検証方法（1 行 1 件）
    ├── baseline           run 開始前から変更されていたパス（内容は保存しない）
    ├── log                段階遷移の記録（時刻・stage・証跡 ID）
    └── stop-hook          Stop hook の連続 block 回数と直前の理由（hook だけが書く）
```

`state` のキー: `schema` `run_id` `session_id` `target`（`issue:<n>` / `plan:<path>`）`repo` `remote` `remote_url` `worktree` `git_dir` `branch` `base` `start_head` `issue_hash` `plan_hash` `stage` `next` `attempts` `max_attempts` `verify_run` `verify_fingerprint` `verified_head` `review_id` `pushed_oid` `pr` `blocked_reason` `created_at` `updated_at`

保存しないもの: 会話・実装の経緯、Issue 本文や差分の本文、コマンド本文、権限・承認の状態。再開時の権限は現在の設定と利用者の指示で判断し、checkpoint から復元・拡大しない。

## 対象外

複数 run の並行管理（1 worktree に active な run は 1 つ）、checkpoint の改ざん防止、PR / CI の状態の保存（毎回 `gh` で取り直す）。
