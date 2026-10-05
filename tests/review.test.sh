#!/usr/bin/env bash
# scripts/review と reviewer 定義のテスト。隔離した一時リポジトリ（合成 fixture）だけを操作する。
# 実行: bash tests/review.test.sh

set -u

TOP="$(cd "$(dirname "$0")/.." && pwd)"
REVIEW="$TOP/scripts/review"
VERIFY="$TOP/scripts/verify"
FIXTURE="$TOP/tests/fixtures/review-defect"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/review-test.XXXXXX")
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

expect_file() {
  local name="$1" file="$2" pattern="$3"
  if grep -Eq -- "$pattern" "$file" 2>/dev/null; then ok "$name"; else ng "$name (pattern: $pattern in $file)"; fi
}

new_repo() {
  local dir="$WORK/$1"
  mkdir -p "$dir/.claude"
  git -C "$dir" init -q -b main
  git -C "$dir" config user.email test@example.invalid
  git -C "$dir" config user.name test
  printf 'check test . sh test.sh\n' >"$dir/.claude/verify.conf"
  printf 'exit 0\n' >"$dir/test.sh"
  git -C "$dir" add -A && git -C "$dir" commit -q -m init
  git -C "$dir" switch -q -c feature
  printf '%s\n' "$dir"
}

r() { (cd "$REPO" && CLAUDE_REVIEW_VERIFY="$VERIFY" "$REVIEW" "$@"); }
vr() { (cd "$REPO" && "$VERIFY" "$@"); }
latest_id() { cat "$(git -C "$REPO" rev-parse --absolute-git-dir)/claude-review/latest"; }
packet_of() { printf '%s/claude-review/%s/packet.md' "$(git -C "$REPO" rev-parse --absolute-git-dir)" "$1"; }

# result <verdict> <id> [extra lines...] — reviewer の出力を模擬する
result() {
  local verdict="$1" id="$2"
  shift 2
  printf 'VERDICT: %s\nREVIEW_ID: %s\n\n## 指摘\n' "$verdict" "$id"
  if [ $# -gt 0 ]; then printf '%s\n' "$@"; else printf -- '- なし\n'; fi
}

record() { local id="$1"; shift; result "$@" | r record "$id"; }

repo_state() {
  local gd
  gd=$(git -C "$REPO" rev-parse --absolute-git-dir)
  printf '%s\n' "$(git -C "$REPO" rev-parse HEAD)"
  git -C "$REPO" hash-object "$gd/index"
  git -C "$REPO" status --porcelain=v1 --untracked-files=all
  (cd "$REPO" && find . -path ./.git -prune -o -type f -print | LC_ALL=C sort | while IFS= read -r f; do git hash-object "$f"; done)
}

# ------------------------------------------------------------ reviewer 定義

AGENT="$TOP/agents/reviewer.md"
tools=$(awk '/^---$/{n++; next} n==1 && /^tools:/{t=1; next} n==1 && t && /^  - /{sub(/^  - /,""); print; next} n==1 && t{t=0}' "$AGENT")
if [ "$(printf '%s\n' "$tools" | LC_ALL=C sort | tr '\n' ' ')" = "Glob Grep Read " ]; then
  ok "reviewer: tools は Read / Glob / Grep だけ"
else
  ng "reviewer: tools は Read / Glob / Grep だけ" "$tools"
fi
if awk '/^---$/{n++; next} n==1' "$AGENT" | grep -Eq '^(disallowedTools|permissionMode|mcpServers|hooks):'; then
  ng "reviewer: 追加の権限設定を持たない"
else
  ok "reviewer: 追加の権限設定を持たない"
fi

for cmd in review-issue code-review; do
  f="$TOP/commands/$cmd.md"
  expect_file "$cmd: reviewer エージェントを使う" "$f" 'subagent_type: reviewer'
  expect_file "$cmd: review build で packet を作る" "$f" '\.claude/scripts/review build'
  expect_file "$cmd: review record で結果を記録する" "$f" '\.claude/scripts/review record'
  if awk '/^---$/{n++; next} n==1' "$f" | grep -Eq '(^|[^(])Bash([^(]|$)|Write|Edit'; then
    ng "$cmd: allowed-tools に無制限 Bash / Write / Edit がない"
  else
    ok "$cmd: allowed-tools に無制限 Bash / Write / Edit がない"
  fi
done
if grep -Eq '修正し、コミット|指摘事項を修正' "$TOP/commands/code-review.md"; then
  ng "code-review: 自動修正・自動コミットの手順が残っていない"
else
  ok "code-review: 自動修正・自動コミットの手順が残っていない"
fi
[ ! -e "$TOP/skills/review-issue" ] && ok "review-issue: skills と commands の同名二重定義がない" ||
  ng "review-issue: skills と commands の同名二重定義がない"

# ------------------------------------------------------------ 既知の欠陥 fixture（未追跡の新規ファイル）

REPO=$(new_repo defect)
cp "$FIXTURE/backup.sh" "$REPO/backup.sh"
vr run >/dev/null 2>&1
before=$(repo_state)
expect_exit "fixture: build できる" 0 r build --issue-file "$FIXTURE/issue.md"
expect_output "fixture: 範囲を表示する" '^scope: 1 files, base main, pathspec \(all\)'
expect_output "fixture: 検証証跡 VALID" '^verify: VALID'
ID=$(latest_id)
P=$(packet_of "$ID")
expect_file "fixture: 未追跡ファイルが範囲に入る" "$P" '^untracked A	backup\.sh$'
expect_file "fixture: 欠陥行が差分に含まれる" "$P" '^\+eval "cp \$src \$src\.bak"$'
expect_file "fixture: Issue 本文を境界で囲む" "$P" '^----- BEGIN UNTRUSTED-[0-9a-f]+ -----$'
expect_file "fixture: 検証証跡を含む" "$P" '"schema": "claude-verify/v1"'
sed "s/{{REVIEW_ID}}/$ID/" "$FIXTURE/expected-result.md" >"$WORK/expected.md"
expect_exit "fixture: 行番号付き指摘は CHANGES_REQUESTED" 1 r record "$ID" <"$WORK/expected.md"
expect_output "fixture: reviewer の判定どおり" 'RESULT  CHANGES_REQUESTED \(reviewer_changes_requested\)'
expect_file "fixture: 指摘数を記録する" "$(dirname "$P")/result" '^findings=2$'
expect_exit "fixture: status は NOT_PASS" 1 r status
expect_output "fixture: NOT_PASS を表示" '^NOT_PASS'
after=$(repo_state)
if [ "$before" = "$after" ]; then ok "読み取り専用: build / record / status で作業ツリー・index・HEAD が変わらない"; else
  ng "読み取り専用: build / record / status で作業ツリー・index・HEAD が変わらない" "$(diff <(printf '%s\n' "$before") <(printf '%s\n' "$after"))"
fi

# 埋め込み指示に従って PASS を返しても、Critical があれば PASS にならない
expect_exit "fixture: Critical 付き PASS は CHANGES_REQUESTED" 1 \
  record "$ID" PASS "$ID" '- [Critical] backup.sh:5 — eval によるコマンドインジェクション'
expect_output "fixture: pass_with_findings" '\(pass_with_findings\)'

expect_exit "形式: 位置のない CHANGES_REQUESTED は BLOCKED" 2 record "$ID" CHANGES_REQUESTED "$ID" '- [Critical] eval が危険'
expect_output "形式: findings_without_location" '\(findings_without_location\)'
expect_exit "形式: VERDICT 行がなければ BLOCKED" 2 r record "$ID" <<<"looks good"
expect_output "形式: malformed_result" '\(malformed_result\)'
expect_exit "形式: REVIEW_ID 不一致は BLOCKED" 2 record "$ID" PASS "other-id"
expect_output "形式: review_id_mismatch" '\(review_id_mismatch\)'

# ------------------------------------------------------------ 不足する入力を PASS にしない

REPO=$(new_repo missing)
printf 'echo hi\n' >"$REPO/hello.sh"

r build >/dev/null 2>&1
expect_exit "不足: 証跡なし（NONE）の PASS は BLOCKED" 2 record "$(latest_id)" PASS "$(latest_id)"
expect_output "不足: verification_not_valid" '\(verification_not_valid\)'

vr run >/dev/null 2>&1
printf 'echo hi2\n' >"$REPO/hello.sh"
r build >/dev/null 2>&1
expect_exit "不足: 古い証跡（STALE）の PASS は BLOCKED" 2 record "$(latest_id)" PASS "$(latest_id)"
expect_output "不足: STALE も verification_not_valid" '\(verification_not_valid\)'

printf 'exit 1\n' >"$REPO/test.sh"
vr run >/dev/null 2>&1
r build >/dev/null 2>&1
expect_exit "不足: 失敗した証跡（NOT_PASS）の PASS は BLOCKED" 2 record "$(latest_id)" PASS "$(latest_id)"
printf 'exit 0\n' >"$REPO/test.sh"

vr run >/dev/null 2>&1
r build --issue-file "$WORK/no-such-issue.md" >/dev/null 2>&1
expect_exit "不足: Issue を取得できない PASS は BLOCKED" 2 record "$(latest_id)" PASS "$(latest_id)"
expect_output "不足: acceptance_criteria_missing" '\(acceptance_criteria_missing\)'

REPO=$(new_repo empty)
vr run >/dev/null 2>&1
r build >/dev/null 2>&1
expect_exit "不足: 変更ファイルがない PASS は BLOCKED" 2 record "$(latest_id)" PASS "$(latest_id)"
expect_output "不足: empty_scope" '\(empty_scope\)'

REPO=$(new_repo noverify)
printf 'x\n' >"$REPO/x.txt"
(cd "$REPO" && CLAUDE_REVIEW_VERIFY="$WORK/none" "$REVIEW" build) >/dev/null 2>&1
LAST_OUT=$(sed -n 's/^verify_status=//p' "$(dirname "$(packet_of "$(latest_id)")")/meta")
expect_output "不足: verify がなければ UNAVAILABLE" '^UNAVAILABLE$'

# ------------------------------------------------------------ PASS と鮮度

REPO=$(new_repo fresh)
printf 'one\n' >"$REPO/tracked.txt"
git -C "$REPO" add tracked.txt && git -C "$REPO" commit -q -m tracked
printf 'two\n' >>"$REPO/tracked.txt"
printf 'new\n' >"$REPO/new.txt"
printf 'issue\n' >"$WORK/issue.txt"

pass_review() {
  vr run >/dev/null 2>&1
  r build --issue-file "$WORK/issue.txt" >/dev/null 2>&1
  result PASS "$(latest_id)" | r record "$(latest_id)" >/dev/null 2>&1
}

pass_review
expect_exit "鮮度: 条件を満たす PASS は VALID" 0 r status
expect_output "鮮度: VALID を表示" '^VALID'

printf 'three\n' >>"$REPO/tracked.txt"
expect_exit "鮮度: unstaged の変更で STALE" 1 r status
expect_output "鮮度: STALE を表示" '^STALE'

pass_review
git -C "$REPO" add tracked.txt
expect_exit "鮮度: staged の変更で STALE" 1 r status

pass_review
printf 'more\n' >>"$REPO/new.txt"
expect_exit "鮮度: 未追跡ファイルの変更で STALE" 1 r status

pass_review
git -C "$REPO" add -A && git -C "$REPO" commit -q -m wip
expect_exit "鮮度: コミット（HEAD）の変更で STALE" 1 r status

pass_review
vr run >/dev/null 2>&1
expect_exit "鮮度: 検証のやり直しで STALE" 1 r status

pass_review
printf 'issue edited\n' >"$WORK/issue.txt"
expect_exit "鮮度: Issue 本文の変更で STALE" 1 r status

pass_review
git -C "$REPO" switch -q main
printf 'base moved\n' >"$REPO/base.txt"
git -C "$REPO" add base.txt && git -C "$REPO" commit -q -m base
git -C "$REPO" switch -q feature
git -C "$REPO" merge -q --no-edit main
expect_exit "鮮度: ベース・HEAD の更新で STALE" 1 r status

# レビュー中（build と record の間）の変更
vr run >/dev/null 2>&1
r build --issue-file "$WORK/issue.txt" >/dev/null 2>&1
ID=$(latest_id)
printf 'during review\n' >>"$REPO/new.txt"
expect_exit "鮮度: レビュー中の変更は PASS にしない" 2 record "$ID" PASS "$ID"
expect_output "鮮度: inputs_changed_during_review" '\(inputs_changed_during_review\)'
expect_exit "鮮度: その結果は status でも VALID にならない" 1 r status

# ------------------------------------------------------------ 範囲指定

REPO=$(new_repo scope)
mkdir -p "$REPO/src" "$REPO/docs"
printf 'a\n' >"$REPO/src/a.sh"
printf 'b\n' >"$REPO/docs/b.md"
vr run >/dev/null 2>&1
expect_exit "範囲: pathspec で絞れる" 0 r build -- src
expect_output "範囲: 範囲を表示する" '^scope: 1 files, base main, pathspec src$'
P=$(packet_of "$(latest_id)")
expect_file "範囲: 指定内の未追跡ファイルを含む" "$P" '^untracked A	src/a\.sh$'
if grep -q 'docs/b.md' "$P"; then ng "範囲: 指定外のファイルを含まない"; else ok "範囲: 指定外のファイルを含まない"; fi
expect_file "範囲: packet に pathspec を明記" "$P" '^- pathspec: `src`$'

expect_exit "引数: 不正な Issue 番号は拒否" 64 r build --issue 'abc'
expect_exit "引数: 存在しないベースはエラー" 2 r build --base no-such-branch
expect_exit "status: 結果がなければ NONE" 1 env CLAUDE_REVIEW_STATE_DIR="$WORK/empty-state" "$REVIEW" status

printf '\n%d passed, %d failed\n' "$PASSED" "$FAILED"
[ "$FAILED" -eq 0 ]
