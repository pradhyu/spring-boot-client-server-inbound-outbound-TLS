#!/bin/bash

# Build the project
echo "Building project..."
mvn clean package -Dmaven.test.skip=true

# Function to kill background processes on exit
cleanup() {
    echo "Stopping server and client..."
    kill $SERVER_PID $CLIENT_PID
}
trap cleanup EXIT

# Start Server
echo "Starting TLS Server on port 8443..."
java -jar tls-server/target/tls-server-0.0.1-SNAPSHOT.jar > server.log 2>&1 &
SERVER_PID=$!

# Start Client
echo "Starting TLS Client on port 8444..."
java -jar tls-client/target/tls-client-0.0.1-SNAPSHOT.jar > client.log 2>&1 &
CLIENT_PID=$!

echo "Waiting for services to start..."
sleep 30

# Test the flow
echo "Calling Client (HTTPS) which calls Server (HTTPS)..."
echo "Command: curl -k https://localhost:8444/call-server"
RESPONSE=$(curl -k https://localhost:8444/call-server)

echo "--------------------------------"
echo "Response: $RESPONSE"
echo "--------------------------------"

if [[ "$RESPONSE" == *"Hello from TLS secured server!"* ]]; then
    echo "SUCCESS: End-to-end TLS verified!"
else
    echo "FAILURE: Response did not match expectation."
    exit 1
fi
