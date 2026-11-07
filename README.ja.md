# Cognito + API Gateway (HTTP API) + ECS Fargate 学習用環境

Terraform でデプロイ可能な、Amazon Cognito 認証の学習用小規模環境です。
本番環境ではなく、学習および低コストでの利用を目的として構築されています。

```
ブラウザ / curl --> API Gateway (HTTP API、Cognito JWT オーソライザー)
                --> VPC リンク --> 内部 ALB --> ECS Fargate (FastAPI)

Cognito ユーザープール <-- サインイン (クライアントが Cognito と直接通信してトークンを受信する)
```

- API Gateway が JWT を検証するため、認証されたリクエストのみがアプリに到達します（パブリックな `/health`、`/`、`/callback` ルートを除く）。
- ALB は内部用（Internal）です。Fargate は NAT ゲートウェイなしでイメージを取得できるようにパブリックサブネット（パブリック IP 付き）で実行されますが、そのセキュリティグループは ALB からのトラフィックのみを受け付けます。

## 前提条件

- Terraform >= 1.5
- AWS CLI（認証済みで、上記のリソースを作成する権限があること）
- Docker
- make

## プロジェクト構成

```
.
├── Makefile
├── app/               FastAPI アプリ、ログインページ (index.html)、Dockerfile
└── terraform/         VPC、セキュリティグループ、Cognito、ECR、ALB、ECS、API Gateway
```

## デプロイ

```
make up
```

これにより、タスク数 0 でインフラストラクチャが作成され、イメージのビルドと ECR へのプッシュが行われた後、サービスのタスク数が 1 にスケールされます。
初回実行には約 10 分かかります。デフォルトリージョンは `ap-northeast-1` です。

## 試してみる

### ブラウザから（認可コードフロー + PKCE）

1. テストユーザーを作成します:
   ```
   make create-user EMAIL=you@example.com PASSWORD='Passw0rd!'
   ```
2. 以下のコマンドで出力される URL を開きます:
   ```
   terraform -chdir=terraform output -raw app_url
   ```
3. **Login** をクリックし、Cognito ホステッド UI でサインインすると、`/callback` にリダイレクトされます。
   ページ内でコードがトークンに交換され、デコードされたアクセストークン / ID トークンと、`/me` からのレスポンスが表示されます。
   ボタンを使用して、アクセストークン付き、ID トークン付き、またはトークンなし（401 が期待されます）で `/me` を呼び出すことができます。

### コマンドラインから

```
make test EMAIL=you@example.com PASSWORD='Passw0rd!'
```

ここでは 3 つのケースを確認します：トークンなしの `/health`（200）、トークンなしの `/me`（401）、Bearer トークン付きの `/me`（200）。
`make token EMAIL=... PASSWORD=...` はアクセストークンのみを出力します（ID トークンを取得するには `TOKEN_TYPE=IdToken` を追加してください）。
これはテスト専用の `USER_PASSWORD_AUTH` フローを使用しています。

### ログ

```
make logs
```

CloudWatch Logs のアプリケーションログを追跡します。401 で拒否されたリクエストは ECS に到達しないため、ここには表示されません。

## クリーンアップ

```
make down
```

内部 ALB とパブリック IP は、存在している間課金されます。作業が完了したら、必ず環境を削除（destroy）してください。

## オプション

| オプション | 方法 |
|---|---|
| プライベートサブネット + VPC エンドポイント（インターネットへのルートなし） | `terraform apply -var private_mode=true`。ecr.api、ecr.dkr、logs、s3 のエンドポイントを作成します。インターフェイスエンドポイントは時間単位で課金されます。 |
| ARM64 (Graviton) | `-var cpu_architecture=ARM64` を設定し、`make PLATFORM=linux/arm64` を実行します。 |
| 追加のコールバック / ログアウト URL | `terraform.tfvars` で `callback_urls` / `logout_urls` を設定します。API Gateway の URL は常に自動的に登録されます。 |
| Cognito ドメインプレフィックス | `domain_prefix` を設定します（予約語 `cognito` を含めることはできません）。 |

## 注意事項

- トークンは学習目的でのみページ上に表示され、`sessionStorage` に保存されます。実際のアプリケーションでは、トークンをメモリ内に保持するか、サーバーサイドセッション（BFF）を使用するべきです。
- HTTP API の JWT オーソライザーは、トークンが失効しているかどうかを確認しないため、トークンは有効期限（デフォルトで 60 分）が切れるまで有効なままになります。
- Terraform のステートはローカルに保存され、`.gitignore` で除外されています。アカウント固有の値が含まれる可能性があるため、`*.tfstate` や `*.tfvars` をコミットしないでください。