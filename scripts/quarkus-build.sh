#!/usr/bin/env bash

set -euo pipefail

script_name="${BASH_SOURCE:-$0}"
script_path=$(realpath "${BASH_SOURCE[0]:-$0}")
scripts_dir_path=$(dirname "$script_path")

# shellcheck disable=SC1091
source "${scripts_dir_path}/lib/_functions.sh"

declare -A args
args["image"]=""
args["registry"]="quay.io"
args["project"]=""
args["name"]=""
args["tag"]=""
args["push"]=""
args["workflow-directory"]="$PWD"

function parse_args {
    while getopts ":i:n:r:p:t:w:h-:" opt; do
        case $opt in
            h) usage && exit ;;
            i) args["image"]="$OPTARG" ;;
            r) args["registry"]="$OPTARG" ;;
            p) args["project"]="$OPTARG" ;;
            n) args["name"]="$OPTARG" ;;
            t) args["tag"]="$OPTARG" ;;
            w) args["workflow-directory"]="$OPTARG" ;;
            -)
                case "${OPTARG}" in
                    help)
                        usage && exit ;;
                    push)
                        args["push"]="true" ;;
                    image=*)
                        args["image"]="${OPTARG#*=}" ;;
                    registry=*)
                        args["registry"]="${OPTARG#*=}" ;;
                    project=*)
                        args["project"]="${OPTARG#*=}" ;;
                    name=*)
                        args["name"]="${OPTARG#*=}" ;;
                    tag=*)
                        args["tag"]="${OPTARG#*=}" ;;
                    workflow-directory=*)
                        args["workflow-directory"]="${OPTARG#*=}" ;;
                    *) echo "Invalid option: --$OPTARG" >&2; exit 1 ;;
                esac
            ;;
            \?) echo "Invalid option: -$OPTARG" >&2; exit 2 ;;
            :) echo "Option -$OPTARG requires an argument." >&2; exit 3 ;;
        esac
    done

    if [[ -z "${args["image"]:-}" ]] && [[ -z "${args["project"]:-}" ]]; then
        echo "ERROR: Missing --project or --image flags."
        exit 4
    fi
}

function usage {
    cat <<EOF
Builds a Quarkus SonataFlow project in the current directory resulting in a container image.

Usage: 
    $script_name [flags]

Flags:
    -i|--image string           Full image name in the form of [registry]/[project]/[name]:[tag]
                                    Required when the registry, project, name and tag flags are not specified.
    -n|--name string            The image name
                                    Overrides the [name] part when the --image flag is specified
                                    Default: the workflow ID in the workflow file
                                    Example: 'fedora-42' as in 'quay.io/fedora/fedora-42'
    -p|--project string         The project name in the containers registry
                                    Overrides the [project] part when the --image flag is specified
                                    Example: 'fedora' as in 'quay.io/fedora'
                                    Default: 'latest' and the first 8 characters of the current git commit hash
    -r|--registry string        The containers registry to use
                                    Overrides the [registry] part when the --image flag is specified
                                    Example: 'quay.io'
    -t|--tag string             The image tag
    -w|--workflow-directory     Path to the directory containing the workflow's files (the 'src' directory).
                                    Default: current directory
       --push                   Pushes the image to the registry after building

Note: The project name or the image path must be specified using --project or --image flags correspondingly.
EOF
}

parse_args "$@"

workflow_id=$(get_workflow_id "${args["workflow-directory"]}/src/main/resources")
commit_sha=$(git rev-parse --short=8 HEAD)
image="${args["image"]:-${args["registry"]}/${args["project"]}/${args["name"]:-$workflow_id}:${args["tag"]:-$commit_sha}}"

pocker build \
    -f "${args["workflow-directory"]}/docker/orchestrator.Dockerfile" \
    --ulimit nofile=4096:4096 \
    --platform linux/amd64 \
    --tag "${image}" \
    "${args["workflow-directory"]}"

if [[ -n "${args["push"]}" ]]; then
    pocker push "${image}"
    if [[ ! "${args["image"]}" =~ latest$ ]]; then
        pocker tag "${image}" "${image}:latest"
        pocker push "${image}:latest"
    fi
fi