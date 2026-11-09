#!/usr/bin/env bash
# anam の画面を自動操作しながら録画する（Android 実機またはエミュレーター）。
#
#   bash pendant/mobile/demo/record.sh                     # flows/tour.yaml を録画
#   bash pendant/mobile/demo/record.sh flows/xxx.yaml out/xxx.mp4
#
# 必要なもの: adb、scrcpy、maestro（README.md の「準備」）。アプリはインストール済みであること。
# pendant/mobile/local.properties に pendant.api.base / pendant.api.token があれば、
# 録画の前にサーバーの「クラウド送信」をオンにし、相談の履歴を消して毎回同じ状態から始める。
set -euo pipefail
cd "$(dirname "$0")"

APP=dev.lifeos.pendant
FLOW="${1:-flows/tour.yaml}"
OUT="${2:-out/anam-$(date +%Y%m%d-%H%M%S).mp4}"

die() { echo "エラー: $*" >&2; exit 1; }
for c in adb scrcpy maestro; do
  command -v "$c" >/dev/null || die "$c が見つかりません（README.md の「準備」を参照）"
done
[ -f "$FLOW" ] || die "flow がありません: $FLOW"
[ "$(adb devices | awk 'NR > 1 && $2 == "device"' | wc -l)" -eq 1 ] \
  || die "Android 端末かエミュレーターを 1 台だけ接続してください（adb devices）"
adb shell pm path "$APP" >/dev/null 2>&1 \
  || die "アプリが入っていません: (cd pendant/mobile && ./gradlew :androidApp:installDebug)"

# ---- サーバーの準備（トークンは表示しない） ----
prop() { sed -n "s/^$1=//p" ../local.properties 2>/dev/null | tail -1 | tr -d '\r'; }
BASE="$(prop pendant.api.base)"; TOKEN="$(prop pendant.api.token)"
if [ -n "$BASE" ] && [ -n "$TOKEN" ]; then
  auth=(-H "Authorization: Bearer $TOKEN")
  if curl -fsS -m 30 "${auth[@]}" -X PATCH -H "Content-Type: application/json" \
       -d '{"cloud_enabled": true}' "${BASE%/}/settings" >/dev/null; then
    curl -fsS -m 30 "${auth[@]}" -X DELETE "${BASE%/}/assistant/messages" >/dev/null || true
    echo "サーバー: クラウド送信をオンにし、相談の履歴を消しました"
  else
    echo "警告: サーバーに接続できません。アプリは固定データ（台本）で動きます" >&2
  fi
else
  echo "local.properties に接続先がないため、固定データ（台本）で録画します"
fi

# ---- 録画しながら flow を再生 ----
mkdir -p "$(dirname "$OUT")" out/shots
adb shell am force-stop "$APP"   # 起動アニメーションから撮る

opts=(--record "$OUT" --max-size 1280)
# scrcpy 2.0 以降は音声も録ろうとするので止める（1.x にはこのオプションがない）
[ "$(scrcpy --version | head -1 | grep -oE '[0-9]+' | head -1)" -ge 2 ] && opts+=(--no-audio)
# ウィンドウは出さない。出すと、画面の無い環境（エージェントからの実行など）で固まり、止める合図も受け取らない
scrcpy --help 2>&1 | grep -q -- '--no-window' && opts+=(--no-window)
scrcpy "${opts[@]}" >out/scrcpy.log 2>&1 &
REC=$!
# スクリプト内でバックグラウンドにしたプロセスは SIGINT を無視するので TERM で止める（scrcpy は TERM でも mp4 を閉じる）
stop_rec() { kill -TERM "$REC" 2>/dev/null && wait "$REC" 2>/dev/null || true; }
trap stop_rec EXIT
sleep 3   # scrcpy の録画開始待ち

rm -f out/shots/*.png
touch out/.start   # これより新しいスクリーンショットだけを集める
status=0
maestro test "$FLOW" || status=$?
sleep 2   # 最後の画面を少し映す
stop_rec
trap - EXIT
# Maestro 2.x は takeScreenshot を ~/.maestro/tests/<実行日時>/ の下に保存するので、out/shots に集める
find "$HOME/.maestro/tests" -newer out/.start -path '*takeScreenshot*' -name '*.png' -exec cp {} out/shots/ \; 2>/dev/null || true

[ -s "$OUT" ] || die "録画ファイルが作られませんでした（out/scrcpy.log を確認）"
echo "録画: $(pwd)/$OUT"
echo "スクリーンショット: $(pwd)/out/shots/"
[ "$status" -eq 0 ] || die "flow が途中で失敗しました（maestro の出力と ~/.maestro/tests/ のログを確認）"
