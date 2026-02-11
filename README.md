# Update DS records for Value-Domain

---

これは、Value-Domain で管理しているドメインの DS レコードを更新するシェルスクリプトです。権威 DNS サーバーとして、PowerDNS を 使用しており、かつ、バックエンドに RDBMS 使用していることが動作条件です。

#### 必要条件

1. PowerDNS - https://www.powerdns.com/
1. MariaDB  - https://mariadb.com/ または、その他の RDBMS (MariaDB でのみ動作検証をしています)
1. Bash - https://www.gnu.org/software/bash/
1. Gawk - https://www.gnu.org/software/gawk/ (BSD awk でも動作するかどうかは検証していません)
1. curl - https://curl.se/

#### 事前設定

1. value-domain.com にログインします。
1. マイページへ移動し、API 設定を選択します。
1. 許可 IP を設定します。
1. API トークンを発行します。
1. 取得した API トークンをホームディレクトリの `.vd-token` と名前をつけたファイルに保存します。

#### 使用方法

`update-ds.sh [オプション] [ドメイン名...]`

オプション一覧: -a,--all         : RDBMS からドメイン名の一覧を取得して、そのすべてに DS レコードを設定します。引数にドメイン名を指定しても無視されます。<br />
                -c,--use-csk     : KSK と ZSK の代わりに、CSK を生成します。(ディフォルトです)<br />
                -s,--separate-key: CSK ではなく、KSK と ZSK をそれぞれ生成します。<br />
                -z,--only-zsk    : ZSK だけを更新します。<br />

#### 環境変数

TLD_PATTERN: -a|--all を指定した場合に DS レコードを生成対象とする TLD のパターンを指定します。ディフォルトは、`com|net|jp|me` です。
PDNS_DB_CMD: PowerDNS のバックエンドデータベースのアクセスコマンドを指定します。ディフォルトは、`mariadb` です。
PDNS_DB_OPT: PDNS_DB_CMD に渡すオプションを指定します。デフォルトは、`""` です。
PDNS_DBNAME: PowerDNS のデータベース名を指定します。ディフォルトは、`powerdns` です。

#### ライセンス

MIT License.
