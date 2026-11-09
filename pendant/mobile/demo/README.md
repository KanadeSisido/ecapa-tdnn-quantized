# demo/ — アプリ画面の自動録画

anam（`pendant/mobile` の Android アプリ）を **Maestro で自動操作しながら、scrcpy で mp4 に録画する**。
人がやっても、AI エージェント（Claude Code など）に任せてもよい。エージェントに渡すプロンプトは[一番下](#ai-エージェントに渡すプロンプト)にある。

| ファイル | 内容 |
|---|---|
| `record.sh` | 録画の開始 → flow の再生 → 録画の停止までを 1 コマンドで行う |
| `flows/tour.yaml` | 全画面ツアー（ホーム → 要約で相談 → 報告書 → ログ → 診療 → 設定） |
| `out/` | 録画（mp4）とスクリーンショットの出力先。Git には入らない |

Playwright はブラウザ専用なので、このネイティブアプリには使えない。

## 準備（初回だけ）

Linux か macOS。Android Studio は不要。

1. **JDK 17 以上**と **Android SDK**（platform 36、platform-tools）。`adb` に PATH を通す。
2. **Maestro**（JDK 17 以上が必要）:
   ```bash
   curl -fsSL "https://get.maestro.mobile.dev" | bash
   ```
3. **scrcpy**（2.x 以上を推奨）: macOS は `brew install scrcpy`。Linux は `apt install scrcpy`。apt の版が古いときは GitHub のリリース版を使う。
4. **端末**: 次のどちらか。
   - **Android 実機（推奨）**: 開発者向けオプションで USB デバッグを有効にし、USB でつなぐ。
   - **エミュレーター**:
     ```bash
     sdkmanager "system-images;android-36;google_apis;x86_64" "emulator"
     avdmanager create avd -n anam -k "system-images;android-36;google_apis;x86_64" -d pixel_7
     emulator -avd anam &
     ```
     Bluetooth はないが、録画には影響しない（ホームは「録音中」の表示のまま）。
5. **サーバーの接続先**: `pendant/mobile/local.properties` に書く。このファイルは Git に入らない。
   ```properties
   pendant.api.base=https://pendant-api-756406909128.asia-northeast1.run.app
   pendant.api.token=<チームから受け取ったトークン>
   ```
   書かなければ、固定データ（台本）で動く。AI の返答は出ないが、録画はできる。
6. **アプリのビルドとインストール**:
   ```bash
   cd pendant/mobile
   ./gradlew :androidApp:installDebug
   ```
   `local.properties` を書き換えたら、ビルドし直すこと（値はビルド時に埋め込まれる）。

`adb devices` で端末が 1 台だけ `device` と出れば準備完了。

## 録画する

```bash
bash pendant/mobile/demo/record.sh
```

- 出力: `pendant/mobile/demo/out/anam-<日時>.mp4` と、`out/shots/*.png`（各画面のスクリーンショット）。
- 接続先があれば、録画の前にサーバーの**クラウド送信をオン**にし、**相談の履歴を消す**。毎回同じ状態から撮れる。
- 所要時間は 1〜2 分。Gemini の返答待ちがあるため。

別の flow を撮る: `bash pendant/mobile/demo/record.sh flows/xxx.yaml out/xxx.mp4`

flow だけを録画せずに試す: `cd pendant/mobile/demo && maestro test flows/tour.yaml`

## 自分で flow を書くときの注意

- **画面の文言で要素を指定する。** 文言は `androidApp/src/main/kotlin/dev/lifeos/pendant/android/ProductUi.kt` と `MainActivity.kt` にある。Maestro は文言を**正規表現として全体一致**で比べる。`(` や `?` などの半角記号はエスケープが必要。全角の `（` `？` はそのままでよい。
- **「要約」はタブとログ画面の絞り込みボタンの 2 か所にある。** ログ画面にいるときに `tapOn: "要約"` を使わない。
- **AI の返答は毎回変わる。** 返答の文で待たずに、`聞いています…` / `Gemini で作成中…` が消えるのを待つ。
- **声の相談（「押して話す」）は自動化しにくい。** 声を入れられないため。録画では「文字で入力する」→ 提案ボタンを使う。押すとマイク権限のダイアログが出る点にも注意。
- **日本語の文字入力（`inputText`）は、Android では入らないことがある。** ボタンをタップする操作で組む。
- **「クラウドに送信する」のスイッチは文言から押せない。** スイッチは文言の右にある別の要素のため。オン・オフは `record.sh` が API で切り替える。

## うまくいかないとき

| 症状 | 対処 |
|---|---|
| `Element not found` で止まる | 画面の文言が変わった可能性がある。`out/shots/` の最後の画像と `ProductUi.kt` を見て、flow を直す |
| AI の返答の代わりに「台本で返答」と出る | `local.properties` の接続先を確認し、アプリを入れ直す。サーバーが起動直後なら数秒待つ |
| 「設定でクラウド送信をオンにすると使えます」と出る | `record.sh` がクラウド送信をオンにする前にアプリが起動していた。もう一度 `record.sh` を実行する |
| mp4 ができない | `out/scrcpy.log` を見る。scrcpy が古いときは更新する |
| 録画が真っ黒 | エミュレーターの GPU 設定を変える（`emulator -avd anam -gpu swiftshader_indirect`） |

iOS を撮る場合（Mac が必要）: シミュレーターに対しても `maestro test` は使える。録画は `xcrun simctl io booted recordVideo out/ios.mp4`（Ctrl+C で終了）。flow の文言は `iosApp/Sources/ProductViews.swift` に合わせる。

---

## AI エージェントに渡すプロンプト

リポジトリを clone したディレクトリで、エージェント（Claude Code など）に次をそのまま貼る。
`local.properties`（接続先とトークン）は、**人が先に用意しておく**こと。トークンをプロンプトに書かない。

```text
pendant/mobile の Android アプリ「anam」の画面を、自動操作しながら mp4 に録画してください。

手順書: pendant/mobile/demo/README.md（必ず最初に全部読むこと）
使うもの: pendant/mobile/demo/record.sh と pendant/mobile/demo/flows/tour.yaml

やること:
1. README の「準備」を上から確認し、足りないものだけ入れる（JDK 17+、Android SDK、adb、Maestro、scrcpy）。
   インストールにパスワードや承認が必要なら、私に頼んでください。
2. `adb devices` で端末が 1 台つながっているか確認する。つながっていなければ、README の手順でエミュレーターを作って起動する。
3. pendant/mobile/local.properties があるか確認する（中身のトークンは表示しない・ログに出さない）。
   なければ作らずに私に知らせ、固定データのまま進めてよいか聞く。
4. `cd pendant/mobile && ./gradlew :androidApp:installDebug` でアプリを入れる。
5. `bash pendant/mobile/demo/record.sh` で録画する。
6. 結果を確認する:
   - mp4 ができていて、サイズが 0 でないこと
   - out/shots/ のスクリーンショットを開いて見て、各画面（ホーム・要約の返答・報告書・ログ・診療・設定）が映っていること
   - 要約の返答が「台本で返答」になっていないこと（接続先がある場合）
7. flow が途中で失敗したら、最後のスクリーンショットと ProductUi.kt / MainActivity.kt の文言を比べて
   flows/tour.yaml を直し、もう一度録画する。3 回失敗したら止めて、原因を報告する。

守ること:
- アプリ本体（androidApp/、shared/、iosApp/）のコードは変えない。直してよいのは pendant/mobile/demo/ の中だけ。
- サーバー（server/）のデプロイや設定変更はしない（record.sh が行うクラウド送信のオンと履歴の削除は除く）。
- local.properties・トークン・out/ を Git にコミットしない。push はしない。
- 声の相談（「押して話す」）は自動化しない。

最後に報告してほしいこと:
- mp4 のパス、長さ（秒）、サイズ
- 各スクリーンショットで何が映っていたか（1 行ずつ）
- flow を直した場合は、その差分と理由
- うまくいかなかったことがあれば、そのまま書く
```
