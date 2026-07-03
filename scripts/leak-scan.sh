#!/usr/bin/env bash
# 公開耐性ガード: コミット対象（tracked＋未追跡でgitignoreされていない）ファイルに
# 秘密・個人識別子・vaultパスが混入していないか検査。
# 使い方:  ./scripts/leak-scan.sh   → exit 0=クリーン / 1=検出
# コミット前に必ず実行（任意で .git/hooks/pre-commit から呼ぶ）。
#
# 誤検知の抑制: 既知・公開前提の値（例 Firebase公開config）や説明用の例示行は、
# その行に「leak-scan-ignore」というコメントを添えると本文スキャンから除外される。
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2

# 汎用パターン（具体的な識別子を含まない＝この tracked ファイルをコミットしても安全）。
# 精度優先: sk_ は Stripe形式(sk_live_/sk_test_)に限定し "risk_" 等の一般語を誤検知しない。
# sk-ant- は8文字以上の実キーのみ（"sk-ant-..." プレースホルダは拾わない）。
# 秘密鍵は PRIVATE KEY ブロックに限定（CERTIFICATE 等の公開物は対象外）。
GENERIC='sk_(live|test)_[0-9A-Za-z]{10,}|sk-ant-[A-Za-z0-9]{8,}|AIza[0-9A-Za-z_-]{20,}|AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}|-----BEGIN [A-Z ]*PRIVATE KEY|/Users/[A-Za-z0-9]|/home/[A-Za-z0-9]'
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
# leak-scan.sh 自身は除外（実識別子は持たないが、汎用パターン文字列との自己一致を避けるため）。
files=$(git ls-files --cached --others --exclude-standard | grep -v '^scripts/leak-scan\.sh$')

# 1) 本文の識別子スキャン（"leak-scan-ignore" を含む行は既知・公開前提として除外）
hits=""
while IFS= read -r f; do
  [ -f "$f" ] || continue
  m=$(grep -HnE "$PATTERN" "$f" 2>/dev/null | grep -v 'leak-scan-ignore') && hits+="$m"$'\n'
done <<< "$files"
if [ -n "${hits//[$'\n']/}" ]; then
  echo "❌ コミット対象ファイルに識別子/秘密を検出:"
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
