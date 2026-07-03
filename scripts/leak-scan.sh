#!/usr/bin/env bash
# 公開耐性ガード: コミットされる内容（ステージ済みblob／未追跡でgitignoreされていないファイル）に
# 秘密・個人識別子・vaultパスが混入していないか検査。
# 使い方:  ./scripts/leak-scan.sh   → exit 0=クリーン / 1=検出 / 2=異常(fail-closed)
# コミット前に必ず実行（任意で .git/hooks/pre-commit から呼ぶ）。
#
# 誤検知の抑制: 既知・公開前提の値（例 Firebase公開config）や説明用の例示行は、
# その行に「leak-scan-ignore」というコメントを添えると本文スキャンから除外される。
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2

# 汎用パターン（具体的な識別子を含まない＝この tracked ファイルをコミットしても安全）。
# - sk-ant-: 実キーは sk-ant-api03-... のようにハイフンを含むため [A-Za-z0-9-]{20,} で捕捉。
#   "sk-ant-..." のようなプレースホルダ（英数が続かない）は拾わない。
# - sk_    : Stripe(sk_live_/sk_test_) と RevenueCat(sk_<英数>) の秘密キー両方を捕捉。
#   直前が英数でない場合のみ一致させ、"ri sk_medium"（risk_medium）等の一般語を誤検知しない。
# - gh[pousr]_ / github_pat_: GitHub の各種トークン。 AKIA: AWS。 xox*: Slack。
# - PRIVATE KEY ブロックに限定（CERTIFICATE 等の公開物は対象外）。
# - /Users/ /home/: 絶対パス（ユーザー名露出）。
GENERIC='sk-ant-[A-Za-z0-9-]{20,}|(^|[^A-Za-z0-9])sk_[A-Za-z0-9_]{16,}|AIza[0-9A-Za-z_-]{20,}|AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}|-----BEGIN [A-Z ]*PRIVATE KEY|/Users/[A-Za-z0-9]|/home/[A-Za-z0-9]'
# 具体的な個人識別子・ブランド名・非公開メール等は gitignore のローカルファイルから読む
# （tracked ファイルに実識別子を直書きしないため。1行1正規表現。scripts/leak-extra.example.txt 参照）。
# ファイルが無ければ汎用のみで走査（fresh clone でも秘密を露出しない）。
PATTERN="$GENERIC"
EXTRA="scripts/leak-extra.txt"
# 識別子リストは追跡してはいけない。git add -f 等で追跡/ステージされていたら異常終了（fail-closed）。
if git ls-files --cached --error-unmatch "$EXTRA" >/dev/null 2>&1; then
  echo "❌ $EXTRA が追跡対象になっています（git add -f 等）。識別子ファイルはコミットしないこと。"
  exit 2
fi
if [ -f "$EXTRA" ]; then
  more=$(grep -vE '^\s*(#|$)' "$EXTRA" | paste -sd '|' -)
  [ -n "$more" ] && PATTERN="$GENERIC|$more"
else
  echo "ℹ️  scripts/leak-extra.txt 無し → 汎用パターンのみで走査（識別子リストは各自ローカルで用意）"
fi

# fail-closed: 不正な正規表現だと grep が status≥2 で失敗し「無検出＝PASS」になる事故を防ぐ。
# 空入力に対し valid=1(no match) / invalid=2(error)。2以上なら安全側で異常終了する。
printf '' | grep -E "$PATTERN" >/dev/null 2>&1
if [ "$?" -ge 2 ]; then
  echo "❌ 検出パターンが不正（scripts/leak-extra.txt の正規表現を確認）。fail-closed で異常終了。"
  exit 2
fi

fail=0

# コミット対象ファイル一覧（tracked＋未追跡・gitignore除外）。
# git 失敗（リポジトリ外等）は「無検出＝PASS」に化けるため fail-closed で止める。
if ! files=$(git ls-files --cached --others --exclude-standard 2>/dev/null); then
  echo "❌ git ls-files に失敗（git リポジトリ外？）。fail-closed で異常終了。"
  exit 2
fi
# leak-scan.sh 自身は除外（実識別子は持たないが、汎用パターン文字列との自己一致を避けるため）。
files=$(printf '%s\n' "$files" | grep -v '^scripts/leak-scan\.sh$')

# 実際にコミットされる内容を検査する。ステージ済みファイルは index の blob を読み
# （pre-commit で worktree とステージ内容がズレても実際に入る内容を見る）、
# 未ステージ/未追跡は worktree を読む。
staged=$(git diff --cached --name-only --diff-filter=ACM 2>/dev/null)

# 1) 本文の識別子スキャン（"leak-scan-ignore" を含む行は既知・公開前提として除外）
hits=""
while IFS= read -r f; do
  [ -n "$f" ] || continue
  if printf '%s\n' "$staged" | grep -qxF "$f"; then
    content=$(git show ":$f" 2>/dev/null)
  elif [ -f "$f" ]; then
    content=$(cat "$f" 2>/dev/null)
  else
    continue
  fi
  m=$(printf '%s\n' "$content" | grep -nE "$PATTERN" 2>/dev/null | grep -v 'leak-scan-ignore' | sed "s#^#$f:#")
  [ -n "$m" ] && hits+="$m"$'\n'
done <<< "$files"
if [ -n "${hits//[$'\n']/}" ]; then
  echo "❌ コミット対象の内容に識別子/秘密を検出:"
  echo "$hits"
  fail=1
else
  echo "✅ 本文スキャン: 0 hits"
fi

# 2) 実データ（data/*.json・*.csv で .example でない）が追跡されていないか
tracked_data=$(git ls-files 'data/*.json' 'data/*.csv' 2>/dev/null | grep -v '\.example\.' || true)
if [ -n "$tracked_data" ]; then
  echo "❌ 実データが追跡対象（gitignore漏れ）:"
  echo "$tracked_data"
  fail=1
else
  echo "✅ 実データファイル: 追跡なし（.example のみ）"
fi

if [ "$fail" -eq 0 ]; then
  echo "── leak-scan: PASS ──"
else
  echo "── leak-scan: FAIL ──"
fi
exit $fail
