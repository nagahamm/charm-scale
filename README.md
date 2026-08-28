# マッチングアプリ振り返りAI

マッチングアプリのトーク画面スクショ・プロフィール写真・プロフィール画面を Claude に読ませ、
**相手の食いつき度数 / 自分のメッセージの添削 / 次の一手 / 写真評価 / プロフィール分析** を返す振り返りアプリ(Flutter / iOS・Android)。

## できること

### 会話モード
| 出力 | 内容 |
| :--- | :--- |
| 食いつき度数 | 相手の熱量を 0–100 で採点。会話フェーズ(様子見／盛り上がり／失速 等)も判定 |
| 項目別スコア | 返信速度・文量バランス・質問返し・感情表現・主導権 の5項目で個別採点 |
| 会話の再現 | 実際のトーク画面のような吹き出しでやり取りを再現。添削付きのメッセージはタップで詳細を表示 |
| もっとこうすべきだった | 損をした自分の発言を「送った文 → 問題点 → 改善文 → 理由」で添削。改善文はそのままコピー可 |
| 次に送るならこれ | 現状から送るべき返信案を、トーン違いで2〜3案 |
| 相手のプロフィール(任意) | 会話と同じ相手のプロフィール画面も送ると、年齢・職業・いいね数・自己紹介・興味タグを合わせて分析し、返信案にも活かす。**顔写真からの年齢・外見の推定は行わない**(画面に文字で表示されている情報のみ) |

### 写真モード
写真ごとに(メイン写真バッジ・サムネイル付きで)被写体カテゴリ(人物・ライフスタイル・風景・食事・ペット等)に応じた評価とスコア、必要なら撮り直し指示。項目別評価は第一印象・全体印象の一貫性の2項目。自分のプロフィール画面も送ると、自己紹介文の添削と、いいね数から見た大まかな立ち位置の目安(公開データに基づくAI推定、出典タグ付き)も表示する。

## 使い方

1. モードを選ぶ(会話 / 写真)
2. スクショをカメラまたはライブラリから追加(最大8枚。写真モードは1枚目がメイン写真)
3. 必要なら相手/自分のプロフィール画面も追加
4. 「分析する」

画像は端末側で長辺 1568px に縮小してから送信し、サーバーには保存しない。

## 構成

```
app/                            Flutter アプリ(iOS / Android)
  lib/screens/                  画面
  lib/widgets/                  再利用可能な表示部品
  lib/models/analysis.dart      APIレスポンスの型定義
  lib/services/                 画像の取り込み・縮小、NDJSONストリーム受信、認証
api/functions/analyse.mjs       Claude API 呼び出し(APIキーはサーバー側のみ)
netlify.toml                    Netlify 設定(APIのみ配信)
supabase/migrations/            アカウント・人別履歴用のDBスキーマ(docs/design.md 3節)
docs/requirements.md            要件定義(BDDシナリオ)
docs/design.md                  詳細設計(ドメインモデル・DB設計)
```

- モデル: `claude-opus-5`(vision + adaptive thinking)
- 出力は Structured Outputs(`output_config.format`)で JSON スキーマに固定
- 応答は NDJSON でストリーミングし、関数のタイムアウトを回避

## セットアップ

### バックエンド(api/)

```bash
npm install
npx netlify dev        # http://localhost:8888
```

APIキーはサーバー側の環境変数として設定する(アプリには渡らない)。

```bash
# ローカル
export ANTHROPIC_API_KEY="sk-ant-..."

# 本番(Netlify)
netlify env:set ANTHROPIC_API_KEY "sk-ant-..."
```

### アプリ(app/)

```bash
cd app
flutter pub get
flutter run \
  --dart-define=API_BASE_URL=http://localhost:8888 \
  --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=xxxx
```

`API_BASE_URL` にはバックエンドのURL(本番は Netlify の公開URL)を渡す。
`SUPABASE_URL` / `SUPABASE_ANON_KEY` を渡さない場合、ログイン画面は表示されるがログイン機能は使えない(未設定の警告が出る)。

### アカウント(Supabase)

1. [supabase.com](https://supabase.com) でプロジェクトを作成する。
2. プロジェクトの Settings → API から `Project URL` と `anon public` キーを控える(上記の `SUPABASE_URL` / `SUPABASE_ANON_KEY`)。
3. `supabase/migrations/0001_init.sql` の内容を SQL Editor で実行し、テーブル(`persons` / `analyses` / `usage_counters`)と RLS ポリシーを作成する。
4. Authentication → Providers で Google / Apple を有効化し、各プロバイダのOAuthクライアントを設定する。リダイレクトURLには `io.charmscale.app://login-callback` を追加する。

## デプロイ

バックエンドは Netlify に接続し、`ANTHROPIC_API_KEY` を環境変数に登録する。
アプリは `flutter build ipa` / `flutter build apk` でビルドし、それぞれのストアに配信する。

## 注意

- 判定はAIによる推定であり、結果を保証するものではない。
- スクショには相手の氏名・アイコン・投稿内容が写り込む。第三者の個人情報を扱う自覚を持ち、必要なら伏せてからアップロードすること。
- 相手を操作・強要する助言は返さない。改善対象は常に自分の振る舞い。
