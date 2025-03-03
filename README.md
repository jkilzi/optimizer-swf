# serverless-workflow-project

This project uses Quarkus, the Supersonic Subatomic Java Framework.

If you want to learn more about Quarkus, please visit its website: https://quarkus.io/ .

## Running the application in dev mode

You can run your application in dev mode that enables live coding using:
```shell script
./mvnw compile quarkus:dev
```

> **_NOTE:_**  Quarkus now ships with a Dev UI, which is available in dev mode only at http://localhost:8080/q/dev/.

## Packaging and running the application

The application can be packaged using:
```shell script
./mvnw package
```
It produces the `quarkus-run.jar` file in the `target/quarkus-app/` directory.
Be aware that it’s not an _über-jar_ as the dependencies are copied into the `target/quarkus-app/lib/` directory.

The application is now runnable using `java -jar target/quarkus-app/quarkus-run.jar`.

If you want to build an _über-jar_, execute the following command:
```shell script
./mvnw package -Dquarkus.package.type=uber-jar
```

The application, packaged as an _über-jar_, is now runnable using `java -jar target/*-runner.jar`.

## Creating a native executable

You can create a native executable using: 
```shell script
./mvnw package -Dnative
```

Or, if you don't have GraalVM installed, you can run the native executable build in a container using: 
```shell script
./mvnw package -Dnative -Dquarkus.native.container-build=true
```

You can then execute your native executable with: `./target/serverless-workflow-project-1.0.0-SNAPSHOT-runner`

If you want to learn more about building native executables, please consult https://quarkus.io/guides/maven-tooling.

## Related Guides

- Kubernetes ([guide](https://quarkus.io/guides/kubernetes)): Generate Kubernetes resources from annotations
- Kogito Jobs Service Knative Eventing Add-On ([guide](https://quarkus.io/guides/kogito)): Kogito Add-On to interact with the Kogito Jobs Service using events via the knative eventing system
- KIE Monitoring Prometheus Add-On ([guide](https://quarkus.io/guides/kie)): Kogito Add-On for Prometheus Monitoring
- SmallRye Health ([guide](https://quarkus.io/guides/smallrye-health)): Monitor service health
- SonataFlow Quarkus Extension ([guide](https://quarkus.io/guides/sonataflow)): Quarkus Extension to include the SonataFlow engine
- KIE Events Process Add-On ([guide](https://quarkus.io/guides/kie)): KIE Add-On for Processes Events
- KIE Process Management Add-On ([guide](https://quarkus.io/guides/kie)): KIE Process Management REST API
- KIE Kubernetes Add-On ([guide](https://quarkus.io/guides/kie)): Adds support for Kubernetes integrations within KIE engine.
- KIE Knative Eventing Add-On ([guide](https://quarkus.io/guides/kie)): Adds support for CloudEvents on top of HTTP and Knative env vars configuration.
- KIE Source Files Add-On ([guide](https://quarkus.io/guides/kie)): KIE Add-On to Provide access to source files for Quarkus
- Kogito Add-On Microprofile Config Service Catalog ([guide](https://quarkus.io/guides/kogito)): Kogito Add-On to use the service discovery API at the time the resolved values can be configured as properties

## Provided Code

### SmallRye Health

Monitor your application's health using SmallRye Health

[Related guide section...](https://quarkus.io/guides/smallrye-health)

<!--
  Licensed to the Apache Software Foundation (ASF) under one
  or more contributor license agreements.  See the NOTICE file
  distributed with this work for additional information
  regarding copyright ownership.  The ASF licenses this file
  to you under the Apache License, Version 2.0 (the
  "License"); you may not use this file except in compliance
  with the License.  You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing,
  software distributed under the License is distributed on an
  "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
  KIND, either express or implied.  See the License for the
  specific language governing permissions and limitations
  under the License.
  -->

### SonataFlow Serverless Workflow codestart

This is an example Kogito Serverless Workflow Quarkus codestart, it contains a sample Serverless Workflow definition for REST code generation.

[Related guide section...](https://quarkus.io/guides/sonataflow)

This Kogito Serverless Workflow project contains a sample workflow definition as described in the [Quarkus Kogito guide](https://quarkus.io/guides/kogito).
The goal is to showcase automatic REST endpoint codegen, based on the content of the model.
The `greet.sw.json` workflow will greet users in different languages based on the input.

You can reference the [full guide on the Quarkus website](https://quarkus.io/guides/kogito).
