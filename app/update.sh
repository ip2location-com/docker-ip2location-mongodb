#!/bin/bash

if [ -n "$NO_COLOR" ]; then
	C_RESET=; C_DIM=; C_BOLD=; C_OK=; C_WARN=; C_ERR=
else
	C_RESET=$'\e[0m'; C_DIM=$'\e[2m'; C_BOLD=$'\e[1m'
	C_OK=$'\e[32m'; C_WARN=$'\e[33m'; C_ERR=$'\e[31m'
fi

STEP_N=0
STEP_WIDTH=58

banner() {
	printf '\n%s  %s%s\n%s  %s%s\n\n' \
		"$C_BOLD" "$1" "$C_RESET" \
		"$C_DIM" "$(printf '─%.0s' $(seq 1 $((${#1} + 2))))" "$C_RESET"
}

step() {
	STEP_N=$((STEP_N + 1))
	printf '  %s%2d.%s ' "$C_DIM" "$STEP_N" "$C_RESET"
	local label="$1"
	[ ${#label} -gt "$STEP_WIDTH" ] && label="${label:0:$((STEP_WIDTH - 3))}..."
	local pad=$((STEP_WIDTH - ${#label})) dots=""
	[ $pad -gt 0 ] && dots="$(printf '·%.0s' $(seq 1 $pad))"

	printf '%s %s%s%s ' "$label" "$C_DIM" "$dots" "$C_RESET"
	printf '%s' "$C_DIM"
}
ok()   { if [ -n "$1" ]; then printf '%s✓%s %s(%s)%s\n' "$C_OK" "$C_RESET" "$C_DIM" "$1" "$C_RESET"; else printf '%s✓%s\n' "$C_OK" "$C_RESET"; fi; }
warn() { printf '%s!%s %s%s%s\n' "$C_WARN" "$C_RESET" "$C_DIM" "$1" "$C_RESET"; }
fail() { printf '%s✗%s %s\n' "$C_ERR" "$C_RESET" "$1"; exit 1; }
note()  { printf '     %s%s%s\n' "$C_DIM" "$1" "$C_RESET"; }
field() { printf '  %s%-9s%s %s\n' "$C_DIM" "$1" "$C_RESET" "$2"; }

group() {
	local n="$1" out=""
	while [ ${#n} -gt 3 ]; do
		out=",${n: -3}${out}"
		n="${n:0:${#n}-3}"
	done
	printf '%s%s' "$n" "$out"
}

summary() {
	printf '\n  %s✓%s %s%s%s\n' "$C_OK" "$C_RESET" "$C_BOLD$C_OK" "$1" "$C_RESET"
	[ -n "$2" ] && printf '    %s%s%s\n' "$C_DIM" "$2" "$C_RESET"
	printf '\n'
}

quiet_run() {
	local out rc
	out="$("$@" 2>&1)"
	rc=$?
	if [ $rc -ne 0 ]; then
		printf '%s\n' "$out" | tr '\r' '\n' | grep -v '^[[:space:]]*$' | tail -n 15
	fi
	return $rc
}

elapsed() { echo "$(( $(date +%s) - $1 ))s"; }

[ ! -f /config ] && fail "Missing configuration file."

banner "IP2Location Database Update"

USER_AGENT="Mozilla/5.0+(compatible; IP2Location/MongoDB-Docker; https://hub.docker.com/r/ip2location/mongodb)"
TOKEN=$(grep '^TOKEN=' /config | cut -d= -f2-)
CODE=$(grep '^CODE=' /config | cut -d= -f2-)
CODE_INPUT="$CODE"
IP_TYPE=$(grep '^IP_TYPE=' /config | cut -d= -f2-)
MONGODB_PASSWORD=$(grep '^MONGODB_PASSWORD=' /config | cut -d= -f2-)

if [ "$IP_TYPE" == "IPV6" ]; then
	IP_TYPE="IPV6"
	SUFFIX="CSVIPV6"
	CODE_SUFFIX="IPV6"
else
	IP_TYPE="IPV4"
	SUFFIX="CSV"
	CODE_SUFFIX=""
fi

CASE_CODE="$(echo $CODE | sed 's/-//')${CODE_SUFFIX}"

rm -rf /_tmp && mkdir /_tmp && cd /_tmp

step "Download IP2Location $IP_TYPE database"

ARCHIVE="/_tmp/database.zip"
wget -qO "$ARCHIVE" --user-agent="$USER_AGENT" "https://www.ip2location.com/download?token=${TOKEN}&code=$(echo $CODE | sed 's/-//')${SUFFIX}" > /dev/null 2>&1

[ ! -z "$(grep 'NO PERMISSION' "$ARCHIVE")" ] && fail "DENIED"
[ ! -z "$(grep '5 TIMES' "$ARCHIVE")" ] && fail "QUOTA EXCEEDED"

unzip -t "$ARCHIVE" >/dev/null 2>&1

[ $? -ne 0 ] && fail "FILE CORRUPTED"

ok

CSV=$(unzip -l "$ARCHIVE" | sort -nr | grep -Eio 'IP(V6)?.*CSV' | head -n 1)

step "Decompress the downloaded archive"

unzip -oq "$ARCHIVE" "$CSV"

if [ ! -f "/_tmp/$CSV" ]; then
	fail "ERROR"
fi

ok

case "$CASE_CODE" in
	DB1|DB1LITE|DB1IPV6|DB1LITEIPV6 )
		FIELDS=''
	;;

	DB2|DB2IPV6 )
		FIELDS=',isp'
	;;

	DB3|DB3LITE|DB3IPV6|DB3LITEIPV6 )
		FIELDS=',region_name,city_name'
	;;

	DB4|DB4IPV6 )
		FIELDS=',region_name,city_name,isp'
	;;

	DB5|DB5LITE|DB5IPV6|DB5LITEIPV6 )
		FIELDS=',region_name,city_name,latitude,longitude'
	;;

	DB6|DB6IPV6 )
		FIELDS=',region_name,city_name,latitude,longitude,isp'
	;;

	DB7|DB7IPV6 )
		FIELDS=',region_name,city_name,isp,domain'
	;;

	DB8|DB8IPV6 )
		FIELDS=',region_name,city_name,latitude,longitude,isp,domain'
	;;

	DB9|DB9LITE|DB9IPV6|DB9LITEIPV6 )
		FIELDS=',region_name,city_name,latitude,longitude,zip_code'
	;;

	DB10|DB10IPV6 )
		FIELDS=',region_name,city_name,latitude,longitude,zip_code,isp,domain'
	;;

	DB11|DB11LITE|DB11IPV6|DB11LITEIPV6 )
		FIELDS=',region_name,city_name,latitude,longitude,zip_code,time_zone'
	;;

	DB12|DB12IPV6 )
		FIELDS=',region_name,city_name,latitude,longitude,zip_code,time_zone,isp,domain'
	;;

	DB13|DB13IPV6 )
		FIELDS=',region_name,city_name,latitude,longitude,time_zone,net_speed'
	;;

	DB14|DB14IPV6 )
		FIELDS=',region_name,city_name,latitude,longitude,zip_code,time_zone,isp,domain,net_speed'
	;;

	DB15|DB15IPV6 )
		FIELDS=',region_name,city_name,latitude,longitude,zip_code,time_zone,idd_code,area_code'
	;;

	DB16|DB16IPV6 )
		FIELDS=',region_name,city_name,latitude,longitude,zip_code,time_zone,isp,domain,net_speed,idd_code,area_code'
	;;

	DB17|DB17IPV6 )
		FIELDS=',region_name,city_name,latitude,longitude,time_zone,net_speed,weather_station_code,weather_station_name'
	;;

	DB18|DB18IPV6 )
		FIELDS=',region_name,city_name,latitude,longitude,zip_code,time_zone,isp,domain,net_speed,idd_code,area_code,weather_station_code,weather_station_name'
	;;

	DB19|DB19IPV6 )
		FIELDS=',region_name,city_name,latitude,longitude,isp,domain,mcc,mnc,mobile_brand'
	;;

	DB20|DB20IPV6 )
		FIELDS=',region_name,city_name,latitude,longitude,zip_code,time_zone,isp,domain,net_speed,idd_code,area_code,weather_station_code,weather_station_name,mcc,mnc,mobile_brand'
	;;

	DB21|DB21IPV6 )
		FIELDS=',region_name,city_name,latitude,longitude,zip_code,time_zone,idd_code,area_code,elevation'
	;;

	DB22|DB22IPV6 )
		FIELDS=',region_name,city_name,latitude,longitude,zip_code,time_zone,isp,domain,net_speed,idd_code,area_code,weather_station_code,weather_station_name,mcc,mnc,mobile_brand,elevation'
	;;

	DB23|DB23IPV6 )
		FIELDS=',region_name,city_name,latitude,longitude,isp,domain,mcc,mnc,mobile_brand,usage_type'
	;;

	DB24|DB24IPV6 )
		FIELDS=',region_name,city_name,latitude,longitude,zip_code,time_zone,isp,domain,net_speed,idd_code,area_code,weather_station_code,weather_station_name,mcc,mnc,mobile_brand,elevation,usage_type'
	;;

	DB25|DB25IPV6 )
		FIELDS=',region_name,city_name,latitude,longitude,zip_code,time_zone,isp,domain,net_speed,idd_code,area_code,weather_station_code,weather_station_name,mcc,mnc,mobile_brand,elevation,usage_type,address_type,category'
	;;

	DB26|DB26IPV6 )
		FIELDS=',region_name,city_name,latitude,longitude,zip_code,time_zone,isp,domain,net_speed,idd_code,area_code,weather_station_code,weather_station_name,mcc,mnc,mobile_brand,elevation,usage_type,address_type,category,district,asn,as,as_domain,as_usage_type,as_cidr'
	;;
esac

if [ "$IP_TYPE" == "IPV6" ]; then
	step "Create index field"
	cat "$CSV" | awk 'BEGIN { FS="\",\""; } { s = "0000000000000000000000000000000000000000"$2; print "\"A"substr(s, 1 + length(s) - 40)"\","$0; }' > ./INDEXED.CSV

	[ $? -ne 0 ] && fail "ERROR" || ok

	T1=$(date +%s)
	step "Import the CSV into a new collection"
	quiet_run mongoimport -u mongoAdmin -p "$MONGODB_PASSWORD" --authenticationDatabase admin --drop --db ip2location_database --collection ip2location_database_tmp --type csv --file "./INDEXED.CSV" --fields ip_to_index,ip_from,ip_to,country_code,country_name$FIELDS

	[ $? -ne 0 ] && fail "ERROR" || ok "$(elapsed $T1)"

	step "Create index"
	quiet_run mongosh -u mongoAdmin -p "$MONGODB_PASSWORD" --authenticationDatabase admin --quiet --eval 'db.getSiblingDB("ip2location_database").ip2location_database_tmp.createIndex({ip_to_index: 1})'

	[ $? -ne 0 ] && fail "ERROR" || ok
else
	T1=$(date +%s)
	step "Import the CSV into a new collection"
	quiet_run mongoimport -u mongoAdmin -p "$MONGODB_PASSWORD" --authenticationDatabase admin --drop --db ip2location_database --collection ip2location_database_tmp --type csv --file "$CSV" --fields ip_from,ip_to,country_code,country_name$FIELDS

	[ $? -ne 0 ] && fail "ERROR" || ok "$(elapsed $T1)"

	step "Create index"
	quiet_run mongosh -u mongoAdmin -p "$MONGODB_PASSWORD" --authenticationDatabase admin --quiet --eval 'db.getSiblingDB("ip2location_database").ip2location_database_tmp.createIndex({ip_to: 1})'

	[ $? -ne 0 ] && fail "ERROR" || ok
fi

step "Activate ip2location_database"
quiet_run mongosh -u mongoAdmin -p "$MONGODB_PASSWORD" --authenticationDatabase admin --quiet --eval 'db.getSiblingDB("ip2location_database").ip2location_database_tmp.renameCollection("ip2location_database", true)'

[ $? -ne 0 ] && fail "ERROR" || ok

rm -rf /_tmp

summary "Update completed" "$CODE_INPUT ($IP_TYPE) refreshed"
field "Database" "ip2location_database"
note "The previous data was dropped only after the new table finished loading."
printf '\n'
