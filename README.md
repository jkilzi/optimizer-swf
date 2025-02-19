
# Optimizer Serverless Workflow
A serverless workflow for rightsizing workload resources.

![](./src/main/resources/optimize.svg)

## Dependencies
- [Knative CLI](https://knative.dev/docs/client/install-kn/)
- [Knative Workflow CLI](https://sonataflow.org/serverlessworkflow/latest/testing-and-troubleshooting/kn-plugin-workflow-overview.html) v10.0.0
- [Sdkman](https://sdkman.io/install/) (Not mandatory, but useful for installing these other dependencies)
  - JDK 21+ (For building a native image use [GraalVM](https://www.graalvm.org/))  
  `sdk install java 21.0.2-graalce`
  
  - [Quarkus](https://quarkus.io)  
  `sdk install quarkus 3.8.6`
  
  - Maven  
  `sdk install maven 3.9.6`
  

## Running the application in dev mode

You can run your application in dev mode that enables live coding using:
```shell script
kn workflow quarkus run
```

> **_NOTE:_**  The Dev UI, which is only available in dev mode at http://localhost:8080/q/dev/, will open automatically using your default browser. Once it is up, access the Serverless Workflow Tools at: http://localhost:8080/q/dev/org.apache.kie.sonataflow.sonataflow-quarkus-devui/workflows

## Deploying the workflow
TBD...