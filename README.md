# Update DS records for Value-Domain

これは、[Value-Domain](https://www.value-domain/) で管理しているドメインの DS レコードを更新するシェルスクリプトです。権威 DNS サーバーとして、[PowerDNS]( https://www.powerdns.com/) を使用していることが動作条件です。

#### 必要なシステム・コマンド

|システム／コマンド名|備考|
| ---- | ---- |
| `PowerDNS` | https://www.powerdns.com/ |
| `Bash` | https://www.gnu.org/software/bash/ |
| `Gawk` | https://www.gnu.org/software/gawk/ (BSD awk でも動作するかどうかは検証していません) |
| `GNU Grep` | https://www.gnu.org/software/grep/ |
| `jq` | https://jqlang.org/ |
| `Curl`/`Wget` | https://curl.se/ または、https://www.gnu.org/software/wget/ のいずれか。|

#### 事前設定

1. [Value-Domain](https://www.value-domain.com/) にログインします。
1. マイページへ移動し、API 設定を選択します。
1. 許可 IP を設定します。
1. API トークンを発行します。
1. 取得した API トークンをホームディレクトリの `.vd-token` と名前をつけたファイルに保存します。
1. PowerDNS の API を有効にします。(`pdns.conf` 内の `api` を `yes` に変更し、`api-key` に適切な値を設定して PoerDNS サーバーを再起動します。)
1. PowerDNS に設定した API-Key をホームディレクトリの `.pdns-key` と名前をつけたファイルに保存します。

#### 使用方法

```bash
update-ds.sh [オプション] [ドメイン名...]
   オプション一覧
   -c,--use-csk      :` KSK と ZSK の代わりに、CSK を生成します。(ディフォルトです)
   -s,--separate-key :` CSK ではなく、KSK と ZSK をそれぞれ生成します。
   -z,--only-zsk     :` ZSK だけを更新します。`-s,--separate-key` も合わせて指定しなくてはなりません。
   -l,--domain-list  :` このオプションに続けて指定したファイルからドメイン名を取得して、そのすべてに DS レコードを設定します。引数にドメイン名を指定しても無視されます。
   -p,--all-from-pdns:` PoewrDNS から DNSSEC が有効になっているドメインの一覧を取得して、そのすべてに DS レコードを設定します。引数にドメイン名を指定しても無視されます。
   -v,--all-from-vd  :` Value-Domain からドメイン名の一覧を取得して、そのすべてに DS レコードを設定します。引数にドメイン名を指定しても無視されます。
```

#### 環境変数

|環境変数名|設定内容|
| ---- | ---- |
|`TLD_PATTERN`| `-d`,`-l`,`-v`,`--all-from-db`,`--domain-list`,`--all-from-vd` のいずれかを指定した場合に DS レコードを生成対象とする TLD のパターンを指定します。ディフォルトは、`(com\|net\|jp\|me)` です。|
|`NUM_VDDOMAINS`| `-v`,`--all-from-vd` のどちらかを指定した場合に取得するドメイン数の上限を指定します。ディフォルトは、`100` です。|
|`UDDS_SUDO`  | コマンド実行時に使用する `sudo` または `doas` コマンドをオプションを含めて指定します。ディフォルトは、`sudo` です。|

#### ライセンス

MIT License.
