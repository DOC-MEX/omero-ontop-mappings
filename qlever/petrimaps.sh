#!/usr/bin/env bash
set -euo pipefail

CONTAINER_NAME="qlever-petrimaps"
IMAGE="adfreiburg/qlever-petrimaps:latest"

HOST_PORT="${HOST_PORT:-9100}"
CONTAINER_PORT="9090"

# Deployment mode:
#
#   linux (default)
#       Standard deployment for Linux servers.
#
#   mac
#       Docker Desktop on macOS. Adds the qlever-host alias so
#       Petrimaps can reach the QLever backend running on the host.
#
PETRIMAPS_MODE="${PETRIMAPS_MODE:-linux}"

ACTION="${1:-start}"

start_container() {
    docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true

    case "$PETRIMAPS_MODE" in

        linux)

            docker run -d \
                --name "$CONTAINER_NAME" \
                -p "${HOST_PORT}:${CONTAINER_PORT}" \
                --restart unless-stopped \
                "$IMAGE"

            echo " Petrimaps started"            
            echo "   URL  : http://localhost:${HOST_PORT}"
            echo
            echo "QLever UI configuration:"
            echo "   baseUrl:        http://localhost:8888"
            echo "   mapViewBaseURL: http://localhost:${HOST_PORT}"
            ;;

        mac)

            docker run -d \
                --name "$CONTAINER_NAME" \
                --add-host=qlever-host:host-gateway \
                -p "${HOST_PORT}:${CONTAINER_PORT}" \
                --restart unless-stopped \
                "$IMAGE"

            echo " Petrimaps started"
            echo "   Mode : macOS"
            echo "   URL  : http://localhost:${HOST_PORT}"
            echo
            echo "Reminder:"
            echo "   /etc/hosts should contain:"
            echo "      127.0.0.1 qlever-host"
            echo
            echo "QLever UI configuration:"
            echo "   baseUrl:        http://qlever-host:8888"
            echo "   mapViewBaseURL: http://localhost:${HOST_PORT}"
            ;;

        *)

            echo "Unknown PETRIMAPS_MODE: $PETRIMAPS_MODE"
            echo "Supported modes: linux, mac"
            exit 1

            ;;

    esac
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
        echo "  PETRIMAPS_MODE=mac ./petrimaps.sh"
        exit 1
        ;;

esac
