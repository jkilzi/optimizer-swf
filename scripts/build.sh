#!/usr/bin/env bash

set -euo pipefail

script_name="${BASH_SOURCE:-$0}"
script_path=$(realpath "$script_name")
scripts_dir_path=$(dirname "$script_path")

# shellcheck disable=SC1091
source "${scripts_dir_path}/lib/_functions.sh"

function usage {
    cat <<EOF
Generates a list of Operator manifests for a SonataFlow project and builds the workflow image.

Usage: 
    $script_name [flags]

Flags:
    -i|--image string                 The image path to use for the workflow.
    -w|--workflow-directory string    Path to the directory containing the workflow's files (the 'src' directory). Default: current directory.
    -P|--no-persistence               Skips adding persistence configuration to the sonataflow CR.
       --apply                        Applies the generated manifests in the current namespace.
       --push                         Pushes the image to the registry after building

Notes:
    1. The project name or the image path must be specified using --project or --image flags correspondingly.
    2. The manifests will be in 'manifests' beside 'src'.
    3. This script is a wrapper around the 'kn-workflow gen-manifest' command.
EOF
}

declare -A args
args["image"]=""
args["workflow-directory"]="$PWD"
args["no-persistence"]=""
args["apply"]=""
args["push"]=""

function parse_args {
    while getopts ":i:w:hP-:" opt; do
        case $opt in
            h) usage && exit ;;
            P) args["no-persistence"]="YES" ;;
            i) args["image"]="$OPTARG" ;;
            w) args["workflow-directory"]="$OPTARG" ;;
            -)
                case "${OPTARG}" in
                    help)
                        usage && exit ;;
                    apply)
                        args["apply"]="YES" ;;
                    no-persistence)
                        args["no-persistence"]="YES" ;;
                    push)
                        args["push"]="--push" ;;
                    image=*)
                        args["image"]="${OPTARG#*=}" ;;
                    workflow-directory=*)
                        args["workflow-directory"]="${OPTARG#*=}" ;;
                    *) echo "Invalid option: --$OPTARG" >&2; exit 1 ;;
                esac
            ;;
            \?) echo "Invalid option: -$OPTARG" >&2; exit 2 ;;
            :) echo "Option -$OPTARG requires an argument." >&2; exit 3 ;;
        esac
    done

    if [[ -z "${args["image"]:-}" ]]; then
        echo "ERROR: Missing --image flag."
        exit 4
    fi
}

parse_args "$@"

manifests_dir_path="${args["workflow-directory"]}/manifests"
res_dir_path="${args["workflow-directory"]}/src/main/resources"
workflow_id=$(get_workflow_id "$res_dir_path")

cd "$res_dir_path"
echo "Switched directory: $res_dir_path"

kn-workflow gen-manifest \
    -c "${manifests_dir_path}" \
    --profile 'gitops' \
    --skip-namespace \
    --image "${args["image"]}"

cd "${args["workflow-directory"]}"
echo "Switched directory: ${args["workflow-directory"]}"

# Find the sonataflow CR for the workflow
sonataflow_cr=$(findw "${manifests_dir_path}" -type f -name "*-sonataflow_${workflow_id}.yaml")

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
    kubectl apply -f "$manifests_dir_path"
    echo "Applied the generated manifests"
fi

kn workflow quarkus build --image="${args["image"]}" "${args["push"]}"
