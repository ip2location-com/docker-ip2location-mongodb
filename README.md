docker-ip2location-mongodb
==========================

A ready-to-run MongoDB server preloaded with an [IP2Location](https://www.ip2location.com) geolocation database. Supports the commercial packages and the free [LITE](https://lite.ip2location.com) package. Register for an account first as download token is required.



## Usage

```bash
docker network create ip2location-network

docker run --name ip2location \
  --network ip2location-network \
  -d \
  -e TOKEN={DOWNLOAD_TOKEN} \
  -e CODE={DOWNLOAD_CODE} \
  -e IP_TYPE=IPV4 \
  -e MONGODB_PASSWORD={MONGODB_PASSWORD} \
  ip2location/mongodb

docker logs -f ip2location      # Wait for "✓ Setup completed"
```

**ENV Variables**

| Variable | Description |
|---|---|
| `TOKEN` | Download token. Required. |
| `CODE` | Database code. Required. See below. |
| `IP_TYPE` | `IPV4` (default) or `IPV6`. |
| `MONGODB_PASSWORD` | Password for the `mongoAdmin` user. Random if omitted. |

**`CODE`** — LITE: `DB1-LITE`, `DB3-LITE`, `DB5-LITE`, `DB9-LITE`, `DB11-LITE`.
Commercial: `DB1` … `DB26`.

Only one address family is installed per container. To switch, start a fresh container with an empty `/data/db` — an existing install is not converted in place, and re-running with different settings prints a note explaining that.

The admin password is written to `/config` inside the container, so `docker logs` and `docker exec` access are equivalent to knowing it.

To start over:

```bash
docker rm -f ip2location
docker volume rm ip2location-data        # if you used -v ip2location-data:/data/db
```



## Query for IP Information

Two fields are stored: `ip_to` is the IP **number** and `ip_to_index` is the same number zero-padded to 40 characters and prefixed with `A`, which is what makes range comparison work as a string. Which one you filter on depends on the `IP_TYPE` you installed.

**IPv4** — the IP number as a plain string:

```js
use ip2location_database
db.ip2location_database.findOne( { ip_to: { $gte: "134744072" } } )
```

```
{ ip_to: "134874623", country_code: "US", country_name: "United States of America", ... }
```

**IPv6** — the padded, `A`-prefixed form. For `2001:4860:4860::8888` the IP number is `42541956123769884636017138956568135816`:

```js
use ip2location_database
db.ip2location_database.findOne( { ip_to_index: { $gte: "A0042541956123769884636017138956568135816" } } )
```

**Both search values are quoted strings.** `mongoimport --type csv` imports every CSV value as text unless the field types are declared, so the unquoted form `{ ip_to: { $gte: 134744072 } }` matches **nothing** and returns `null` — BSON compares across types by type order, and numbers sort before strings.

To convert an address to an IP number see the [IP2Location FAQs](https://www.ip2location.com/faqs#technical).

To store the numbers as `int64` instead of strings, declare the types at import time with `--columnsHaveTypes` and `int64(...)`; `--columnsHaveTypes` is only accepted together with `--fields`.



## Connect from an Application

Put your application on the same network and reach the container by name (`ip2location`):

```bash
docker run --network ip2location-network -t -i {YOUR_APPLICATION}
```

```bash
mongosh --host ip2location -u mongoAdmin -p {MONGODB_PASSWORD} --authenticationDatabase admin
```



## Update IP2Location Database

```bash
docker exec -it ip2location /update.sh
```

Imports a fresh copy and swaps it in with `renameCollection(..., true)`, so queries keep working against the old data until the swap. The daily download quota is limited. If you get `[QUOTA EXCEEDED]` error, please try again after 24 hours.



## Articles and Tutorials

[IP2Location Articles and Tutorials](https://blog.ip2location.com)
