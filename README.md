# Besu 社債トークン移転制限ハンズオン

Hyperledger Besu（QBFT）の許可型ネットワーク上で、allowlist 型の社債トークン `AllowlistBond` をデプロイし、移転制限を確認するサンプルです。

対象記事: [Besuで“許可型EVM”を手元に立てて、社債トークンの移転制限を書いてみた](https://github.com/br-to/zenn-content/blob/main/articles/besu-hands-on-bond-transfer-restriction-2026.md)

学習用の最小実装です。ERC-3643/T-REX ではなく、本番の社債を表すコントラクトでもありません。

`.env.example` に入っている秘密鍵は、Besu クイックスタートのドキュメントが公開しているテストアカウントだけです。Ethereum Mainnet や本番ネットワークでは使わないでください。

## 前提

次を導入してください。ドキュメントでは、プライベートネットワーク用に Docker へ最大 6GB のメモリを割り当てるよう案内されています。

- [Docker](https://docs.docker.com/get-docker/) と Docker Compose v2 以上
- [Node.js](https://nodejs.org/)（`npx` が使えること）
- [Foundry](https://book.getfoundry.sh/getting-started/installation)（`forge` / `cast`）
- `curl`

記事の実行環境は Besu 26.2.0、Foundry（forge）1.8.5、solc 0.8.30 です。このリポジトリの `foundry.toml` は `solc_version = "0.8.30"` と `evm_version = "cancun"` を明示しています。クイックスタートの genesis は Cancun まで有効です。

## 1. ネットワークを起動する

記事と同じ選択肢（Private、OTel なし、Chainlens あり、出力先 `./besu-test-network`）で、Besu Developer Quickstart 0.2.2 を生成します。生成された `.env` は `BESU_VERSION=26.2.0` を指定します。

```bash
npx -y @consensys-software/besu-dev-quickstart@0.2.2 --networkType private \
  --outputPath ./besu-test-network --otel false --chainlens true
cd besu-test-network
./run.sh
```

Docker グループに入っていない場合は `sudo ./run.sh` を使います。起動後、JSON-RPC は `http://127.0.0.1:8545` です。

```bash
curl -X POST --data '{"jsonrpc":"2.0","method":"web3_clientVersion","params":[],"id":1}' \
  http://127.0.0.1:8545/ -H "Content-Type: application/json"
curl -X POST --data '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' \
  http://127.0.0.1:8545/ -H "Content-Type: application/json"
```

`web3_clientVersion` が `besu/v26.2.0/...` を返し、`net_peerCount` が `0x4` になれば準備完了です。ブロックが進まない場合は、末尾の「環境依存のトラブル」を見てください。

リポジトリ直下へ戻ります。

```bash
cd ..
```

## 2. `.env` を用意する

```bash
cp .env.example .env
set -a && source .env && set +a
```

| 変数 | 役割 | 公式テストアカウント |
| --- | --- | --- |
| `ISSUER_KEY` | 発行体の秘密鍵 | Test Account 1 |
| `A_KEY` | 投資家Aの秘密鍵 | Test Account 2 |
| `A` | 投資家Aのアドレス | Test Account 2 |
| `B` | 投資家Bのアドレス | Test Account 3 |
| `RPC_URL` | rpcnode の JSON-RPC | `http://127.0.0.1:8545` |
| `TOKEN` | デプロイしたコントラクト | 自分のデプロイ結果を後で入れる |

`TOKEN` は次のデプロイが終わるまで空のままで構いません。

## 3. ビルドする

```bash
forge build
```

`solc 0.8.30` と EVM `cancun` でコンパイルされます。

## 4. デプロイする

額面 1,000,000、満期 `1830297600`（記事と同じコンストラクタ引数）で発行体からデプロイします。`--legacy` は付けません。

```bash
forge create src/AllowlistBond.sol:AllowlistBond \
  --rpc-url "$RPC_URL" --private-key "$ISSUER_KEY" \
  --broadcast --constructor-args 1000000 1830297600
```

出力の `Deployed to:` のアドレスを `.env` の `TOKEN` に入れ、読み直します。

```bash
# TOKEN=0x... を .env に書いたあと
set -a && source .env && set +a
```

## 5. 許可リストへ投資家Aを登録し、発行する

```bash
cast send "$TOKEN" "setAllowed(address,bool)" "$A" true \
  --rpc-url "$RPC_URL" --private-key "$ISSUER_KEY"
cast send "$TOKEN" "issue(address,uint256)" "$A" 100 \
  --rpc-url "$RPC_URL" --private-key "$ISSUER_KEY"
```

## 6. 移転の失敗と成功

投資家Bはまだ許可されていないので、A → B の 10 単位は revert します。`cast send` は送信前の gas 見積もりで `NotAllowed` を検出し、この時点ではトランザクションは送られません。

```bash
cast send "$TOKEN" "transfer(address,uint256)" "$B" 10 \
  --rpc-url "$RPC_URL" --private-key "$A_KEY"
```

B を許可リストに入れたあと、同じ移転は成功します。

```bash
cast send "$TOKEN" "setAllowed(address,bool)" "$B" true \
  --rpc-url "$RPC_URL" --private-key "$ISSUER_KEY"
cast send "$TOKEN" "transfer(address,uint256)" "$B" 10 \
  --rpc-url "$RPC_URL" --private-key "$A_KEY"
```

## 7. 残高を確認する

A が 90、B が 10 になれば成功です。

```bash
cast call "$TOKEN" "balanceOf(address)(uint256)" "$A" --rpc-url "$RPC_URL"
cast call "$TOKEN" "balanceOf(address)(uint256)" "$B" --rpc-url "$RPC_URL"
```

## 8. 片付ける

チェーンデータを残したまま止める場合:

```bash
cd besu-test-network
./stop.sh
```

再開は `./resume.sh` です。コンテナとボリュームまで削除する場合は `./remove.sh` を使います。生成ディレクトリ `besu-test-network/` 自体は残るので、不要なら手元で削除してください。`run.sh` と同様、Docker グループに入っていない場合は `sudo` を付けます。

## 環境依存のトラブル

記事の実行環境で実際に起きた点です。Docker Desktop などで再現するかは未確認のものもあります。

### peer 数が 0 のままブロックが進まない

ホストに古い `iptables-legacy` のテーブルがあり、`FORWARD` のポリシーが `DROP` だと、起動直後の peer 数が 0 のままブロック 0 から進みません。次の 1 行でクイックスタートの Docker ネットワーク内通信を許可すると、`peers=0x4` になりブロック生成が始まります。

```bash
sudo iptables-legacy -I DOCKER-USER -s 172.16.239.0/24 -d 172.16.239.0/24 -j ACCEPT
```

修正前の validator ログには `Moved to round 2 which will expire in 40 seconds` も出ていました。

### `TERM` 未設定で `run.sh` / `list.sh` が exit 1 になる

`TERM` が未設定だと、`#!/bin/bash -eu` で動く `list.sh` の `tput bold` が失敗し、`run.sh` と `list.sh` が exit 1 で終わります。コンテナ自体は起動しています。次なら exit 0 で一覧を表示できます。

```bash
TERM=xterm ./list.sh
```

### ドキュメントの数値と実物が違う

- ドキュメントの出力例は Java 21 ですが、Besu 26.2.0 イメージは Java 25 です
- Test Account 1 の残高はドキュメントでは 200 ETH ですが、生成された genesis と RPC では 90000 ETH です
