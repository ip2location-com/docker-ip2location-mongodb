FROM debian:bookworm-slim
LABEL maintainer="support@ip2location.com"

# Install packages
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get -qy install curl gnupg wget unzip ca-certificates \
	&& rm -rf /var/lib/apt/lists/*

# MongoDB setup. Note the repository is pinned to bookworm, so the base image
# must stay on bookworm -- MongoDB does not publish a trixie repository yet.
RUN curl -fsSL https://www.mongodb.org/static/pgp/server-8.0.asc | gpg -o /usr/share/keyrings/mongodb-server-8.0.gpg --dearmor
RUN echo "deb [arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-8.0.gpg] http://repo.mongodb.org/apt/debian bookworm/mongodb-org/8.0 main" | tee /etc/apt/sources.list.d/mongodb-org-8.0.list
RUN apt-get update \
	&& apt-get install -y mongodb-org \
	&& rm -rf /var/lib/apt/lists/*

# Add scripts
ADD app/main.sh /main.sh
ADD app/update.sh /update.sh
ADD app/entrypoint.sh /entrypoint.sh
RUN chmod 755 /*.sh

# Without this the database is stored in the container's writable layer and is
# lost the moment the container is removed.
VOLUME ["/data/db"]

EXPOSE 27017

# ENTRYPOINT (not CMD) so that arguments are honoured: `docker run image mongosh ...`
# must reach the client instead of being discarded in favour of the setup script.
ENTRYPOINT ["/entrypoint.sh"]
