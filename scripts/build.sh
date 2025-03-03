#!/usr/bin/env bash

set -euo pipefail

script_name="${BASH_SOURCE:-$0}"
script_path=$(realpath "$script_name")
scripts_dir_path=$(dirname "$script_path")

# shellcheck disable=SC1091
source "${scripts_dir_path}/lib/_functions.sh"
# shellcheck disable=SC1091
source "${scripts_dir_path}/lib/_logger.sh"

function usage {
    cat <<EOF
This script performs the following tasks in this specific order:
1. Generates a list of Operator manifests for a SonataFlow project
2. Builds the workflow image using 
3. Optionally deploys.
    3.1 Pushes the image to a registry (specidied in the image path)
    3.2 Applies the generated manifests in the current k8s namespace

Usage: 
    $script_name [flags]

Flags:
    -i|--image string                 The image path to use for the workflow (required).
    -b|--builder-image string         Overrides the image to use for building the workflow image.
    -h|--help                         Prints this help message.
    -r|--runtime-image string         Overrides the image to use for running the workflow.
    -w|--workflow-directory string    Path to the directory containing the workflow's files (the 'src' directory). Default: current directory.
    -P|--no-persistence               Skips adding persistence configuration to the sonataflow CR.
       --apply                        Applies the generated manifests in the current namespace.
       --push                         Pushes the image to the registry after building

Note: The manifests will be in 'manifests' beside 'src'.
EOF
}

declare -A args
args["apply"]=""
args["image"]=""
args["no-persistence"]=""
args["push"]=""
args["workflow-directory"]="$PWD"
args["builder-image"]=""
args["runtime-image"]=""

function parse_args {
    while getopts ":i:b:r:w:hP-:" opt; do
        case $opt in
            h) usage; exit ;;
            P) args["no-persistence"]="YES" ;;
            i) args["image"]="$OPTARG" ;;
            w) args["workflow-directory"]="$OPTARG" ;;
            b) args["builder-image"]="$OPTARG" ;;
            r) args["runtime-image"]="$OPTARG" ;;
            -)
                case "${OPTARG}" in
                    help)
                        usage; exit ;;
                    apply)
                        args["apply"]="YES" ;;
                    no-persistence)
                        args["no-persistence"]="YES" ;;
                    push)
                        args["push"]="YES" ;;
                    image=*)
                        args["image"]="${OPTARG#*=}" ;;
                    workflow-directory=*)
                        args["workflow-directory"]="${OPTARG#*=}" ;;
                    builder-image=*)
                        args["builder-image"]="${OPTARG#*=}" ;;
                    runtime-image=*)
                        args["runtime-image"]="${OPTARG#*=}" ;;
                    *) log_error "Invalid option: --$OPTARG"; usage; exit 1 ;;
                esac
            ;;
            \?) log_error "Invalid option: -$OPTARG"; usage; exit 2 ;;
            :) log_error "Option -$OPTARG requires an argument."; usage; exit 3 ;;
        esac
    done

    if [[ -z "${args["image"]:-}" ]]; then
        log_error "Missing required flag: --image"
        usage; exit 4
    fi
}

function gen_manifests {
    local res_dir_path="${args["workflow-directory"]}/src/main/resources"
    local workflow_id

    workflow_id=$(get_workflow_id "$res_dir_path")

    cd "$res_dir_path"
    log_info "Switched directory: $res_dir_path"

    kn-workflow gen-manifest \
        -c "${args["workflow-directory"]}/manifests" \
        --profile 'gitops' \
        --skip-namespace \
        --image "${args["image"]}"

    cd "${args["workflow-directory"]}"
    log_info "Switched directory: ${args["workflow-directory"]}"

    # Find the sonataflow CR for the workflow
    sonataflow_cr=$(findw manifests -type f -name "*-sonataflow_${workflow_id}.yaml")

    if [[ -f secret.properties ]]; then
        yq --inplace ".spec.podTemplate.container.envFrom=[{\"secretRef\": { \"name\": \"${workflow_id}-creds\"}}]" "${sonataflow_cr}"
        kubectl create secret generic "${workflow_id}-creds" \
            --from-env-file=secret.properties \
            --dry-run=client -o=yaml > "manifests/00-secret_${workflow_id}.yaml"
        log_info "Generated k8s secret for the workflow"
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
        log_info "Added persistence configuration to the sonataflow CR"
    fi
}

function build_image {
    local image_name="${args["image"]%:*}"
    local tag="${args["image"]#*:}"

    # Build specifically for linux/amd64 so macos users with arm-based CPUs can also run this image.
    pocker_args=(
        -f="${args["workflow-directory"]}/docker/osl.Dockerfile"
        --platform='linux/amd64'
        --ulimit='nofile=4096:4096'
    )
    [[ -n "${args["builder-image"]:-}" ]] && pocker_args+=(--build-arg="BUILDER_IMAGE=${args["builder-image"]}")
    [[ -n "${args["runtime-image"]:-}" ]] && pocker_args+=(--build-arg="RUNTIME_IMAGE=${args["runtime-image"]}")

    log_info "Building the workflow image"
    pocker build "${pocker_args[@]}" "${args["workflow-directory"]}"
    pocker tag "${args["image"]}" "$image_name:$(git rev-parse --short=8 HEAD)"
    if [[ "$tag" != "latest" ]]; then
        pocker tag "${args["image"]}" "$image_name:latest"
    fi
    pocker images --filter="reference=$image_name" --format="{{.Repository}}:{{.Tag}}"
}

function maybe_deploy {
    local image_name="${args["image"]%:*}"
    local tag="${args["image"]#*:}"

    if [[ -n "${args["push"]}" ]]; then
        docker push "${args["image"]}"
        docker push "$image_name:$(git rev-parse --short=8 HEAD)"
        if [[ "$tag" != "latest" ]]; then
            docker push "$image_name:latest"
        fi
    fi

    if [[ -n "${args["apply"]}" ]]; then
        kubectl apply -f "${args["workflow-directory"]}/manifests"
        log_info "Applied the generated manifests"
    fi
}

parse_args "$@"

gen_manifests
build_image
maybe_deploy
