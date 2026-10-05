#!/usr/bin/env bash
# scripts/git-guard のテスト。使い捨てのローカル repo と bare remote、gh / verify のテストダブルだけを操作する。
# 実行: bash tests/git-guard.test.sh

set -u

SRC="$(cd "$(dirname "$0")/.." && pwd)"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/git-guard-test.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

PASSED=0
GOT=""
LAST_REASON=""
FAILED=0

ok() { PASSED=$((PASSED + 1)); printf 'ok   %s\n' "$1"; }
ng() { FAILED=$((FAILED + 1)); printf 'FAIL %s\n' "$1"; [ -z "${2:-}" ] || printf '%s\n' "$2" | sed 's/^/     /'; }

# Hook と同じ配置（scripts/git-guard の隣に verify）を作り、verify はテストダブルにする
HOOK_DIR="$WORK/hook"
mkdir -p "$HOOK_DIR" "$WORK/bin"
cp "$SRC/scripts/git-guard" "$HOOK_DIR/git-guard"
cat >"$HOOK_DIR/verify" <<'EOF'
#!/bin/sh
[ "${VERIFY_STUB:-VALID}" = VALID ] && { echo VALID; exit 0; }
echo "$VERIFY_STUB"; exit 1
EOF
chmod +x "$HOOK_DIR/verify"

# gh のテストダブル: pr view は $GH_STUB_PR の JSON を返す。それ以外は呼び出しを記録するだけ
cat >"$WORK/bin/gh" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"$GH_STUB_LOG"
case "$1 $2" in
  "pr view") cat "$GH_STUB_PR" ;;
esac
EOF
chmod +x "$WORK/bin/gh"
export PATH="$WORK/bin:$PATH"
export GH_STUB_LOG="$WORK/gh.log"
export GH_STUB_PR="$WORK/pr.json"
unset CLAUDE_GIT_GUARD_PROTECTED CLAUDE_GIT_GUARD_REQUIRE_VERIFY

# guard <dir> <command> -> GOT に pass / ask / deny、LAST_REASON に理由を入れる
guard() {
  local out
  out=$(jq -n --arg c "$2" --arg d "$1" '{tool_name: "Bash", tool_input: {command: $c}, cwd: $d}' |
    CLAUDE_PROJECT_DIR="$PROJECT" "$HOOK_DIR/git-guard" pre)
  LAST_REASON=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""' 2>/dev/null)
  if [ -z "$out" ]; then GOT=pass; else GOT=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision'); fi
}

post() {
  jq -n --arg c "$2" --arg d "$1" '{tool_name: "Bash", tool_input: {command: $c}, cwd: $d}' |
    CLAUDE_PROJECT_DIR="$PROJECT" "$HOOK_DIR/git-guard" post
}

expect() { # <name> <want> <dir> <command>
  guard "$3" "$4"
  if [ "$GOT" = "$2" ]; then ok "$1"; else ng "$1 (got $GOT, want $2)" "$LAST_REASON"; fi
}

expect_reason() { # <name> <pattern>
  if printf '%s' "$LAST_REASON" | grep -Eq -- "$2"; then ok "$1"; else ng "$1 (pattern: $2)" "$LAST_REASON"; fi
}

# 判定が pass のときだけ実際に実行する（Claude Code が実行するのと同じ順序）
run() { # <name> <dir> <command>
  local out
  guard "$2" "$3"
  if [ "$GOT" != pass ]; then ng "$1 (guard: $GOT)" "$LAST_REASON"; return 1; fi
  if out=$(cd "$2" && bash -c "$3" 2>&1); then
    post "$2" "$3"
    ok "$1"
  else
    ng "$1 (exec failed)" "$out"; return 1
  fi
}

new_clone() {
  git clone -q "$REMOTE" "$WORK/$1" 2>/dev/null
  git -C "$WORK/$1" config user.email "$1@example.invalid"
  git -C "$WORK/$1" config user.name "$1"
  printf '%s\n' "$WORK/$1"
}

REMOTE="$WORK/remote.git"
git init -q --bare -b main "$REMOTE"
SEED=$(mktemp -d "$WORK/seed.XXXX")
git -C "$SEED" init -q -b main
git -C "$SEED" config user.email seed@example.invalid
git -C "$SEED" config user.name seed
echo base >"$SEED/README"
git -C "$SEED" add README && git -C "$SEED" commit -q -m init
git -C "$SEED" push -q "$REMOTE" main

A=$(new_clone claude)   # 実装担当（Claude）の作業コピー
B=$(new_clone other)    # 別の actor
PROJECT="$A"

# ------------------------------------------------------------ 1. 通常フロー

run "branch 作成" "$A" "git switch -c feat"
echo one >"$A/one.txt"
run "対象ファイルだけ add" "$A" "git add one.txt"
run "heredoc のメッセージで commit" "$A" "git commit -q -m \"\$(cat <<'EOF'
feat: one (first)
EOF
)\""
expect "heredoc 本文の括弧や語は解析に影響しない" pass "$A" "git commit --allow-empty -m \"\$(cat <<'EOF'
fix (unbalanced; git push -f && git reset --hard
EOF
)\""
run "通常 push（upstream 設定）" "$A" "git push -q -u origin feat"
if [ "$(git -C "$REMOTE" rev-parse feat)" = "$(git -C "$A" rev-parse HEAD)" ]; then ok "remote に push された"; else ng "remote に push された"; fi
expect "読み取り系は判定対象外" pass "$A" "git status && git log --oneline -3 && git diff origin/main...HEAD"
expect "fetch は通常操作" pass "$A" "git fetch --prune"

# ------------------------------------------------------------ 2. rebase → 期待 OID 付き force-with-lease

echo upstream >"$B/upstream.txt"
git -C "$B" add upstream.txt && git -C "$B" commit -q -m "upstream change" && git -C "$B" push -q origin main
git -C "$A" fetch -q

expect "退避 ref なしの rebase は止める" deny "$A" "git rebase origin/main"
expect_reason "退避方法を示す" "refs/claude-backup/feat/"
run "退避 ref の作成" "$A" "git update-ref refs/claude-backup/feat/t1 HEAD"
run "作業 branch の rebase" "$A" "git rebase -q origin/main"
OLD=$(git -C "$A" rev-parse origin/feat)
expect "期待 OID なしの lease は止める" deny "$A" "git push --force-with-lease origin feat"
expect "無条件 force は止める" deny "$A" "git push --force origin feat"
expect "+refspec の force は止める" deny "$A" "git push origin +feat"
run "期待 OID 付き force-with-lease" "$A" "git push -q --force-with-lease=feat:$OLD origin feat"
if [ "$(git -C "$REMOTE" rev-parse feat)" = "$(git -C "$A" rev-parse HEAD)" ]; then ok "rebase 後の先端が remote に反映"; else ng "rebase 後の先端が remote に反映"; fi

# ------------------------------------------------------------ 3. 途中で別 actor が remote を更新

git -C "$B" fetch -q && git -C "$B" switch -q feat
echo theirs >"$B/theirs.txt"
git -C "$B" add theirs.txt && git -C "$B" commit -q -m "other actor commit" && git -C "$B" push -q origin feat
THEIRS=$(git -C "$B" rev-parse HEAD)
KNOWN=$(git -C "$A" rev-parse origin/feat)   # A は B の更新を知らない
git -C "$A" commit -q --amend -m "feat: one (amended)"
expect "remote 更新後の lease push は止める" deny "$A" "git push --force-with-lease=feat:$KNOWN origin feat"
expect_reason "remote 更新を報告する" "更新されています"
(cd "$A" && git push -q --force-with-lease="feat:$KNOWN" origin feat 2>/dev/null)
if [ "$(git -C "$REMOTE" rev-parse feat)" = "$THEIRS" ]; then ok "guard を素通りしても lease が他者の commit を守る"; else ng "lease が他者の commit を守る"; fi
git -C "$A" fetch -q
expect "新しい先端を取り直しただけの上書きは止める" ask "$A" "git push --force-with-lease=feat:$THEIRS origin feat"
expect_reason "失われる commit を示す" "$(printf '%s' "$THEIRS" | cut -c1-12)"
# 他者の commit を取り込んでから書き換えた場合は通る
git -C "$A" update-ref refs/claude-backup/feat/t2 HEAD
git -C "$A" rebase -q origin/feat 2>/dev/null || git -C "$A" rebase --abort
run "他者の commit を含めた lease push" "$A" "git push -q --force-with-lease=feat:$THEIRS origin feat"

# ------------------------------------------------------------ 4. 統合ブランチ

expect "統合ブランチへの直接 push は確認" ask "$A" "git push origin feat:main"
expect "統合ブランチの書き換えは止める" deny "$A" "git push --force-with-lease=main:$(git -C "$A" rev-parse origin/main) origin feat:main"
expect "統合ブランチのリモート削除は止める" deny "$A" "git push origin --delete main"
expect "前段でブランチを変える連結は分けさせる" deny "$A" "git switch -q main && git rebase origin/feat"
expect_reason "分割を促す" "分けて"
git -C "$A" switch -q main
expect "統合ブランチの rebase は確認" ask "$A" "git rebase origin/feat"
expect "統合ブランチへの直接 commit は確認" ask "$A" "git commit -m x"
git -C "$A" switch -q feat

# ------------------------------------------------------------ 5. PR の merge

HEAD_A=$(git -C "$A" rev-parse HEAD)
pr_json() { # <head_oid> <base> <mergeState> <checkConclusion> <checkStatus> [review]
  jq -n --arg oid "$1" --arg base "$2" --arg ms "$3" --arg c "$4" --arg s "$5" --arg r "${6:-APPROVED}" \
    '{number: 12, state: "OPEN", isDraft: false, baseRefName: $base, headRefName: "feat", headRefOid: $oid,
      mergeStateStatus: $ms, reviewDecision: $r,
      statusCheckRollup: [{__typename: "CheckRun", name: "ci", status: $s, conclusion: $c}]}' >"$GH_STUB_PR"
}
pr_json "$HEAD_A" main CLEAN SUCCESS COMPLETED
expect "条件が揃った merge commit は通常フロー" pass "$A" "gh pr merge 12 --merge --delete-branch"
expect "--admin は止める" deny "$A" "gh pr merge 12 --merge --admin"
pr_json 0000000000000000000000000000000000000000 main CLEAN SUCCESS COMPLETED
expect "PR head とローカルが不一致なら止める" deny "$A" "gh pr merge 12 --merge"
pr_json "$HEAD_A" develop CLEAN SUCCESS COMPLETED
expect "統合先が想定と違えば確認" ask "$A" "gh pr merge 12 --merge"
pr_json "$HEAD_A" main CLEAN "" IN_PROGRESS
expect "CI 未完了なら止める" deny "$A" "gh pr merge 12 --merge"
pr_json "$HEAD_A" main UNSTABLE FAILURE COMPLETED
expect "CI 失敗なら止める" deny "$A" "gh pr merge 12 --merge"
pr_json "$HEAD_A" main BLOCKED SUCCESS COMPLETED REVIEW_REQUIRED
expect "保護・レビュー条件未達なら止める" deny "$A" "gh pr merge 12 --merge"
pr_json "$HEAD_A" main CLEAN SUCCESS COMPLETED
VERIFY_STUB=STALE expect "検証証跡が古ければ止める" deny "$A" "gh pr merge 12 --merge"
mv "$HOOK_DIR/verify" "$HOOK_DIR/verify.off"
expect "検証の仕組みが無ければ確認" ask "$A" "gh pr merge 12 --merge"
mv "$HOOK_DIR/verify.off" "$HOOK_DIR/verify"
echo dirty >>"$A/one.txt"
expect "未コミット変更があれば merge しない" deny "$A" "gh pr merge 12 --merge"
git -C "$A" checkout -q -- one.txt

# ------------------------------------------------------------ 6. 変更・commit の消失防止

echo wip >>"$A/one.txt"
expect "未コミット変更があれば reset --hard を止める" deny "$A" "git reset --hard origin/main"
expect "変更のあるファイルの checkout -- は確認" ask "$A" "git checkout -- one.txt"
expect "変更の無いファイルの checkout -- は通す" pass "$A" "git checkout -- README"
expect "restore で変更を戻すのは確認" ask "$A" "git restore one.txt"
expect "未コミット変更がある switch -f は確認" ask "$A" "git switch -f main"
expect "未コミット変更がある rebase は止める" deny "$A" "git rebase origin/main"
expect "連結コマンド中の破壊的操作も検出" deny "$A" "git status; git reset --hard"
expect "コマンド置換の中も検出" deny "$A" "echo \$(git reset --hard)"
git -C "$A" checkout -q -- one.txt
echo scratch >"$A/scratch.txt"
expect "未追跡ファイルを消す clean は確認" ask "$A" "git clean -fd"
expect "clean の dry-run は通す" pass "$A" "git clean -nd"
rm "$A/scratch.txt"
expect "未追跡ファイルが無ければ clean は通す" pass "$A" "git clean -fd"

git -C "$A" switch -q -c local-only
echo local >"$A/local.txt" && git -C "$A" add local.txt && git -C "$A" commit -q -m "unpushed"
git -C "$A" switch -q feat
expect "未統合 commit を持つ branch の -D は確認" ask "$A" "git branch -D local-only"
expect "-d は git 自身が未統合を拒否するので通す" pass "$A" "git branch -d local-only"
git -C "$A" branch merged-copy feat
expect "他の ref に含まれる branch の -D は通す" pass "$A" "git branch -D merged-copy"
git -C "$A" switch -q local-only
expect "未 push の commit を捨てる reset は確認" ask "$A" "git reset --hard HEAD~1"
git -C "$A" update-ref refs/claude-backup/local-only/t1 HEAD
expect "退避 ref があれば reset は通す" pass "$A" "git reset --hard HEAD~1"
git -C "$A" switch -q feat
expect "stash drop は確認" ask "$A" "git stash drop"
expect "退避 ref の削除は確認" ask "$A" "git update-ref -d refs/claude-backup/feat/t1"
expect "--no-verify の commit は確認" ask "$A" "git commit --no-verify -m x"

# ------------------------------------------------------------ 7. 通常の実装範囲外

expect "repo 削除は止める" deny "$A" "gh repo delete owner/repo --yes"
expect "公開範囲の変更は止める" deny "$A" "gh repo edit --visibility public"
expect "秘密の設定は止める" deny "$A" "gh secret set TOKEN -b s3cr3t-value"
expect "認証トークンの表示は止める" deny "$A" "gh auth token"
expect "権限 API の変更は止める" deny "$A" "gh api -X PUT repos/o/r/collaborators/x"
expect "repo 自体の API 削除は止める" deny "$A" "gh api --method DELETE repos/o/r"
expect "その他の API 書き込みは確認" ask "$A" "gh api repos/o/r/issues -f title=x"
expect "API の読み取りは通す" pass "$A" "gh api repos/o/r/pulls"
expect "GraphQL mutation は確認" ask "$A" "gh api graphql -f query='mutation { x }'"
expect "個人設定の変更は止める" deny "$A" "git config --global user.name x"
expect "認証に関わるローカル設定は確認" ask "$A" "git config credential.helper store"
expect "通常のローカル設定は通す" pass "$A" "git config branch.feat.description x"
expect "remote の変更は確認" ask "$A" "git remote set-url origin https://example.invalid/x.git"
expect "別 repo への gh 書き込みは確認" ask "$A" "gh -R someone/else pr create --title t --body b"
expect "PR 作成は通す" pass "$A" "gh pr create --title t --body b"
OTHER=$(new_clone outside)
expect "プロジェクト外 repo への書き込みは確認" ask "$A" "git -C $OTHER commit --allow-empty -m x"
expect "プロジェクト外でも読み取りは通す" pass "$A" "git -C $OTHER log -1"

# ------------------------------------------------------------ 8. 解析できない形

expect "シェル経由の git は確認" ask "$A" "bash -c 'git push -f origin feat'"
expect "xargs 経由の git は確認" ask "$A" "echo feat | xargs git branch -D"
expect "動的なコマンド名は確認" ask "$A" "\$GIT push -f"
expect "動的な push 先は確認" ask "$A" "git push origin \$BR"
expect "閉じていない引用符は確認" ask "$A" "git commit -m 'oops"
expect "-c による alias 定義は確認" ask "$A" "git -c alias.p=push p"
expect "無関係なコマンドは対象外" pass "$A" "ls -la .git && cat .git/HEAD"

# ------------------------------------------------------------ 9. 記録

LOG="$(git -C "$A" rev-parse --path-format=absolute --git-common-dir)/claude-guard/log.jsonl"
if [ -s "$LOG" ] && jq -e . "$LOG" >/dev/null 2>&1; then ok "判定記録は JSON Lines"; else ng "判定記録は JSON Lines"; fi
if grep -q 's3cr3t-value' "$LOG"; then ng "秘密の値を記録しない"; else ok "秘密の値を記録しない"; fi
if jq -e 'select(.rule == "push-lease" and .phase == "pre" and (.oids | test("feat:[0-9a-f]+->[0-9a-f]+")))' "$LOG" >/dev/null; then
  ok "lease push の前後 OID を記録"; else ng "lease push の前後 OID を記録" "$(tail -5 "$LOG")"; fi
if jq -e 'select(.phase == "post" and .op == "git push" and (.after | test("feat=[0-9a-f]{40}")))' "$LOG" >/dev/null; then
  ok "実行後の OID を記録"; else ng "実行後の OID を記録"; fi
if jq -e 'select(.decision == "deny" and .rule == "push-remote-moved")' "$LOG" >/dev/null; then
  ok "停止理由を記録"; else ng "停止理由を記録"; fi

# ------------------------------------------------------------ 10. 設定

if jq -e '.hooks.PreToolUse[0].hooks[0].command | test("git-guard pre")' "$SRC/settings.json" >/dev/null &&
  jq -e '.hooks.PostToolUse[0].hooks[0].command | test("git-guard post")' "$SRC/settings.json" >/dev/null; then
  ok "settings.json が Hook を登録"; else ng "settings.json が Hook を登録"; fi
if jq -e '.permissions.allow | index("Bash(*)") or index("Bash")' "$SRC/settings.json" >/dev/null; then
  ng "Bash 全体を無条件許可しない"; else ok "Bash 全体を無条件許可しない"; fi
if grep -Eq '^allowed-tools:.*[[ ,]Bash[],]' "$SRC"/commands/*.md; then ng "commands が Bash 全体を許可しない"; else ok "commands が Bash 全体を許可しない"; fi

printf '\n%d passed, %d failed\n' "$PASSED" "$FAILED"
[ "$FAILED" -eq 0 ]
