# tokenize.awk — git-guard / command-guard が共有する Bash コマンドの字句解析。
#   awk -f tokenize.awk < コマンド文字列
#
# シェルの完全な構文解析ではない。引用符・エスケープ・コマンド置換・heredoc・連結/パイプ・
# リダイレクトを区切り、次の行を出力する。
#   T<0|1><単語>   単語。2 文字目が 1 なら変数展開・コマンド置換を含む（動的）
#   B<本文>        heredoc の本文（その heredoc を持つセグメントの中に出る）
#   E              セグメント（; && || | 改行 ( ) で区切られた 1 コマンド）の終端
#   X              閉じていない引用符など、解析しきれなかったことを示す（末尾に 1 回）
# リダイレクトの対象（> の右側）は単語として出力しない。
# bash 3.2 / BSD awk 互換を保つ（macOS 標準環境で動かすため）。

BEGIN { RS = "\001"; ORS = "" }
{ src = src $0 }
END {
  n = length(src); pos = 1; out = ""
  scan(0)
  if (unterminated) out = out "X\n"
  print out
}
function endword(   w) {
  if (inw) {
    if (redir) redir = 0
    else { w = word; gsub(/[\n\t\r]/, " ", w); seg = seg "T" (dyn ? 1 : 0) w "\n" }
  }
  word = ""; inw = 0; dyn = 0
}
function endseg() { endword(); if (seg != "") out = out seg "E\n"; seg = ""; redir = 0 }
function heredoc_bodies(   cnt, parts, i, strip, d, body, nl, line) {
  cnt = split(pend, parts, "\034")
  for (i = 1; i <= cnt; i++) {
    if (parts[i] == "") continue
    strip = (substr(parts[i], 1, 1) == "-"); d = substr(parts[i], 2); body = ""
    while (pos <= n) {
      nl = index(substr(src, pos), "\n")
      if (nl == 0) { line = substr(src, pos); pos = n + 1 } else { line = substr(src, pos, nl - 1); pos += nl }
      if (strip) sub(/^\t+/, "", line)
      if (line == d) break
      body = body " " line
    }
    gsub(/[\t\r]/, " ", body)
    seg = seg "B" body "\n"
  }
  pend = ""
}
function subscan(   s_seg, s_word, s_inw, s_dyn, s_redir, s_pend) {
  s_seg = seg; s_word = word; s_inw = inw; s_dyn = dyn; s_redir = redir; s_pend = pend
  seg = ""; word = ""; inw = 0; dyn = 0; redir = 0; pend = ""
  scan(1)
  seg = s_seg; word = s_word; inw = s_inw; dyn = s_dyn; redir = s_redir; pend = s_pend
}
function backtick(   q, content, s_src, s_n, s_pos) {
  q = index(substr(src, pos + 1), "`")
  if (q == 0) { unterminated = 1; pos = n + 1; return }
  content = substr(src, pos + 1, q - 1); s_pos = pos + q + 1
  s_src = src; s_n = n
  src = content; n = length(content); pos = 1
  subscan()
  src = s_src; n = s_n; pos = s_pos
  dyn = 1; inw = 1; word = word "`...`"
}
function dollar(   c2, q) {
  c2 = substr(src, pos + 1, 1)
  if (c2 == "(") {
    if (substr(src, pos + 2, 1) == "(") {
      q = index(substr(src, pos + 3), "))")
      pos = (q == 0) ? n + 1 : pos + q + 4
      dyn = 1; inw = 1; word = word "$((...))"; return
    }
    pos += 2; dyn = 1; inw = 1; word = word "$(...)"
    subscan(); return
  }
  if (c2 ~ /[A-Za-z_{0-9@*#?!$-]/) { dyn = 1; inw = 1; word = word "$"; pos++; return }
  if (c2 == "\047") { pos++; return }
  word = word "$"; inw = 1; pos++
}
function dquote(   c, c2) {
  while (pos <= n) {
    c = substr(src, pos, 1)
    if (c == "\"") { pos++; return }
    if (c == "\\") {
      c2 = substr(src, pos + 1, 1)
      if (c2 == "\n") { pos += 2; continue }
      if (c2 == "\"" || c2 == "\\" || c2 == "$" || c2 == "`") { word = word c2; pos += 2; continue }
      word = word c; pos++; continue
    }
    if (c == "$") { dollar(); continue }
    if (c == "`") { backtick(); continue }
    word = word c; pos++
  }
  unterminated = 1
}
function redirection(   strip, d, c) {
  if (inw && word ~ /^[0-9]+$/) { word = ""; inw = 0; dyn = 0 } else endword()
  if (substr(src, pos, 3) == "<<<") { pos += 3; redir = 1; return }
  if (substr(src, pos, 2) == "<<") {
    pos += 2; strip = 0
    if (substr(src, pos, 1) == "-") { strip = 1; pos++ }
    while (substr(src, pos, 1) == " " || substr(src, pos, 1) == "\t") pos++
    d = ""
    while (pos <= n) {
      c = substr(src, pos, 1)
      if (c ~ /[ \t\n;|&<>()]/) break
      if (c != "\047" && c != "\"" && c != "\\") d = d c
      pos++
    }
    pend = pend "\034" (strip ? "-" : "=") d
    return
  }
  pos++
  while (substr(src, pos, 1) ~ /[<>&|]/ && pos <= n) pos++
  redir = 1
}
function scan(depth,   c, c2, plevel, q) {
  plevel = 0
  while (pos <= n) {
    c = substr(src, pos, 1)
    if (c == "\\") {
      c2 = substr(src, pos + 1, 1)
      if (c2 == "\n") { pos += 2; continue }
      word = word c2; inw = 1; pos += 2; continue
    }
    if (c == "\047") {
      q = index(substr(src, pos + 1), "\047")
      if (q == 0) { unterminated = 1; word = word substr(src, pos + 1); inw = 1; pos = n + 1; break }
      word = word substr(src, pos + 1, q - 1); inw = 1; pos += q + 1; continue
    }
    if (c == "\"") { pos++; inw = 1; dquote(); continue }
    if (c == "$") { dollar(); continue }
    if (c == "`") { backtick(); continue }
    if (c == " " || c == "\t") { endword(); pos++; continue }
    if (c == "\n") { endword(); pos++; if (pend != "") heredoc_bodies(); endseg(); continue }
    if (c == "&" && substr(src, pos + 1, 1) == ">") { endword(); pos++; redirection(); continue }
    if (c == ";" || c == "&" || c == "|") { endseg(); pos++; continue }
    if (c == "(" && !inw) { endseg(); plevel++; pos++; continue }
    if (c == ")") {
      if (plevel > 0) { plevel--; endseg(); pos++; continue }
      endseg(); pos++
      if (depth > 0) return
      continue
    }
    if (c == "<" || c == ">") { redirection(); continue }
    if (c == "#" && !inw) {
      q = index(substr(src, pos), "\n")
      pos = (q == 0) ? n + 1 : pos + q - 1
      continue
    }
    word = word c; inw = 1; pos++
  }
  endseg()
}
