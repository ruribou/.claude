---
name: verify
description: プロジェクトが .claude/verify.conf で明示した検証を実行し、現在の差分に結び付いた証跡を記録する
disable-model-invocation: true
allowed-tools: Bash(.claude/scripts/verify:*), Read
---

# /verify

`.claude/scripts/verify` を実行し、結果を報告するだけの薄い入口。検証ロジック・結果の判定はスクリプト側にあり、ここで検証コマンドを推測・追加しない。仕様は `.claude/scripts/verify.md`。

## 手順

1. リポジトリのルートで `.claude/scripts/verify run` を実行する
2. 出力から次だけを報告する。ログ全文は読み込まない
   - 段階（check）ごとの `PASS` / `FAIL` / `BLOCKED` と理由
   - FAIL の短い抜粋（スクリプトが表示する末尾行）
   - 全体の結果と理由
   - 証跡（`evidence:`）のパス
3. 結果に応じて次の行動を案内する
   - `PASS`: そのまま報告する
   - `FAIL`: 失敗した check を示す。修正はこの入口では行わない
   - `BLOCKED (config_missing / no_checks)`: `.claude/scripts/verify suggest` の候補を提示し、ユーザーが確認して `.claude/verify.conf` に書くよう案内する。候補を実行・書き込みしない
   - `BLOCKED (inputs_changed_during_run)`: 検証中にファイルが変わったため結果は確定していない。編集を止めて再実行するよう案内する
   - その他の `BLOCKED`: 理由（実行ファイル不在など）をそのまま伝える。PASS 扱いしない

詳しい失敗内容が必要なときだけ、該当 check のログ（証跡ディレクトリ内の `runs/<run_id>/<id>.log`）を必要な範囲だけ読む。
