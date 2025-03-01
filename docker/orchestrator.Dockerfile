FROM registry.redhat.io/openshift-serverless-1/logic-swf-builder-rhel8:1.35.0-6 AS builder

#ENV MAVEN_REPO_URL=https://maven.repository.redhat.com/earlyaccess/all

ARG QUARKUS_EXTENSIONS="\
    org.kie:kie-addons-quarkus-monitoring-sonataflow:10.0.0, \
    org.kie:kogito-addons-quarkus-jobs-knative-eventing:10.0.0, \
    org.kie:kie-addons-quarkus-persistence-jdbc:10.0.0, \
    io.quarkus:quarkus-jdbc-postgresql:3.8.6.redhat-00004, \
    io.quarkus:quarkus-agroal:3.8.6.redhat-00004"

# Additional java/mvn arguments to pass to the builder.
# This is a conventient way for passing build-time properties to Sonataflow and Quarkus.
# Note that the 'maxYamlCodePoints' parameter contols the maximum input size for YAML files, set to 35000000 characters, which is ~33MB in UTF-8.  
ARG MAVEN_ARGS_APPEND="\
    -DmaxYamlCodePoints=35000000 \
    -Dkogito.persistence.type=jdbc \
    -Dquarkus.datasource.db-kind=postgresql \
    -Dkogito.persistence.proto.marshaller=false"

COPY --chown=1001 . .

RUN /home/kogito/launch/build-app.sh

#=============================
# Runtime Run
#=============================
FROM registry.access.redhat.com/ubi9/openjdk-17:1.21-2


ARG FLOW_NAME
ARG FLOW_SUMMARY
ARG FLOW_DESCRIPTION

ENV LANG='en_US.UTF-8' LANGUAGE='en_US:en'

# We make four distinct layers so if there are application changes the library layers can be re-used
COPY --from=builder --chown=185 /home/kogito/serverless-workflow-project/target/quarkus-app/lib/ /deployments/lib/
COPY --from=builder --chown=185 /home/kogito/serverless-workflow-project/target/quarkus-app/*.jar /deployments/
COPY --from=builder --chown=185 /home/kogito/serverless-workflow-project/target/quarkus-app/app/ /deployments/app/
COPY --from=builder --chown=185 /home/kogito/serverless-workflow-project/target/quarkus-app/quarkus/ /deployments/quarkus/
COPY LICENSE /licenses/

EXPOSE 8080
USER 185
ENV AB_JOLOKIA_OFF=""
ENV JAVA_OPTS="-Dquarkus.http.host=0.0.0.0 -Djava.util.logging.manager=org.jboss.logmanager.LogManager"
ENV JAVA_APP_JAR="/deployments/quarkus-run.jar"

LABEL name="${FLOW_NAME}"
LABEL summary="${FLOW_SUMMARY}"
LABEL description="${FLOW_DESCRIPTION}"
LABEL io.k8s.description="${FLOW_DESCRIPTION}"
LABEL io.k8s.display-name="${FLOW_NAME}"
LABEL com.redhat.component="${FLOW_NAME}"
LABEL io.openshift.tags=""