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
	if [ $((${#1} + 1)) -le "$STEP_WIDTH" ]; then
		printf '%s ' "$1"
		printf '%s%s%s ' "$C_DIM" "$(printf '·%.0s' $(seq 1 $((STEP_WIDTH - ${#1}))))" "$C_RESET"
	else
		printf '%s\n     ' "$1"
	fi
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

# run a command quietly: its output is shown only if it fails. mongod, mongosh
# and mongoimport all write banners and progress bars to stdout, which would
# otherwise land in the middle of the step lines.
quiet_run() {
	local out rc
	out="$("$@" 2>&1)"
	rc=$?
	if [ $rc -ne 0 ]; then
		# mongoimport redraws a progress bar using carriage returns; collapse
		# them so the real failure is what shows in the log.
		printf '%s\n' "$out" | tr '\r' '\n' | grep -v '^[[:space:]]*$' | tail -n 15
	fi
	return $rc
}

# seconds since $1, for "took 42s" style detail
elapsed() { echo "$(( $(date +%s) - $1 ))s"; }

USER_AGENT="Mozilla/5.0+(compatible; IP2Location/MongoDB-Docker; https://hub.docker.com/r/ip2location/mongodb)"
CODES=(DB1-LITE DB3-LITE DB5-LITE DB9-LITE DB11-LITE DB1 DB2 DB3 DB4 DB5 DB6 DB7 DB8 DB9 DB10 DB11 DB12 DB13 DB14 DB15 DB16 DB17 DB18 DB19 DB20 DB21 DB22 DB23 DB24 DB25 DB26)

trim() { local v="${1//$'\r'/}"; v="${v#"${v%%[![:space:]]*}"}"; v="${v%"${v##*[![:space:]]}"}"; printf '%s' "$v"; }

TOKEN="$(trim "$TOKEN")"
CODE="$(trim "$CODE")"
IP_TYPE="$(trim "$IP_TYPE")"
CODE_INPUT="$CODE"

if [ -f /config ]; then
	CONF_TOKEN="$(grep '^TOKEN=' /config | cut -d= -f2-)"
	CONF_CODE="$(grep '^CODE=' /config | cut -d= -f2-)"
	CONF_IP_TYPE="$(grep '^IP_TYPE=' /config | cut -d= -f2-)"
	CONF_PASSWORD="$(grep '^MONGODB_PASSWORD=' /config | cut -d= -f2-)"

	if [ -n "$CODE_INPUT" ] && [ "$CODE_INPUT" != "$CONF_CODE" ]; then
		echo " > NOTE: CODE has changed from '$CONF_CODE' to '$CODE_INPUT', but the database"
		echo " >       is already installed. The existing data is kept. To install"
		echo " >       '$CODE_INPUT' instead, start a fresh container with an empty /data/db."
	fi
	if [ -n "$TOKEN" ] && [ "$TOKEN" != "$CONF_TOKEN" ]; then
		echo " > NOTE: TOKEN has changed but is not re-applied to an existing install."
	fi
	if [ -n "$IP_TYPE" ] && [ "$IP_TYPE" != "$CONF_IP_TYPE" ]; then
		echo " > NOTE: IP_TYPE has changed from '$CONF_IP_TYPE' to '$IP_TYPE', but the"
		echo " >       database is already installed and is not converted in place."
		echo " >       To install '$IP_TYPE', start a fresh container with an empty /data/db."
	fi
	if [ -n "$MONGODB_PASSWORD" ] && [ "$MONGODB_PASSWORD" != "$CONF_PASSWORD" ]; then
		echo " > NOTE: MONGODB_PASSWORD has changed but the existing admin password is kept."
		echo " >       Change it with: db.changeUserPassword('mongoAdmin', '...')"
	fi

	quiet_run mongod --quiet --fork --logpath /var/log/mongodb/mongod.log --auth --bind_ip_all
	tail -f /dev/null
fi

[ -z "$TOKEN" ] && fail "Missing download token. Pass it with -e TOKEN=..."
[ -z "$CODE" ] && fail "Missing database code. Pass it with -e CODE=... (e.g. DB1-LITE)"

if [ -z "$MONGODB_PASSWORD" ]; then
	MONGODB_PASSWORD="$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c${1:-12})"
fi

# Exported so the mongosh calls below can read it via process.env. Interpolating
# it into the --eval source instead would store the literal text "$MONGODB_PASSWORD"
# as the password: bash does not expand inside single quotes and JavaScript does
# not expand inside double quotes.
export MONGODB_PASSWORD

FOUND=""
for i in "${CODES[@]}"; do
	if [ "$i" == "$CODE" ] ; then
		FOUND="$CODE"
	fi
done

if [ -z "$FOUND" ]; then
	fail "Download code '$CODE' is invalid. See the README for the list of supported codes."
fi

if [ "$IP_TYPE" == "IPV6" ]; then
	IP_TYPE="IPV6"
	SUFFIX="CSVIPV6"
	CODE_SUFFIX="IPV6"
else
	[ -n "$IP_TYPE" ] && [ "$IP_TYPE" != "IPV4" ] && echo " > IP_TYPE '$IP_TYPE' is not recognised, using IPV4."
	IP_TYPE="IPV4"
	SUFFIX="CSV"
	CODE_SUFFIX=""
fi

CASE_CODE="$(echo $CODE | sed 's/-//')${CODE_SUFFIX}"

banner "IP2Location Database Setup"
field "Database" "ip2location_database"
field "Code" "$CODE_INPUT"
field "IP type" "$IP_TYPE"

rm -rf /_tmp && mkdir /_tmp && cd /_tmp

echo ""
T0=$(date +%s)
step "Download IP2Location $IP_TYPE database"

ARCHIVE="/_tmp/database.zip"
wget -qO "$ARCHIVE" --user-agent="$USER_AGENT" "https://www.ip2location.com/download?token=${TOKEN}&code=$(echo $CODE | sed 's/-//')${SUFFIX}" > /dev/null 2>&1

[ ! -z "$(grep 'NO PERMISSION' "$ARCHIVE")" ] && fail "DENIED"
[ ! -z "$(grep '5 TIMES' "$ARCHIVE")" ] && fail "QUOTA EXCEEDED"

unzip -t "$ARCHIVE" >/dev/null 2>&1

[ $? -ne 0 ] && fail "FILE CORRUPTED"

ok "$(( $(stat -c%s "$ARCHIVE") / 1048576 )) MB"

CSV=$(unzip -l "$ARCHIVE" | sort -nr | grep -Eio 'IP(V6)?.*CSV' | head -n 1)

T1=$(date +%s)
step "Decompress the downloaded archive"

unzip -oq "$ARCHIVE" "$CSV"

if [ ! -f "/_tmp/$CSV" ]; then
	fail "ERROR"
fi

ok "$(elapsed $T1)"

step "Create data directory"
mkdir -p /data/db

[ $? -ne 0 ] && fail "ERROR" || ok

step "Start daemon"
quiet_run mongod --quiet --fork --logpath /var/log/mongodb/mongod.log --bind_ip_all

[ $? -ne 0 ] && fail "ERROR" || ok

step "Create admin user"
quiet_run mongosh --eval 'const a = db.getSiblingDB("admin"), p = process.env.MONGODB_PASSWORD; if (a.getUser("mongoAdmin")) { a.changeUserPassword("mongoAdmin", p); } else { a.createUser({user: "mongoAdmin", pwd: p, roles: ["root"]}); }'

[ $? -ne 0 ] &&  fail "ERROR"

USERS="$(mongosh --quiet --eval 'db.getSiblingDB("admin").system.users.countDocuments({user: "mongoAdmin"})' 2>/dev/null | tr -dc '0-9')"

[ "$USERS" == "1" ] || fail "admin user was not created"

ok

step "Shut down daemon"
quiet_run mongod --shutdown
[ $? -ne 0 ] && fail "ERROR" || ok

step "Start daemon with authentication"
quiet_run mongod --quiet --fork --logpath /var/log/mongodb/mongod.log --auth --bind_ip_all

[ $? -ne 0 ] &&  fail "ERROR" || ok

step "Verify admin credentials"

# Poll rather than sleeping a fixed amount: the daemon needs a moment after the
# authenticated restart, and a false failure here would be worse than a retry.
AUTH=""
for i in $(seq 1 30); do
	AUTH="$(mongosh -u mongoAdmin -p "$MONGODB_PASSWORD" --authenticationDatabase admin --quiet \
		--eval 'db.getSiblingDB("admin").system.users.countDocuments()' 2>&1)"
	[ "$(echo "$AUTH" | tr -dc '0-9')" == "1" ] && break
	sleep 1
done

case "$(echo "$AUTH" | tr -dc '0-9')" in
	1) ok ;;
	*) fail "mongoAdmin cannot authenticate: $(echo "$AUTH" | tr '\n' ' ')" ;;
esac

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

	[ $? -ne 0 ] &&  fail "ERROR" || ok

	T2=$(date +%s)
	step "Import the CSV into a new collection"
	quiet_run mongoimport -u mongoAdmin -p "$MONGODB_PASSWORD" --authenticationDatabase admin --drop --db ip2location_database --collection ip2location_database_tmp --type csv --file "./INDEXED.CSV" --fields ip_to_index,ip_from,ip_to,country_code,country_name$FIELDS

	[ $? -ne 0 ] &&  fail "ERROR" || ok "$(elapsed $T2)"

	step "Create index"
	quiet_run mongosh -u mongoAdmin -p "$MONGODB_PASSWORD" --authenticationDatabase admin --quiet --eval 'db.getSiblingDB("ip2location_database").ip2location_database_tmp.createIndex({ip_to_index: 1})'

	[ $? -ne 0 ] &&  fail "ERROR" || ok
else
	T2=$(date +%s)
	step "Import the CSV into a new collection"
	quiet_run mongoimport -u mongoAdmin -p "$MONGODB_PASSWORD" --authenticationDatabase admin --drop --db ip2location_database --collection ip2location_database_tmp --type csv --file "$CSV" --fields ip_from,ip_to,country_code,country_name$FIELDS

	[ $? -ne 0 ] &&  fail "ERROR" || ok "$(elapsed $T2)"

	step "Create index"
	quiet_run mongosh -u mongoAdmin -p "$MONGODB_PASSWORD" --authenticationDatabase admin --quiet --eval 'db.getSiblingDB("ip2location_database").ip2location_database_tmp.createIndex({ip_to: 1})'
	[ $? -ne 0 ] &&  fail "ERROR" || ok
fi

step "Activate ip2location_database"
quiet_run mongosh -u mongoAdmin -p "$MONGODB_PASSWORD" --authenticationDatabase admin --quiet --eval 'db.getSiblingDB("ip2location_database").ip2location_database_tmp.renameCollection("ip2location_database", true)'

[ $? -ne 0 ] &&  fail "ERROR" || ok

banner "IP2Location Database Ready"
ROWS="$(mongosh -u mongoAdmin -p "$MONGODB_PASSWORD" --authenticationDatabase admin --quiet --eval 'db.getSiblingDB("ip2location_database").ip2location_database.countDocuments({})' 2>/dev/null | tr -dc '0-9')"
summary "Setup completed" "$(group "$ROWS") documents imported from $CODE_INPUT ($IP_TYPE)"
field "Host" "ip2location"
field "Database" "ip2location_database"
field "User" "mongoAdmin"
field "Password" "$MONGODB_PASSWORD"
printf '\n  %smongosh -h ip2location -u mongoAdmin -p "%s" --authenticationDatabase admin%s\n' "$C_DIM" "$MONGODB_PASSWORD" "$C_RESET"
printf '\n'

echo "MONGODB_PASSWORD=$MONGODB_PASSWORD" > /config
echo "TOKEN=$TOKEN" >> /config
echo "CODE=$CODE_INPUT" >> /config
echo "IP_TYPE=$IP_TYPE" >> /config

rm -rf /_tmp

tail -f /dev/null
