#!/usr/bin/env bash

set -euo pipefail

script_name="${BASH_SOURCE:-$0}"
script_path=$(realpath "$script_name")
scripts_dir_path=$(dirname "$script_path")

# shellcheck disable=SC1091
source "${scripts_dir_path}/lib/_functions.sh"

declare -A args
args["apply"]=""
args["no-persistence"]=""
args["image"]=""
args["registry"]="quay.io"
args["project"]=""
args["name"]=""
args["tag"]="latest"
args["workflow-directory"]="$PWD"

function parse_args {
    while getopts ":i:r:p:n:t:w:hP-:" opt; do
        case $opt in
            h) usage && exit ;;
            P) args["no-persistence"]="true" ;;
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
                    apply)
                        args["apply"]="true" ;;
                    no-persistence)
                        args["no-persistence"]="true" ;;
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
Generates a list of Operator manifests for a SonataFlow project.

Usage: 
    $script_name [flags]

Flags:
    -a|--apply                        Applies the generated manifests in the current namespace.
    -i|--image string                 Full image name in the form of [registry]/[project]/[name]:[tag]
                                        Required when the registry, project, name and tag flags are not specified.
    -n|--name string                  The image name
                                        Overrides the [name] part when the --image flag is specified
                                        Default: the workflow ID in the workflow file
                                        Example: 'fedora-42' as in 'quay.io/fedora/fedora-42'
    -p|--project string               The project name in the containers registry
                                        Overrides the [project] part when the --image flag is specified
                                        Example: 'fedora' as in 'quay.io/fedora'
    -r|--registry string              The containers registry to use
                                        Overrides the [registry] part when the --image flag is specified
                                        Example: 'quay.io'
    -t|--tag string                   The image tag
                                        Default: 'latest'
    -w|--workflow-directory string    Path to the directory containing the workflow's files (the 'src' directory).
                                        Default: current directory
    -P|--no-persistence               Skips adding persistence configuration to the sonataflow CR.

Notes:
    1. The project name or the image path must be specified using --project or --image flags correspondingly.
    2. The manifests will be in 'manifests' beside 'src'.
    3. This script is a wrapper around the 'kn-workflow gen-manifest' command.
EOF
}

parse_args "$@"

res_dir_path="${args["workflow-directory"]}/src/main/resources"
cd "$res_dir_path"
echo "Switched directory: $res_dir_path"

# Enable Flyway migration at start if necessary
if grep -qv 'quarkus.flyway.migrate-at-start=true' application.properties; then
    echo -e "\nquarkus.flyway.migrate-at-start=true" >> application.properties
fi

workflow_id=$(get_workflow_id "$res_dir_path")
image="${args["image"]:-${args["registry"]}/${args["project"]}/${args["name"]:-$workflow_id}:${args["tag"]}}"
kn-workflow gen-manifest \
    -c "${args["workflow-directory"]}/manifests" \
    --profile 'gitops' \
    --skip-namespace \
    --image "$image"

if git status --short | grep -Eq 'application\.properties$'; then
    git restore application.properties
fi

cd "${args["workflow-directory"]}"
echo "Switched directory: ${args["workflow-directory"]}"

# Find the sonataflow CR for the workflow
sonataflow_cr=$(findw manifests -type f -name "*-sonataflow_${workflow_id}.yaml")

if [[ -f secret.properties ]]; then
    yq --inplace ".spec.podTemplate.container.envFrom=[{\"secretRef\": { \"name\": \"${workflow_id}-creds\"}}]" "${sonataflow_cr}"
    kubectl create secret generic "${workflow_id}-creds" \
        --from-env-file=secret.properties \
        --dry-run=client -o=yaml > "manifests/00-secret_${workflow_id}.yaml"
    echo "Generated k8s secret for the workflow"
fi

if [[ -z "${args["no-persistence"]:-}" ]]; then
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
    echo "Added persistence configuration to the sonataflow CR"
fi

if [[ -n "${args["apply"]}" ]]; then
    kubectl apply -f "${args["workflow-directory"]}/manifests"
    echo "Applied the generated manifests"
fi
