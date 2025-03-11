#!/usr/bin/env -S deno --allow-net=converter.swagger.io --allow-read=openshift-openapi-v2.json
// deno-lint-ignore-file ban-ts-comment

import * as YAML from "jsr:@std/yaml";

type JsonScalar = number | string | boolean | null;

function isJsonScalar(value: unknown): value is JsonScalar {
    return (
        typeof value === "number" ||
        typeof value === "string" ||
        typeof value === "boolean" ||
        value === null
    );
}

function isNonNullObject(value: unknown): value is object {
    return value?.constructor.name === "Object";
}

type RefDiscoveredCallback = (
    value: string,
    category: "definitions" | "parameters",
) => string;

function visit(node: unknown, onRefDiscovered: RefDiscoveredCallback) {
    switch (true) {
        case (isJsonScalar(node)): {
            return;
        }

        case (Array.isArray(node)): {
            for (const n of node) {
                visit(n, onRefDiscovered);
            }
            break;
        }

        case (isNonNullObject(node)): {
            for (const [k, v] of Object.entries(node)) {
                if (k === "$ref") {
                    switch (true) {
                        case v.startsWith("#/definitions/"):
                            onRefDiscovered(v, "definitions");
                            break;
                        case v.startsWith("#/parameters/"):
                            onRefDiscovered(v, "parameters");
                            break;
                        default:
                            throw new Error("Unsupported $ref: " + k);
                    }
                }

                visit(v, onRefDiscovered);
            }
            break;
        }

        default:
            throw new Error("Invalid argument!");
    }
}

async function convertToOpenapiV3(
    inputData: Record<string, unknown>,
): Promise<Record<string, unknown>> {
    const response = await fetch("https://converter.swagger.io/api/convert", {
        method: "POST",
        headers: {
            "Content-Type": "application/json",
        },
        body: JSON.stringify(inputData),
    });
    const data = await response.json();
    return data;
}

async function main(args: Array<string>) {
    const DEPLOYMENTS_API_PATH =
        "/apis/apps/v1/namespaces/{namespace}/deployments";
    const DEPLOYMENT_API_PATH =
        "/apis/apps/v1/namespaces/{namespace}/deployments/{name}";

    const { default: fullOpenapi } = await import(
        "./openshift-openapi.json",
        {
            with: { type: "json" },
        }
    );
    const { patch: updateDeployment, parameters: deploymentParameters } =
        fullOpenapi.paths[DEPLOYMENT_API_PATH];
    const { get: listDeployments, parameters: deploymentsParameters } =
        fullOpenapi.paths[DEPLOYMENTS_API_PATH];

    const partialOpenapi = {
        swagger: fullOpenapi.swagger,
        info: fullOpenapi.info,
        security: fullOpenapi.security,
        securityDefinitions: fullOpenapi.securityDefinitions,
        paths: {
            [DEPLOYMENTS_API_PATH]: {
                parameters: deploymentsParameters,
                get: listDeployments,
            },
            [DEPLOYMENT_API_PATH]: {
                parameters: deploymentParameters,
                patch: updateDeployment,
            },
        },
        definitions: {},
        parameters: {},
    };

    const handleRefDiscovered = (
        value: string,
        category: "definitions" | "parameters",
        source = fullOpenapi,
        destination = partialOpenapi,
    ): string => {
        const defName = value.replace(new RegExp(`^#/${category}/`), "");
        if (!Object.hasOwn(destination, defName)) {
            // Link the definition or parameter spec from the full API to the partial API.
            // @ts-ignore
            destination[category][defName] = source[category][defName];
            // @ts-ignore
            visit(destination[category][defName], handleRefDiscovered);
        }

        return defName;
    };

    visit(partialOpenapi.paths, handleRefDiscovered);
    const openapiV3 = await convertToOpenapiV3(partialOpenapi);
    openapiV3.openapi = "3.1.0";

    const format = args[0] ?? 'yaml';
    switch (format) {
        case "yaml":
            console.log(YAML.stringify(openapiV3));
            break;
        case "json":
            console.log(JSON.stringify(openapiV3, null, 2));
            break;
        default:
            throw new Error(`Error: Invalid argument ${args[0]}`);
    }
}

await main(Deno.args);
