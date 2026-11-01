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

記事の実行環境は Besu 26.2.0、Foundry（forge）1.8.7、solc 0.8.30 です。このリポジトリの `foundry.toml` は `solc_version = "0.8.30"` と `evm_version = "cancun"` を明示しています。クイックスタートの genesis は Cancun まで有効です。生成時間や genesis の中身、ブロック間隔の観測値は末尾の「実行記録・詳細」にまとめています。

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

`web3_clientVersion` が `besu/v26.2.0/...` を返し、`net_peerCount` が `0x4` になれば準備完了です。ブロックが進まない場合は、末尾の「トラブルシューティング」を見てください。

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

## 実行記録・詳細

記事のハンズオン環境（Debian 13、x86_64、8コア、RAM 16GB、Docker 26.1.5、Compose 2.26.1、Node v22.23.2、Foundry 1.8.7）で測った値と、このリポジトリを 2026-11-01 に通し実行した [`logs/run-20261101.md`](logs/run-20261101.md) の結果です。数値は実測のみで、測っていない値は補っていません。

クイックスタートの生成（`npx -y @consensys-software/besu-dev-quickstart@0.2.2`）は約 3.2 秒（`real 0m3.221s`）、イメージの pull を含む `run.sh` は約 21.2 秒（`real 0m21.189s`）でした。2026-11-01 の再実行でも `run.sh` は約 21 秒で終わり、QBFT の validator 4 台と rpcnode、Prometheus / Grafana / Loki / Alloy、任意で有効にした Chainlens が起動しています。プライバシー機能の選択肢は任意の Paladin だけで、Tessera は含まれません。

生成された genesis の chain ID は 1337 で、RPC の `eth_chainId` は `0x539` を返します。`berlinBlock`、`londonBlock`、`shanghaiTime`、`cancunTime` はすべて 0、`zeroBaseFee` は true です。QBFT はブロック間隔 5 秒、リクエストタイムアウト 10 秒、epoch 長 30000 で、`config.toml` では `min-gas-price=0`、`permissions-nodes-config-file-enabled=true`、`revert-reason-enabled=true` が設定されています。ノードの allowlist だけが有効で、アカウントの allowlist は無効です。

| 項目 | 値 |
| --- | --- |
| chain ID | 1337（`eth_chainId` = `0x539`） |
| `berlinBlock` / `londonBlock` / `shanghaiTime` / `cancunTime` | すべて 0 |
| `zeroBaseFee` | true |
| QBFT `blockperiodseconds` | 5 |
| QBFT `requesttimeoutseconds` | 10 |
| QBFT `epochlength` | 30000 |
| `min-gas-price` | 0 |
| `permissions-nodes-config-file-enabled` | true |
| `revert-reason-enabled` | true |

RPC では `web3_clientVersion` が `besu/v26.2.0/linux-x86_64/openjdk-java-25`、`net_peerCount` が `0x4` を返し、validator は次の 4 アドレスでした。記事の環境と 2026-11-01 の再実行で一致しています。

```text
["0x27a97c9aaf04f18f3014c32e036dd0ac76da5f18","0x93917cadbace5dfce132b991732c6cda9bcc5b8a","0x98c1334496614aed49d2e81526d089f7264fed9c","0xce412f988377e31f4d0ff12d74df73b51c42d0ca"]
```

記事の環境でブロック 1〜5 のタイムスタンプを読むと、間隔はちょうど 5 秒でした。

```text
block 1 ts=1792591023 22:57:03 JST
block 2 ts=1792591028 22:57:08 JST
block 3 ts=1792591033 22:57:13 JST
block 4 ts=1792591038 22:57:18 JST
block 5 ts=1792591043 22:57:23 JST
```

Chainlens の `:8081/dashboard` と Grafana の `:3000/login` は HTTP 200、Prometheus の `:9090/graph` は 302 を返しました。画面表示までは確認していません。監視を含めて起動したコンテナは 13 本、メモリ使用量の合計は 2,242MiB で、Besu の 5 ノードは各 324〜400MiB、Grafana は 141MiB、Chainlens web は 123MiB、そのほかは各 75MiB 未満でした。

公式ドキュメントの出力例は Java 21、Test Account 1 の初期残高は 200 ETH と書かれていますが、実際の Besu 26.2.0 イメージは Java 25、生成された genesis と RPC では Test Account 1 の残高は 90000 ETH でした。Java 25 の要件は [Besu のシステム要件](https://docs.besu-eth.org/public-networks/get-started/system-requirements) で確認できます。

`forge build` は solc 0.8.30 と `evm_version=cancun` で成功します。forge 1.8.7 の lint は `missing-events-access-control` として `isAllowed is changed without an event but is used for access control` を出します。`setAllowed` では `AllowlistUpdated` を emit しています。

## トラブルシューティング

記事の実行環境と 2026-11-01 の通し実行で実際に起きた点です。Docker Desktop などで再現するかは未確認のものもあります。

ホストに古い `iptables-legacy` のテーブルがあり、`FORWARD` のポリシーが `DROP` だと、起動直後の peer 数が 0 のままブロック 0 から進みません。2026-11-01 の再実行でも `net_peerCount=0x0` / `eth_blockNumber=0x0` で同じ状態になりました。次の 1 行でクイックスタートの Docker ネットワーク（`172.16.239.0/24`）内通信を許可すると、`peers=0x4` になりブロック生成が始まります。修正前の validator ログには `Moved to round 2 which will expire in 40 seconds` も出ていました。

```bash
sudo iptables-legacy -I DOCKER-USER -s 172.16.239.0/24 -d 172.16.239.0/24 -j ACCEPT
```

`TERM` が未設定だと、`#!/bin/bash -eu` で動く `list.sh` の `tput bold` が失敗し、`run.sh` と `list.sh` が exit 1 で終わります。コンテナ自体は起動しているので、次のコマンドなら exit 0 でエンドポイント一覧を表示できます。

```bash
TERM=xterm ./list.sh
```

ユーザーが docker グループに入っていない場合は、記事の環境と同様に `sudo ./run.sh` を使います。2026-11-01 の検証環境では PID 1 が systemd ではなかったため `service docker start` は使えず、`sudo dockerd` でデーモンを起動してからクイックスタートを走らせました。
