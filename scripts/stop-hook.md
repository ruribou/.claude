# stop-hook — 対象 run 限定の完了前確認の仕様

`scripts/stop-hook`（配置後は `.claude/scripts/stop-hook`）は Claude Code の Stop hook。この session が [`checkpoint`](checkpoint.md) で開始した active な実装 run だけを対象に、停止前に「run が証跡で裏付けられた `done` か、理由付きの `blocked` か」を確認する。**既定では有効化されない（opt-in）**。

判定は `checkpoint check` に委ねる。checkpoint は `verify status` / `review status` と git の状態から段階を取り直すだけなので、hook 内で build / test / LLM 呼び出し / commit / push / PR 作成はしない。

## 位置付けと限界

- 取り違え（証跡が古くなったまま完了報告する、レビュー前に止まる）を軽く補助するためのもので、merge gate や安全保証ではない。CI / branch protection の代わりにはならない
- hook が実行されない・失敗する・timeout する・利用者が中断する（Esc など）と、Claude Code はそのまま停止する。これらの場合も**検証・レビューが PASS とはみなさない**（証跡は確認されていない）
- 判定に使う証跡と checkpoint はローカルの `<git-dir>` 配下にあり、改ざん防止はしない
- 対象は `checkpoint start` で開始し、`session_id` が一致する run だけ。通常の会話・別 session・別 worktree の停止は止めない

## 導入（opt-in）

内容を確認したうえで、[`stop-hook.settings.example.json`](../stop-hook.settings.example.json) の `hooks.Stop` をプロジェクトの `.claude/settings.json`（共有する場合）または `.claude/settings.local.json`（自分だけの場合）にマージする。既存の `PreToolUse` / `PostToolUse` などはそのまま残す。

hook の `timeout`（例では 30 秒）は `CLAUDE_STOP_HOOK_TIMEOUT`（既定 20 秒）より長くしておく。

run は `/implement-issue` が `checkpoint start` で開始する。`session_id` は既定で `CLAUDE_CODE_SESSION_ID`（Claude Code の Bash ツールから実行すると設定される）から記録され、Stop hook の stdin の `session_id` と照合される。`session_id` が記録されていない run（この変更より前に開始した run や、Claude Code の外で開始した run）は対象にならない。

## 判定

stdin の `session_id` / `cwd` / `stop_hook_active` だけを読む（`jq` は使わない）。

| 状況 | 応答 |
| --- | --- |
| git 外 / `session_id` なし / 壊れた入力 / `checkpoint` がない | 何も返さず停止を許可 |
| active な run がない（`checkpoint check` が exit 3） | 同上 |
| run の `session_id` が現在の session と一致しない | 同上（対象外） |
| checkpoint が壊れている（state がない・`stage` がない） | 同上 |
| state が `CLAUDE_STOP_HOOK_TTL_MINUTES`（既定 1440 分）以上更新されていない | 同上（古い active とみなす） |
| 照合が MISMATCH（branch・worktree・remote・計画などが違う） | `{"systemMessage": ...}` で通知し、停止は許可 |
| 証跡で裏付けられた段階が `done` / `blocked` | 何も返さず停止を許可 |
| それ以外（未完了、または `done` 後の変更で証跡が古くなった） | `{"decision": "block", "reason": "<段階・戻した理由・次の作業・止まり方>"}`（exit 0） |
| `stop_hook_active=true` で前回と同じ段階・同じ理由・同じ差分 | `{"systemMessage": ...}`（block しない） |
| `stop_hook_active=true` で同一ターンの block が `CLAUDE_STOP_HOOK_MAX_BLOCKS`（既定 3）回に達した | 同上 |
| 確認が `CLAUDE_STOP_HOOK_TIMEOUT` 秒を超えた | 同上（PASS とはみなさない旨を通知） |
| `checkpoint check` 自体の失敗 | stderr に理由を出して exit 1 |

block は exit 0 + JSON の `decision` で返し、exit 2 は使わない。exit 2 以外の非 0 は Claude Code では非ブロッキングのエラーとして扱われるため、hook 自体の失敗で停止を妨げることはない。

block の回数と直前の理由は `<git-dir>/claude-run/runs/<run_id>/stop-hook` に記録する（hook だけが書く。checkpoint の段階は変更しない）。

## block されたときの対応

- 続けられるなら、`reason` に示された次の作業（`verify run` → `record-verify`、レビュー、push など）を進める
- 人の判断が必要・対応できない場合は `checkpoint block "<理由>" "<次に必要な判断>"` で記録してから止まる（`blocked` は停止を許可する）
- 利用者の中断などで不要な active run が残った場合は `checkpoint abandon` で解除する（放置しても TTL を過ぎれば対象外になる）

## 対象外

編集ごとの重い全検証、すべての会話を対象にした強制 hook、CI / branch protection の代替、証跡の改ざん防止。
