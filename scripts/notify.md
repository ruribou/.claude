# notify — デスクトップ通知（opt-in）

`scripts/notify`（配置後は `.claude/scripts/notify`）は、Claude Code が応答を待っているときや作業を終えたときにデスクトップ通知を出す Hook。通知の要否は個人の好みなので、**既定では有効化されない**。

## 導入（opt-in）

[`notify.settings.example.json`](../notify.settings.example.json) の `hooks` を `.claude/settings.local.json`（自分だけ。推奨）か `.claude/settings.json`（チームで共有する場合）にマージする。既存の `PreToolUse` / `Stop` などはそのまま残し、同じイベントの配列に追記する。

| イベント | 通知のタイミング |
| --- | --- |
| `Notification` | 権限の確認・入力待ちなど、Claude Code が利用者の操作を待っているとき |
| `Stop` | 応答を終えたとき |

メッセージは設定の引数で変えられる。

## 動作

- macOS は `osascript`、Linux は `notify-send` を使う。どちらも無い環境では何もしない
- stdin の Hook 入力は読まず、常に exit 0 で終わる（通知の失敗で停止や実行を妨げない）
- macOS で通知が出ない場合は、システム設定の「通知」で、Claude Code を起動しているターミナル（または「スクリプトエディタ」）の通知を許可する

## 確認方法

```bash
.claude/scripts/notify "テスト通知"
```
