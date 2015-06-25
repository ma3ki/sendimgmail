#!/bin/sh
#
# 2014/12/10 v0.01: created by ma3ki@ma3ki.net
# 2015/04/04 v0.02: add the attached function of the graph of the screen
# 2015/06/03 v0.03: add -s and -S to the option of the curl command
#
# This script has been tested by Zabbix 2.4 on CentOS 7.1 .
# 
# please install mutt command
# yum install mutt
#
# Usage)
# ./sendimgmail.sh <mailAddress> <subject> <message>
#
# Test example)
# ./sendimgmail.sh hogehoge@example.com "test" "$(echo -e "host: Zabbix server\nkey: system.cpu.load[percpu,avg1]")"

### set language
export LANG=ja_JP.utf8

### READ CONFIG
CURRENT_PATH=$(dirname $0)
source ${CURRENT_PATH}/sendimgmail.conf

### set SCRIPT NAME
SCRIPT=$(basename $0)

### set basic authentication
AUTH=""
if [ "${BASIC_USER}x" != "x" ]
then
  AUTH="--user ${BASIC_USER}:${BASIC_PASS}"
fi

######## zabbix_api #######
# usage)
# _zabbix_api <method> <param1> <param2> ....
#
# user.login
#   Return   = sessionid
# 
# host.get,item.get,graph.get,screen.get
#   <param1> = sessionid
#   <param2> = field name of return value
#   <param3> = output rule
#   <param4> = filter rule
#   Return   = fieldid(s)
###########################
_zabbix_api() {

  header="Content-Type:application/json-rpc"
  method=$1

  case ${method} in
    user.login)
      jsontemp=$(curl ${AUTH} -X GET -H ${header} -s -S -d "{
        \"auth\":null,
        \"method\":\"${method}\",
        \"id\":1,
        \"params\":{
          \"user\":\"${ZABBIX_USER}\",
          \"password\":\"${ZABBIX_PASS}\"
        }, \"jsonrpc\":\"2.0\"
      }" ${ZABBIX_API} )

      result=$(echo "${jsontemp}" | sed -e 's/[,{}]/\n/g' -e 's/"//g' | awk -F: '/^result/{print $2}')

      ;;
    *.get)
      ### get result
      sid=$2
      return=$3
      output=""
      graphid=""

      ### read params
      for x in $(seq 4 $#)
      do
        ARGV=$(eval echo \$${x})
        if [ $(echo ${ARGV} | egrep -c "output|selectScreenItems") -eq 1 ]
        then
          output=${ARGV}
        elif [ $(echo ${ARGV} | grep -c "filter") -eq 1 ]
        then
          output="${output},${ARGV}"
        elif [ $(echo ${ARGV} | egrep -c "^[0-9]+$") -eq 1 ]
        then
          graphid=${ARGV}
        fi
      done
       
      ### get data
      jsontemp=$(curl ${AUTH} -X GET -H ${header} -s -S -d "{
        \"auth\":\"${sid}\",
        \"method\":\"${method}\",
        \"id\":1,
        \"params\":{
          ${output}
        }, \"jsonrpc\":\"2.0\"
      }" ${ZABBIX_API})

      if [ ${method} = "screen.get" ]
      then
        result=$(echo "${jsontemp}" | sed -e 's/[,{}]/\n/g' -e 's/"//g' | awk -F: '/^name:|^resourceid:|^resourcetype:/{print $1","$2}')

        sname=""
        gid=""
        match=0
        for x in $(echo ${result})
        do
          field=$(echo ${x} | awk -F, '{print $1}')
          value=$(echo ${x} | awk -F, '{print $2}')

          if [ ${field} = "name" ]
          then
            if [ ${match} -eq 1 ]
            then
              break
            fi
            sname=${value}
            gid=""
          elif [ "${field}" = "resourcetype" ]
          then
            rtype=${value}
          elif [ "${field}" = "resourceid" ]
          then
            if [ ${graphid} -eq ${value} -a ${rtype} -eq 0 ]
            then
              match=1
            fi
            if [ ${rtype} -eq 0 ]
            then
              gid="${gid} ${value}"
            fi
          fi

        done

        if [ $match -eq 1 ]
        then
          result="${sname},${gid}"
        else
          result=""
        fi

      else
        result=$(echo "${jsontemp}" | sed -e 's/[,{}]/\n/g' -e 's/"//g' | awk -F: "/^${return}:/{print \$2}")
      fi
      ;;
    *)
      ;;
  esac

  if [ "${result}x" = "x" ]
  then
    echo "Error"
  fi

  echo ${result}
}

### get graph image
_get_graph_image() {

  mopt=""
  for x in $(echo $1)
  do
    notupdate=0
    if [ -f "${IMAGE_TEMP}/${x}.png" ]
    then
      modtime=$(stat --printf=%Y ${IMAGE_TEMP}/${x}.png)
      if [ $(date +%s) -lt $((${modtime} + ${GRAPH_UPDATE_INTERVAL})) ]
      then
        notupdate=1
        logger -t ${SCRIPT} -p ${PRITEXT} "host=${HOST}, key=${KEY}, stat=Skip, image=${IMAGE_TEMP}/${x}.png, size=$(stat --printf=%s ${IMAGE_TEMP}/${x}.png)"
      fi
    fi

    if [ ${notupdate} -eq 0 ]
    then
      curl ${AUTH} -X GET -s -S -b zbx_sessionid=${SID} "${ZABBIX_GRAPH}?graphid=${x}&width=${GRAPH_WIDTH}&period=${GRAPH_PERIOD}&stime=${START_TIME}" > ${IMAGE_TEMP}/${x}.png
      logger -t ${SCRIPT} -p ${PRITEXT} "host=${HOST}, key=${KEY}, stat=Update, image=${IMAGE_TEMP}/${x}.png, size=$(stat --printf=%s ${IMAGE_TEMP}/${x}.png)"
    fi
    mopt=$(echo "${mopt} -a ${IMAGE_TEMP}/${x}.png")
  done

  echo $mopt
}

### result check
_result_check() {
  method=$1
  result=$2

  if [ "${result}" = "Error" ]
  then
    logger -t ${SCRIPT} -p ${PRITEXT} "host=${HOST}, key=${KEY}, method=${method}, stat=${result}"
  elif [ ${VERBOSE} -eq 1 ]
  then
    logger -t ${SCRIPT} -p ${PRITEXT} "host=${HOST}, key=${KEY}, method=${method}, id=\"${result}\""
  fi

}

### set arguments
RCPT="$1"
SUBJ="$2"
DATA=$(echo "$3" | tr -d '\r')

### get graph infomation
HOST=$(echo "${DATA}" | grep "^host:" | sed -r 's/host:\s?//')
KEY=$(echo "${DATA}" | grep "^key:" | sed -r 's/key:\s?//')

### check tempolary directory for e-mail.
if [ ! -d ${IMAGE_TEMP} ]
then
  mkdir ${IMAGE_TEMP}
  if [ $? -ne 0 ]
  then
    logger -t ${SCRIPT} -p ${PRITEXT} "host=${HOST}, key=${KEY}, stat=Error, error=\"Can't create ${IMAGE_TEMP}.\""
    exit 1
  fi
fi
export HOME=${IMAGE_TEMP}

### set email address
cat <<EOF > ${IMAGE_TEMP}/mutt.txt.$$
set from='${MAIL_FROM}'
set realname='${MAIL_NAME}'
set envelope_from=yes
set smtp_url='${SMTP_URL}'
EOF

### process count
PCNT=$(ps -C ${SCRIPT} -o cmd | grep -v ^CMD | sort | uniq | wc -l)

if [ ${PROCESS_LIMIT} -lt ${PCNT} ]
then
  result=$(echo "${DATA}" | mutt -s "${SUBJ}" -F ${IMAGE_TEMP}/mutt.txt.$$ "${RCPT}" 2>&1)
  if [ "${result}x" != "x" ]
  then
    logger -t ${SCRIPT} -p ${PRITEXT} "host=${HOST}, key=${KEY}, stat=Error, error=\"${result}\""
  fi
  logger -t ${SCRIPT} -p ${PRITEXT} "host=${HOST}, key=${KEY}, pcnt=${PCNT}, plimit=${PROCESS_LIMIT}"
  rm -f ${IMAGE_TEMP}/mutt.txt.$$
  exit 1
fi

### get sessionid
SID=$(_zabbix_api user.login)
_result_check user.login ${SID}

### get hostid
HOSTID=$(_zabbix_api host.get ${SID} hostid '"output":["hostid"]' "\"filter\":{\"host\":\"${HOST}\"}")
_result_check host.get ${HOSTID}

### get itemid
ITEMID=$(_zabbix_api item.get ${SID} itemid '"output":["itemid"]' "\"filter\":{\"hostid\":\"${HOSTID}\",\"key_\":\"${KEY}\"}")
_result_check item.get ${ITEMID}

### get graphids
GRAPHIDS=$(_zabbix_api graph.get ${SID} graphid "\"output\":\"graphid\",\"hostids\":\"${HOSTID}\",\"itemids\":\"${ITEMID}\"")
_result_check graph.get "${GRAPHIDS}"

### get graph images
sleep $((${PCNT}-1))

MOPT=""
if [ "${GRAPHIDS}" != "Error" ]
then
  START_TIME=$(date -d "${GRAPH_START}" +%s)

  if [ ${MODE} -eq 0 ]
  then
    MOPT=$(_get_graph_image "${GRAPHIDS}")
  elif [ ${MODE} -eq 1 ]
  then
    SNAME=""
    ### get screen
    for x in $(echo ${GRAPHIDS})
    do
      SCREENIDS=$(_zabbix_api screen.get ${SID} dummy '"selectScreenItems":"extend"' $x)
      _result_check screen.get "${SCREENIDS}"
      if [ "${SCREENIDS}" != "Error" ]
      then
        SNAME=$(echo ${SCREENIDS} | awk -F, '{print $1}')
        MOPT="${MOPT} $(_get_graph_image "$(echo ${SCREENIDS} | awk -F, '{print $2}')")"
      else
        MOPT="${MOPT} $(_get_graph_image ${x})"
      fi

      if [ "${SNAME}x" != "x" ]
      then
        DATA=$(echo -e "${DATA}\nscreen: ${SNAME}")
      fi

    done

  fi
fi

### send e-mail
if [ "${MOPT}x" != "x" ]
then
  result=$(echo "${DATA}" | mutt -s "${SUBJ}" -F ${IMAGE_TEMP}/mutt.txt.$$ "${RCPT}" ${MOPT} 2>&1)
else
  result=$(echo "${DATA}" | mutt -s "${SUBJ}" -F ${IMAGE_TEMP}/mutt.txt.$$ "${RCPT}" 2>&1)
fi

### write smtp error log
if [ "${result}x" != "x" ]
then
  logger -t ${SCRIPT} -p ${PRITEXT} "host=${HOST}, key=${KEY}, to=<${RCPT}>, stat=Error, error=\"${result}\""
else
  logger -t ${SCRIPT} -p ${PRITEXT} "host=${HOST}, key=${KEY}, to=<${RCPT}>, stat=Sent"
fi

###delete mutt.txt
rm -f ${IMAGE_TEMP}/mutt.txt.$$

### initialize sent
if [ -f "${HOME}/sent" ]
then
  cp -f /dev/null ${HOME}/sent
fi

exit 0
