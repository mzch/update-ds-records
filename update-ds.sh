#! /usr/bin/env bash

if [[ -z "$PDNS_DB_CMD" ]] ; then
  PDNS_DB_CMD="mariadb"
  PDNS_DB_OPT=""
fi
if [[ -z "$PDNS_DBNAME" ]] ; then
  PDNS_DBNAME="powerdns"
fi

TMPDIR="$HOME/tmp/update-ds"
KEYLIST="$TMPDIR/pdns_key.list"
ZONEINFO="$TMPDIR/zone-info.txt"
UPDATEREC="$TMPDIR/updata.json"

ALG_ED255="ed25519"
ALG_EC256="ecdsa256"
ALG_EC384="ecdsa384"
ALG_ED446="ed448"

SHOWCMD="show-zone"
CHCKCMD="zone check"
LISTCMD="zone list-keys"
DELTCMD="zone remove-key"
ADDKCMD="zone add-key"

TOKEN_FILE="$HOME/.vd-token"

SQL="select name from domains;"

is_From_MARIADB=0

use_CSK=1

only_ZSK=0

is_JP=0

if [[ -z "$TLD_PATTERN" ]] ; then
  TLD_PATTERN='(com|net|jp|me)'
fi

GAWK=$(which gawk)
if [[ $? -ne - ]] ; then
  GAWK=$(which awk)
  if [[ $? -ne 0 ]] ; then
    echo 'Not found gawk/awk.'
    exit 1
  fi
fi

if [[ -z "$UDDS_SUDO" && $UID -ne 0 ]] ' then
  SUDO="sudo"
else
  SUDO=$UDDS_SUDO
fi

PDNSCMD="$SUDO pdnsutil"

####
#### print usage & exit
####
function print_usage() {
  echo "Usage: "$0" [options] [DOMAIN_NAME...]"
  echo "option: -a,--all         : get domains from database. ignore DOMAIN_NAME arguments."
  echo "        -c,--use-csk     : create CSK keys instad of KSK and ZSK combinations. (default)"
  echo "        -s,--separate-key: create KSK and ZSK keys."
  echo "        -z,--only-zsk    : create only ZSK keys."
  exit 1
}

####
#### Add zone key
####
function add_zonekey()
{
  key=$1
  if [[ $is_JP -eq 0 ]] ; then
    $PDNSCMD $ADDKCMD "$DOMAIN" $key "active" "published" "$ALG_EC256" >> "$LOGFILE" 2>&1 || exit 1
  fi
  $PDNSCMD $ADDKCMD "$DOMAIN" $key "active" "published" "$ALG_EC384" >> "$LOGFILE" 2>&1 || exit 1
  $PDNSCMD $ADDKCMD "$DOMAIN" $key "active" "published" "$ALG_ED255" >> "$LOGFILE" 2>&1 || exit 1
  $PDNSCMD $ADDKCMD "$DOMAIN" $key "active" "published" "$ALG_ED446" >> "$LOGFILE" 2>&1 || exit 1
}

####
#### Create DS records
####
function create_ds()
{

  DOMAIN=$1
  DOMAIN=${DOMAIN,,}

  # $PDNSCMD $CHCKCMD "$DOMAIN"
  # if [[ $? -ne 0 ]] ; then
  #   echo "[ERROR] Not found $DOMAIN"
  #   exit1
  # fi

  is_JP=0

  if [[ "$DOMAIN" =~ ([a-z0-9]*)\.([a-z]*)$ ]] ; then
    TLD=${BASH_REMATCH[2]}
    if [[ "$TLD" == "jp" ]] ; then
      is_JP=1
    else
      TLD=${BASH_REMATCH[3]}
      if [[ "$TLD" == "jp" ]] ; then
        is_JP=1
      fi
    fi
  else
    printf "Illegal Domain name! [%s]\n" $DOMAIN 
    return 1;
  fi

  GETID=$(cat <<EOSF
  /^$DOMAIN/ {
    print \$7;
  }
EOSF
  )

GETTAG=$(cat <<EOS
  /^$DOMAIN/ {
    print \$9;
  }
EOS
  )

  $PDNSCMD $LISTCMD "$DOMAIN" > "$KEYLIST" || exit 1
  cat "$KEYLIST" >> "$LOGFILE"

  $GAWK "$GETID" "$KEYLIST" | while read key
  do
    if [[ $only_ZSK -ne 0 && $key != "zsk" ]] ; then
      continue
    fi
    $PDNSCMD $DELTCMD "$DOMAIN" "$key" >> "LOGFILE" || exit 1
  done

  if [[ $use_CSK -eq 0 ]] ; then
    if [[ $only_ZSK -eq 0 ]] ; then
      keys=("zsk" "ksk")
    else
      keys=("zsk")
    fi
    for key in "${keys[@]}"
    do
      echo "Creating "$key" key..." >> "$LOGFILE"
      add_zonekey $key
    done
  else
    add_zonekey
  fi

  echo                        >> "$LOGFILE"
  echo "---"                  >> "$LOGFILE"
  echo "- Just added keys."   >> "$LOGFILE"
  echo "---"                  >> "$LOGFILE"
  echo                        >> "$LOGFILE"
  $PDNSCMD $LISTCMD "$DOMAIN" >> "$LOGFILE" || exit 1

  if [[ $only_ZSK -ne 0 ]] ; then
    retunr 1
  fi

  $PDNSCMD $SHOWCMD "$DOMAIN" > "$ZONEINFO" || exit 1
  cat "$ZONEINFO" >> "$LOGFILE"

  return 0
}

####
#### update DS records via Value-Domain
####
function update_ds()
{

  DOMAIN=$1
  DOMAIN=${DOMAIN,,}

  PICKUPPARAM=$(cat <<EOA
  /^ID/ {
    printf ("id=%s;",   \$3);
    printf ("flag=%s;", substr(\$7,  1, length(\$7)  - 1));
    printf ("tag=%s;",  substr(\$10, 1, length(\$10) - 1));
    printf ("algo=%s;", substr(\$13, 1, length(\$13) - 1));
  }
  /^DS.* 4 .*$/ {
    printf ("digest=%s\n", \$9);
  }
EOA
  )

  loopCount=0
  maxContents=4
  if [[ $is_JP -ne 0 ]] ; then
    maxContents=3
  fi
  echo "{"                            > "$UPDATEREC"
  echo "  \"ds_records\": [" >> "$UPDATEREC"
  $GAWK "$PICKUPPARAM" "$ZONEINFO" | while read x
  do
    loopCount=$(($loopCount + 1))
    eval $x
    SETDS=$(cat <<EVD
      {
        "keytag": "$tag",
        "alg": "$algo",
        "digesttype": "4",
        "digest": "$digest"
      }
EVD
    )
    if [[ $loopCount -lt $maxContents ]] ; then
      SETDS="${SETDS},"
    fi
    echo "${SETDS}" >> "$UPDATEREC"
  done
  echo "]" >> "$UPDATEREC"
  echo "}" >> "$UPDATEREC"

  API_ENDPOINT="https://api.value-domain.com/v1/domains/$DOMAIN/dnssec"

  API_TOKEN=$(cat "$TOKEN_FILE")
  AUTHZ_HDR="Authorization: Bearer $API_TOKEN"
  CTYPE_HDR="Content-Type: application/json"

  CURL_CMD="curl -s -4 -X \"PUT\" -H \"$AUTHZ_HDR\" -H \"$CTYPE_HDR\" -d @${UPDATEREC} -o "$RESFILE" -w '%{http_code}\n' ${API_ENDPOINT}"

  # eval $CURL_CMD || exit 2
  STATUS=$(eval "$CURL_CMD") || exit 2
  if [[ "$STATUS" != "200" ]] ; then
    printf "ERROR! Response Cdoe = %s\n" "$STATUS"
    exit 3
  fi
}

####
#### Main ####
####

if [[ ! -f "$TOKEN_FILE" ]]
then
  echo "API Token file is not found!"
  exit 1
fi

short_opt_str='acsz'
long_opt_str='all,use-csk,separate-key,only-zsk'
OPTS=$(getopt -o "$short_opt_str" -l "$long_opt_str" -- "$@")
if [[ $? -ne 0 ]] ; then
  print_usage
fi

eval set -- "$OPTS"
unset OPTS

while true
do
  case "$1" in
    '-a'|'--all')
      which "$PDNS_DB_CMD" > /dev/null
      if [[ $? -ne 0 ]] ; then
        echo "$PDNS_DB_CMD"' tool is not found.'
        exit 1
      fi
      is_From_MARIADB=1
      ;;
    '-c'|'--use-csk')
      use_CSK=1
      ;;
    '-s'|'--separate-key')
      use_CSK=0
      ;;
    '-z'|'--only-zask')
      only_ZSK=1
      ;;
    '--')
      shift
      break
      ;;
    '*')
      print_usage
      ;;
  esac
  shift
done

if [[ $only_ZSK -ne 0 && $use_CSK -ne 0 ]] ; then
  echo "You need to use both -s and -z at a time." 
  print_usage
fi

if [[ $is_From_MARIADB -ne 0 ]] ; then
  echo 'show tables;' | $SUDO "$PDNS_DB_CMD" "$PDNS_DB_OPT" "$PDNS_DBNAME" > /dev/null 2>&1
  if [[ $? -ne 0 ]] ; then
    echo 'Not found Database or Tables.'
    exit 1
  fi
  DOM_LIST=$(echo $SQL | $SUDO "$PDNS_DB_CMD" "PDNS_$DB_OPT" "$PDNS_DBNAME" | grep -E -i '^[a-z0-9]+\.'"$TLD_PATTERN"'$')
  if [[ -z "$DOM_LIST" ]] ; then
    echo 'Targeted domain is not found.'
    exit 1
  fi
elif [[ $# < 1 ]] ; then
  print_usage
else
  DOM_LIST="$@"
fi

if [[ ! -d "$TMPDIR" ]]
then
  mkdir "$TMPDIR"
fi

for dom in $DOM_LIST
do
  LOGFILE=$(mktemp --tmpdir="$TMPDIR" 'update-ds.XXXXXXXXXX')
  RESFILE=$(mktemp --tmpdir="$TMPDIR" 'vd-response.XXXXXXXXXX')
  touch "$LOGFILE" "$RESFILE"
  create_ds "$dom"
  if [[ $? -eq 0 ]] ; then
    update_ds "$dom" 
  fi
  rm "$LOGFILE" "$RESFILE"
done

exit 0
