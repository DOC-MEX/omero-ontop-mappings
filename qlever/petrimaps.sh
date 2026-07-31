#!/usr/bin/env bash
set -euo pipefail

CONTAINER_NAME="qlever-petrimaps"
IMAGE="adfreiburg/qlever-petrimaps:latest"

HOST_PORT="${HOST_PORT:-9100}"
CONTAINER_PORT="9090"

###############################################################################
# Petrimaps deployment
#
# Default QLever UI deployments normally use, when running locally:
#
#   baseUrl: http://localhost:8888
#
# This is fine for qlever-ui itself. However, Petrimaps runs in Docker.
# If Petrimaps receives:
#
#   backend=http://localhost:8888
#
# then "localhost" means the Petrimaps container, not the host machine.
#
# Therefore, for local Petrimaps testing  (macOS or Linux) use a host alias
# such as `qlever-host`.
#
# Local Petrimaps setup:
#
#   1. Add on the host:
#        127.0.0.1 qlever-host
#         (echo "127.0.0.1 qlever-host" | sudo tee -a /etc/hosts)
#
#   2. Start Petrimaps with:
#        PETRIMAPS_HOST_ALIAS=qlever-host ./petrimaps.sh restart
#
#   3. Change Qleverfile-ui.yml from:
#        baseUrl: http://localhost:8888
#
#      to:
#        baseUrl: http://qlever-host:8888
#
#      The map URL can stay:
#        mapViewBaseURL: http://localhost:9100
#
# Live server setup:
#
#   Use the public/proxied backend URL in Qleverfile-ui.yml, for example:
#
#        baseUrl:        https://YOUR_SERVER/qlever
#        mapViewBaseURL: https://YOUR_SERVER/petrimaps
#
#   Then proxy /petrimaps/ to localhost:9100.
#
#   If the backend hostname is not reachable from inside Docker, start with:
#
#        PETRIMAPS_HOST_ALIAS=YOUR_HOSTNAME ./petrimaps.sh restart
###############################################################################

PETRIMAPS_HOST_ALIAS="${PETRIMAPS_HOST_ALIAS:-}"
ACTION="${1:-start}"

docker_host_alias_arg() {
    if [[ -n "$PETRIMAPS_HOST_ALIAS" ]]; then
        echo "--add-host=${PETRIMAPS_HOST_ALIAS}:host-gateway"
    fi
}

start_container() {
    docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true

    docker run -d \
        --name "$CONTAINER_NAME" \
        $(docker_host_alias_arg) \
        -p "${HOST_PORT}:${CONTAINER_PORT}" \
        --restart unless-stopped \
        "$IMAGE"

    echo " Petrimaps started"
    echo "   URL: http://localhost:${HOST_PORT}"

    if [[ -n "$PETRIMAPS_HOST_ALIAS" ]]; then
        echo "   Host alias: ${PETRIMAPS_HOST_ALIAS} -> host-gateway"
    fi

    echo
    echo "Note:"
    echo "   If Qleverfile-ui.yml uses baseUrl: http://localhost:8888,"
    echo "   qlever-ui will work, but Petrimaps may fail because localhost"
    echo "   inside the Petrimaps container is not the host machine."
    echo
    echo " Qleverfile-ui.yml configuration examples:"
    echo
    echo "   Default qlever-ui only, no Petrimaps:"
    echo "     baseUrl:        http://localhost:8888"
    echo
    echo "   Local development with Petrimaps:"
    echo "     baseUrl:        http://qlever-host:8888"
    echo "     mapViewBaseURL: http://localhost:${HOST_PORT}"
    echo
    echo "   Live server with public/proxied backend:"
    echo "     baseUrl:        http(s)://YOUR_SERVER/YOUR_BACKEND_ENDPOINT"
    echo "     mapViewBaseURL: http(s)://YOUR_SERVER/petrimaps"
    echo
}

case "$ACTION" in
    start)
        echo " Starting Petrimaps..."
        start_container
        ;;

    stop)
        echo " Stopping Petrimaps..."
        docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
        echo " Petrimaps stopped."
        ;;

    restart)
        echo " Restarting Petrimaps..."
        docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
        start_container
        ;;

    status)
        docker ps --filter "name=$CONTAINER_NAME"
        ;;

    *)
        echo "Usage: $0 {start|stop|restart|status}"
        echo
        echo "Examples:"
        echo "  ./petrimaps.sh"
        echo "  ./petrimaps.sh restart"
        echo "  PETRIMAPS_HOST_ALIAS=qlever-host ./petrimaps.sh restart"
        echo "  PETRIMAPS_HOST_ALIAS=micropop-virtuoso ./petrimaps.sh restart"
        exit 1
        ;;
esac