#!/usr/bin/env bash
# scripts/verify のテスト。隔離した一時リポジトリ（合成 fixture）だけを操作する。
# 実行: bash tests/verify.test.sh

set -u

VERIFY="$(cd "$(dirname "$0")/.." && pwd)/scripts/verify"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/verify-test.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

PASSED=0
FAILED=0

ok() { PASSED=$((PASSED + 1)); printf 'ok   %s\n' "$1"; }
ng() { FAILED=$((FAILED + 1)); printf 'FAIL %s\n' "$1"; [ -z "${2:-}" ] || printf '%s\n' "$2" | sed 's/^/     /'; }

# expect_exit <name> <expected-code> <command...>
expect_exit() {
  local name="$1" want="$2" out code
  shift 2
  out=$("$@" 2>&1)
  code=$?
  if [ "$code" -eq "$want" ]; then ok "$name"; else ng "$name (exit $code, want $want)" "$out"; fi
  LAST_OUT="$out"
}

expect_output() {
  local name="$1" pattern="$2"
  if printf '%s\n' "$LAST_OUT" | grep -Eq -- "$pattern"; then ok "$name"; else ng "$name (pattern: $pattern)" "$LAST_OUT"; fi
}

new_repo() {
  local dir="$WORK/$1"
  mkdir -p "$dir/.claude"
  git -C "$dir" init -q
  git -C "$dir" config user.email test@example.invalid
  git -C "$dir" config user.name test
  git -C "$dir" config core.fileMode true
  printf '%s\n' "$dir"
}

commit_all() { git -C "$1" add -A && git -C "$1" commit -q -m "$2"; }

v() { (cd "$REPO" && "$VERIFY" "$@"); }

# ------------------------------------------------------------ 2 種類のスタック（設定差し替えのみ）

# スタック A: ルートのシェルスクリプトで検証する想定
REPO=$(new_repo stack-a)
mkdir -p "$REPO/scripts"
printf '#!/bin/sh\necho lint ok\n' >"$REPO/scripts/lint.sh"
printf '#!/bin/sh\necho test ok\n' >"$REPO/scripts/test.sh"
chmod +x "$REPO/scripts/lint.sh" "$REPO/scripts/test.sh"
cat >"$REPO/.claude/verify.conf" <<'EOF'
# stack A
check lint . scripts/lint.sh
check test . sh scripts/test.sh
EOF
commit_all "$REPO" init
expect_exit "stack A: 設定どおりに PASS" 0 v run
expect_output "stack A: 各段の結果を表示" '^PASS +lint'
expect_output "stack A: 証跡の位置を表示" '^evidence: .*/claude-verify/runs/.*/evidence.json'
expect_exit "stack A: 同じ入力の証跡は VALID" 0 v status

# スタック B: サブディレクトリの独自ツールで検証する想定
REPO=$(new_repo stack-b)
mkdir -p "$REPO/service/bin"
printf '#!/bin/sh\n[ "$1" = check ] && [ -f main.src ] && echo built\n' >"$REPO/service/bin/fake-build"
chmod +x "$REPO/service/bin/fake-build"
printf 'source\n' >"$REPO/service/main.src"
cat >"$REPO/.claude/verify.conf" <<'EOF'
# stack B
check build service bin/fake-build check
EOF
commit_all "$REPO" init
expect_exit "stack B: 作業ディレクトリを指定して PASS" 0 v run
EVIDENCE=$(printf '%s\n' "$LAST_OUT" | sed -n 's/^evidence: //p')
if grep -q '"cwd": "service"' "$EVIDENCE" && grep -q '"exit_code": 0' "$EVIDENCE" &&
  grep -q '"log": "runs/' "$EVIDENCE" && grep -q '"fingerprint": "' "$EVIDENCE"; then
  ok "stack B: 証跡に識別子・終了コード・ログ参照・スナップショットを記録"
else
  ng "stack B: 証跡の項目" "$(cat "$EVIDENCE")"
fi
if grep -q 'fake-build' "$EVIDENCE"; then ng "証跡に argv 本文を保存しない"; else ok "証跡に argv 本文を保存しない"; fi
if git -C "$REPO" status --porcelain | grep -q .; then
  ng "証跡・ログが作業ツリーを汚さない" "$(git -C "$REPO" status --porcelain)"
else
  ok "証跡・ログが作業ツリーを汚さない"
fi

# ------------------------------------------------------------ 結果の区別

REPO=$(new_repo results)
commit_all "$REPO" init >/dev/null 2>&1 || git -C "$REPO" commit -q --allow-empty -m init

expect_exit "設定ファイルなし は BLOCKED" 2 v run
expect_output "設定ファイルなし の理由" 'BLOCKED \(config_missing\)'
expect_exit "BLOCKED の証跡は status で NOT_PASS" 1 v status
expect_output "NOT_PASS を表示" '^NOT_PASS'

printf '# nothing\n' >"$REPO/.claude/verify.conf"
expect_exit "check 未設定 は BLOCKED" 2 v run
expect_output "check 未設定 の理由" 'BLOCKED \(no_checks\)'

printf 'check lint .\n' >"$REPO/.claude/verify.conf"
expect_exit "コマンド未設定の check は BLOCKED" 2 v run
expect_output "コマンド未設定 の理由" 'command_missing'

printf 'check lint . definitely-not-a-real-command-xyz\n' >"$REPO/.claude/verify.conf"
expect_exit "実行ファイル不在 は BLOCKED" 2 v run
expect_output "実行ファイル不在 の理由" 'executable_not_found'

printf 'check lint . ./missing.sh\n' >"$REPO/.claude/verify.conf"
expect_exit "相対パスの実行ファイル不在 は BLOCKED" 2 v run

printf 'check lint nope true\n' >"$REPO/.claude/verify.conf"
expect_exit "作業ディレクトリ不在 は BLOCKED" 2 v run
expect_output "作業ディレクトリ不在 の理由" 'cwd_missing'

printf 'check lint ../outside true\n' >"$REPO/.claude/verify.conf"
expect_exit "リポジトリ外の作業ディレクトリ は設定エラー" 2 v run
expect_output "設定エラー の理由" 'config_invalid'

printf '#!/bin/sh\necho line-before-failure\nexit 3\n' >"$REPO/fail.sh"
printf 'check ok . true\ncheck bad . sh fail.sh\n' >"$REPO/.claude/verify.conf"
expect_exit "非ゼロ終了 は FAIL" 1 v run
expect_output "FAIL の終了コード" '^FAIL +bad \(nonzero_exit, exit 3\)'
expect_output "FAIL の短い抜粋" '\| line-before-failure'
expect_output "他の check は PASS のまま" '^PASS +ok'

printf 'check ok . true\ncheck gone . definitely-not-a-real-command-xyz\n' >"$REPO/.claude/verify.conf"
expect_exit "PASS と BLOCKED の混在は PASS にしない" 2 v run

printf 'check a . true\ncheck a . true\n' >"$REPO/.claude/verify.conf"
expect_exit "重複した識別子は設定エラー" 2 v run

printf 'check a . echo $(touch pwned)\n' >"$REPO/.claude/verify.conf"
expect_exit "argv をシェル評価しない" 0 v run
if [ -e "$REPO/pwned" ] || [ -e "$REPO/pwned)" ]; then ng "argv をシェル評価しない（副作用なし）"; else ok "argv をシェル評価しない（副作用なし）"; fi

# ------------------------------------------------------------ 鮮度（古い証跡の無効化）

REPO=$(new_repo freshness)
mkdir -p "$REPO/generated"
printf 'a\n' >"$REPO/tracked.txt"
printf 'x\n' >"$REPO/to-delete.txt"
printf 'generated/\n.env.local\n' >"$REPO/.gitignore"
printf 'v1\n' >"$REPO/generated/schema.json"
printf 'SECRET=hunter2\n' >"$REPO/.env.local"
cat >"$REPO/.claude/verify.conf" <<'EOF'
check noop . true
input generated
input .env.local
EOF
commit_all "$REPO" init

assert_stale_after() {
  local name="$1"
  expect_exit "$name: 変更前は VALID" 0 v status
  shift
  "$@"
  expect_exit "$name: 変更後は STALE" 1 v status
  expect_output "$name: STALE を表示" '^STALE'
  v run >/dev/null 2>&1
}

v run >/dev/null 2>&1
assert_stale_after "HEAD" git -C "$REPO" commit -q --allow-empty -m next
assert_stale_after "unstaged" sh -c "printf 'b\n' >>'$REPO/tracked.txt'"
assert_stale_after "staged" git -C "$REPO" add tracked.txt
assert_stale_after "untracked 追加" sh -c "printf 'new\n' >'$REPO/new.txt'"
assert_stale_after "untracked 内容変更" sh -c "printf 'changed\n' >'$REPO/new.txt'"
assert_stale_after "削除" rm "$REPO/to-delete.txt"
assert_stale_after "モード変更" chmod +x "$REPO/tracked.txt"
assert_stale_after "宣言済み追加入力（ディレクトリ内）" sh -c "printf 'v2\n' >'$REPO/generated/schema.json'"
assert_stale_after "宣言済み追加入力（ファイル）" sh -c "printf 'SECRET=other\n' >'$REPO/.env.local'"
assert_stale_after "アダプター設定" sh -c "printf '# comment\n' >>'$REPO/.claude/verify.conf'"

expect_exit "変更がなければ再実行後に VALID" 0 v status
printf '.ignored-but-undeclared\n' >>"$REPO/.git/info/exclude"
printf 'ignored\n' >"$REPO/.ignored-but-undeclared"
expect_exit "未宣言の ignore 済みファイルは対象外" 0 v status

LATEST_EVIDENCE=$(sed -n 's/^evidence=//p' "$REPO/.git/claude-verify/latest")
if grep -rq 'hunter2\|SECRET=other' "$REPO/.git/claude-verify"; then
  ng "追加入力の本文を証跡に保存しない"
else
  ok "追加入力の本文を証跡に保存しない"
fi
if [ -f "$LATEST_EVIDENCE" ]; then ok "latest が証跡を指す"; else ng "latest が証跡を指す"; fi

# ------------------------------------------------------------ 検証中の入力変更

REPO=$(new_repo during-run)
printf 'a\n' >"$REPO/tracked.txt"
printf '#!/bin/sh\nprintf "b\\n" >> tracked.txt\n' >"$REPO/mutate.sh"
printf 'check mutate . sh mutate.sh\n' >"$REPO/.claude/verify.conf"
commit_all "$REPO" init
expect_exit "検証中に追跡ファイルが変わると PASS にしない" 2 v run
expect_output "検証中の変更の理由" 'BLOCKED \(inputs_changed_during_run\)'
expect_exit "検証中に変わった run の証跡は無効" 1 v status

REPO=$(new_repo during-run-untracked)
printf '#!/bin/sh\necho out > build-output.txt\n' >"$REPO/gen.sh"
printf 'check gen . sh gen.sh\n' >"$REPO/.claude/verify.conf"
commit_all "$REPO" init
expect_exit "検証中に未追跡ファイルが増えると PASS にしない" 2 v run

# ------------------------------------------------------------ suggest

REPO=$(new_repo suggest)
printf '{"scripts": {"lint": "eslint .", "test": "vitest"}}\n' >"$REPO/package.json"
printf 'test:\n\ttrue\n' >"$REPO/Makefile"
expect_exit "suggest は候補だけを表示" 0 v suggest
expect_output "package.json の候補" '^# check lint \. npm run lint'
expect_output "Makefile の候補" '^# check test \. make test'
if [ -e "$REPO/.claude/verify.conf" ] || [ -d "$REPO/.git/claude-verify" ]; then
  ng "suggest は設定・証跡を作らない"
else
  ok "suggest は設定・証跡を作らない"
fi

printf '\n%d passed, %d failed\n' "$PASSED" "$FAILED"
[ "$FAILED" -eq 0 ]
