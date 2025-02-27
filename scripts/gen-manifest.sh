#!/usr/bin/env bash

set -euo pipefail

script_name="${BASH_SOURCE:-$0}"
script_path=$(realpath "$script_name")
scripts_dir_path=$(dirname "$script_path")
workspace_dir_path=$(dirname "$scripts_dir_path")

declare -A args
args["registry"]="quay.io"
args["organization"]=""
args["name"]=""
args["tag"]="latest"
args["no-persistence"]=""
args["no-cleanup"]=""

function parse_args {
    while getopts ":r:o:n:t:hPC-:" opt; do
        case $opt in
            h) usage && exit ;;
            P) args["no-persistence"]="true" ;;
            C) args["no-cleanup"]="true" ;;
            r) args["registry"]="$OPTARG" ;;
            o) args["organization"]="$OPTARG" ;;
            n) args["name"]="$OPTARG" ;;
            t) args["tag"]="$OPTARG" ;;
            -)
                case "${OPTARG}" in
                    help) usage && exit ;;
                    no-persistence) args["no-persistence"]="true" ;;
                    no-cleanup) args["no-cleanup"]="true" ;;
                    registry=*) args["container_registry"]="${OPTARG#*=}" ;;
                    organization=*) args["organization"]="${OPTARG#*=}" ;;
                    name=*) args["name"]="${OPTARG#*=}" ;;
                    tag=*) args["tag"]="${OPTARG#*=}" ;;
                    *) echo "Invalid option: --$OPTARG" >&2; exit 1 ;;
                esac
            ;;
            \?) echo "Invalid option: -$OPTARG" >&2; exit 2 ;;
            :) echo "Option -$OPTARG requires an argument." >&2; exit 3 ;;
        esac
    done

    if [[ -z "${args["organization"]:-}" ]]; then
        echo "ERROR: A value for the --organization flag was not provided."
        exit 4
    fi
}

function usage {
    cat <<EOF
Generates a list of Operator manifests for a SonataFlow project.
This script is a wrapper around the 'kn-workflow gen-manifest' command.

Usage: 
    $script_name --organization=<value> [flags]

Flags:
    Required:
        -o|--organization      Name of the organization in the container registry where the image will be stored.

    Optional:
        -r|--registry          The registry used to push the container image (default: 'quay.io').
        -n|--name              The image name (default: the value contained in the 'id' property of the workflow file).
        -t|--tag               The image tag (default: 'latest').
        -P|--no-persistence    Skips adding persistence configuration to the sonataflow CR.
        -C|--no-cleanup        Skips cleaning up the temporary directory at the end of this script.
EOF
}

function is_macos {
    [[ "$(uname)" == "Darwin" ]]
}

# A wrapper for the find command that uses the -E flag on macOS.
# Extended regex (ERE) is not supported by default on macOS.
function _find {
    if is_macos; then
        find -E "$@"
    else
        find "$@"
    fi
}

parse_args "$@"

workdir=$(mktemp -d -p "$workspace_dir_path/.tmp" -t 'workflow')
echo "Created working directory: ${workdir}"
cp -r "$workspace_dir_path"/{src,pom.xml} "${workdir}"

res_dir_path="${workdir}/src/main/resources"
echo "Switcing directories: $res_dir_path"
cd "$res_dir_path"

# Patch application.properties to enable Flyway migration at start
echo -e "\nquarkus.flyway.migrate-at-start=true" >> application.properties

workflow_file=$(_find . -type f -regex '.*\.sw\.ya?ml$')
if [ -z "$workflow_file" ]; then
  echo "ERROR: No workflow file found with *.sw.yaml or *.sw.yml suffix"
  exit 5
fi

workflow_id=$(yq '.id | downcase' "$workflow_file" 2>/dev/null)
if [ -z "$workflow_id" ]; then
  echo "ERROR: The workflow file doesn't seem to have an 'id' property."
  exit 6
fi

kn-workflow gen-manifest \
    -c "$workspace_dir_path/manifests" \
    --profile 'gitops' \
    --skip-namespace \
    --image "${args["registry"]}/${args["organization"]}/${args["name"]:-$workflow_id}:${args["tag"]}"

cd "$workspace_dir_path"
echo "Switched back to the project's root directory: $workspace_dir_path"

# Find the sonataflow CR for the workflow
sonataflow_cr=$(_find manifests -type f -name "*-sonataflow_${workflow_id}.yaml")

if [[ -f secret.properties ]]; then
    echo "Generating k8s secret for the workflow"
    yq --inplace ".spec.podTemplate.container.envFrom=[{\"secretRef\": { \"name\": \"${workflow_id}-creds\"}}]" "${sonataflow_cr}"
    kubectl create secret generic "${workflow_id}-creds" \
        --from-env-file=secret.properties \
        --dry-run=client -o=yaml > "manifests/00-secret_${workflow_id}.yaml"
fi

if [[ -z "${args["no-persistence"]:-}" ]]; then
    echo "Adding persistence configuration to the sonataflow CR"
    yq --inplace ".spec |= (
        . + {
        \"persistence\": {
            \"postgresql\": {
            \"secretRef\": {
                \"name\": \"sonataflow-psql-postgresql\",
                \"userKey\": \"postgres-username\",
                \"passwordKey\": \"postgres-password\"
            },
            \"serviceRef\": {
                \"name\": \"sonataflow-psql-postgresql\",
                \"port\": 5432,
                \"databaseName\": \"sonataflow\",
                \"databaseSchema\": \"${workflow_id}\"
            }
            }
        }
        }
    )" "${sonataflow_cr}"
fi

if [[ -z "${args["no-cleanup"]:-}" ]]; then
    rm -rf "${workdir}"
    echo "Removed working directory: ${workdir}"
fi
