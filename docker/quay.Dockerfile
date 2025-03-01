FROM quay.io/orchestrator/ubi9-pipeline:latest

COPY --chmod=1001 . .

RUN microdnf install -y podman java-21-openjdk-devel
RUN scripts/quarkus-build.sh --project="redhat-resource-optimization" --push

