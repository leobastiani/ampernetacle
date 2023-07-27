#!/bin/bash

cd "$(dirname "$0")"

set -euo pipefail
IFS=$'\n\t'

get_ip() {
  terraform output -json ips | jq -r ".[$1]"
}

ssh -o UserKnownHostsFile=known_hosts "ubuntu@$(get_ip "$1")" "${@:2}"
