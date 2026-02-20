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
is_From_VD=0

use_CSK=1

only_ZSK=0

is_JP=0

DomainListFile=""
use_LocalFile=0

if [[ -z "$TLD_PATTERN" ]] ; then
  TLD_PATTERN='(com|net|jp|me)'
fi

if [[ -z "$NUM_VDDOMAINS" ]] ; then
  NUM_VDDOMAINS=100
elif [[ ! "$NUM_VDDOMAINS" =~ ^[0-9]+$ ]] ; then
  echo 'Illegal environment value, NUM_VDDOMAINS='$NUM_VDDOMAINS
  exit 1
fi

GAWK=$(which gawk > /dev/null)
if [[ $? -ne 0 ]] ; then
  GAWK=$(which awk > /dev/null)
  if [[ $? -ne 0 ]] ; then
    echo 'Not found gawk/awk.'
    exit 1
  fi
fi

if [[ -z "$UDDS_SUDO" && $UID -ne 0 ]] ; then
  SUDO='sudo'
else
  SUDO=$UDDS_SUDO
fi

PDNSCMD="$SUDO pdnsutil"

####
#### print usage & exit
####
function print_usage() {
  echo "Usage: "$0" [options] [DOMAIN_NAME...]"
  echo "options -c,--use-csk     : create CSK keys instad of KSK and ZSK combinations. (default)"
  echo "        -s,--separate-key: create KSK and ZSK keys."
  echo "        -z,--only-zsk    : create only ZSK keys."
  echo "        -d,--all-from-db : get domain names from RDBMS. ignore DOMAIN_NAME arguments."
  echo "        -l,--domain-list : get domain names from a local file. ignore DOMAIN_NAME arguments."
  echo "        -v,--all-from-vd : get domain names from Value-Domain. ignore DOMAIN_NAME arguments."
  exit 1
}


####
#### Get all targeted domain name from Value-Domain
####
function get_all_from_db()
{
  echo 'show tables;' | $SUDO "$PDNS_DB_CMD" "$PDNS_DB_OPT" "$PDNS_DBNAME" > /dev/null 2>&1
  if [[ $? -ne 0 ]] ; then
    echo "Not found Database or Tables."
    exit 1
  fi
  DOM_LIST=$(echo $SQL | $SUDO "$PDNS_DB_CMD" "PDNS_$DB_OPT" "$PDNS_DBNAME" | grep -E -i '^[a-z0-9]+\.'$TLD_PATTERN'$')
  if [[ -z "$DOM_LIST" ]] ; then
    echo "Targeted domain is not found."
    exit 1
  fi
}

####
#### get all domains from Value-Domain
####
function get_all_from_vd()
{
  RESFILE=$(mktemp --tmpdir="$TMPDIR" 'vd-response.XXXXXXXXXX')

  API_ENDPOINT="https://api.value-domain.com/v1/domains"

  API_TOKEN=$(cat "$TOKEN_FILE")
  AUTHZ_HDR="Authorization: Bearer $API_TOKEN"

  CURL_CMD="curl -s -4 -X \"GET\" -H \"${AUTHZ_HDR}\" ${API_ENDPOINT}?limit="${NUM_VDDOMAINS}"\&page=1\&order=asc"
  eval $CURL_CMD > $RESFILE 2>&1

  DOM_LIST=$(jq -r '.results.[].domainname' "$RESFILE" | grep -E -i '^[a-z0-9]+\.'$TLD_PATTERN'$')

  rm $RESFILE
}

####
#### Add zone key
####
function add_zonekey()
{
  key="$1"
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
    printf "Illegal Domain name! [%s]\n" "$DOMAIN"
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

which "$PDNS_DB_CMD" > /dev/null
if [[ $? -ne 0 ]] ; then
  echo "$PDNS_DB_CMD command is not found."
  exit 1
fi

short_opt_str='dcl:svz'
long_opt_str='use-csk,all-from-db.domain-list:,separate-key,all-from-vd,only-zsk'

OPTS=$(getopt -o "$short_opt_str" -l "$long_opt_str" -- "$@")
if [[ $? -ne 0 ]] ; then
  print_usage
fi

eval set -- "$OPTS"
unset OPTS

while true
do
  case "$1" in
    '-c'|'--use-csk')
      use_CSK=1
      ;;
    '-s'|'--separate-key')
      use_CSK=0
      ;;
    '-z'|'--only-zsk')
      only_ZSK=1
      ;;
    '-d'|'--all-from-db')
      is_From_MARIADB=1
      ;;
    '-l'|'--domain-list')
      shift
      if [[ ! -f "$1" ]] ; then
        print_help
      fi
      DomainListFile="$1"
      use_LocalFile=1
      ;;
    '-v'|'--all-from-vd')
      is_From_VD=1
      ;;
    '--')
      shift
      break
      ;;
    *)
      print_usage
      ;;
  esac
  shift
done

if [[ $only_ZSK -ne 0 && $use_CSK -ne 0 ]] ; then
  echo "You cannot use both -s and -z at a time." 
  print_usage
fi

if [[ $is_From_MARIADB -ne 0 && $use_LocalFile -ne 0 ]] ; then
  echo "You cannot use both -a and -l at a time."
  print_usage
fi
if [[ $is_From_VD -ne 0 && $use_LocalFile -ne 0 ]] ; then
  echo "You cannot use both -l and -v at a time."
  print_usage
fi
if [[ $is_From_VD -ne 0 && $is_From_MARIADB -ne 0 ]] ; then
  echo "You cannot use both -a and -v at a time."
  print_usage
fi

DOM_LIST=""

if [[ $is_From_MARIADB -ne 0 ]] ; then
  get_all_from_db
elif [[ $is_From_VD -ne 0 ]] ; then
  get_all_from_vd
elif [[ -n "$DomainListFile" && $use_LocalFile -ne 0 ]] ; then
  DOM_LIST=$(grep -E -i '^[a-z0-9]+\.'$TLD_PATTERN'$' "$DomainListFile")
elif [[ $# > 0 ]] ; then
  DOM_LIST="$@"
else
  print_usage
fi

if [[ ! -d "$TMPDIR" ]] ; then
  mkdir -p "$TMPDIR"
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
