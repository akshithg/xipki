#!/bin/bash
set -e

echo "Waiting for database at xipki-db:3306..."
while ! nc -z xipki-db 3306; do
  sleep 1
done
echo "Database started"

# Start Tomcat in background
echo "Starting Tomcat..."
catalina.sh run &
TOMCAT_PID=$!

# Initialize CA after Tomcat is ready
./init-ca.sh

# Wait for Tomcat process
wait $TOMCAT_PID
