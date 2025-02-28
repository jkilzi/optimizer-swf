#!/usr/bin/env bash

set -eu

script_name="${BASH_SOURCE:-$0}"
script_path=$(realpath "$script_name")
scripts_dir_path=$(dirname "$script_path")

# shellcheck disable=SC1091
source "${scripts_dir_path}/lib/_functions.sh"

function usage {
    cat <<EOF
Usage: $script_name <PROJECT_NAME> [<WORKFLOW_DIRECTORY>]
EOF
}

if [[ "${1:-}" =~ -?-h(elp)? ]]; then
    usage
    exit 0
fi

project=$1
workflow_dir_path=${2:-"$PWD"}
if [[ -z "$project" ]]; then
    usage
    exit 1
fi

workflow_id=$(get_workflow_id "$workflow_dir_path/src/main/resources")
image="quay.io/$project/$workflow_id:latest"

"$scripts_dir_path"/quarkus-build.sh --workflow-directory="$workflow_dir_path" --image="$image" --push
"$scripts_dir_path"/gen-manifest.sh --workflow-directory="$workflow_dir_path" --image="$image" --apply
