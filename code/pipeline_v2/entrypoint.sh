#!/bin/sh
# Start BRouter using the jar specified in BROUTER_JAR env variable
# (set via docker-compose environment: BROUTER_JAR=/brouter/bin/brouter-server-1.7.8-all.jar)
if [ -z "$BROUTER_JAR" ]; then
  echo "ERROR: BROUTER_JAR environment variable not set"
  exit 1
fi
echo "Starting BRouter with: $BROUTER_JAR"
echo "Arguments: $@"
exec java $JAVA_OPTS -cp "$BROUTER_JAR" btools.server.RouteServer "$@"
