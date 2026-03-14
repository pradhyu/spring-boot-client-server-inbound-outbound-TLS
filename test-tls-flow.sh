#!/bin/bash

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

wait_for_https() {
    local url=$1
    local name=$2
    local cert=$3
    echo -ne "${YELLOW}⌛ Waiting for $name readiness... ${NC}"
    for i in {1..30}; do
        if curl -s -k "$url" > /dev/null; then
            echo -e "${GREEN}Ready!${NC}"
            return 0
        fi
        echo -ne "."
        sleep 2
    done
    echo -e "${RED}Failed to start $name${NC}"
    return 1
}

# 1. Build only if jars don't exist
if [[ ! -f "tls-server/target/tls-server-0.0.1-SNAPSHOT.jar" ]] || [[ ! -f "tls-client/target/tls-client-0.0.1-SNAPSHOT.jar" ]]; then
    echo -e "${BLUE}▶ Building project...${NC}"
    mvn clean package -Dmaven.test.skip=true > build.log 2>&1
fi

# 2. Check if already running
if lsof -Pi :8443 -sTCP:LISTEN -t >/dev/null ; then
    echo -e "${GREEN}✔ Server already running on 8443${NC}"
else
    echo -e "${BLUE}▶ Starting TLS Server on 8443...${NC}"
    java -Djavax.net.debug=ssl,handshake,keymanager,trustmanager -jar tls-server/target/tls-server-0.0.1-SNAPSHOT.jar > server.log 2>&1 &
    SERVER_PID=$!
fi

if lsof -Pi :8444 -sTCP:LISTEN -t >/dev/null ; then
    echo -e "${GREEN}✔ Client already running on 8444${NC}"
else
    echo -e "${BLUE}▶ Starting TLS Client on 8444...${NC}"
    java -Djavax.net.debug=ssl,handshake,keymanager,trustmanager -jar tls-client/target/tls-client-0.0.1-SNAPSHOT.jar > client.log 2>&1 &
    CLIENT_PID=$!
fi

# 3. Wait for readiness
wait_for_https "https://localhost:8443/hello" "Server"
wait_for_https "https://localhost:8444/call-server" "Client"

# 4. Report Paths
echo -e "\n${MAGENTA}--- RUNTIME PATH VERIFICATION ---${NC}"
SERVER_CERT_PATH=$(grep "SERVER TLS CERT PATH" server.log | tail -n 1 | awk -F': ' '{print $2}')
CLIENT_TRUST_PATH=$(grep "CLIENT TRUST CERT PATH" client.log | tail -n 1 | awk -F': ' '{print $2}')
echo -e "Server Cert: ${CYAN}${SERVER_CERT_PATH:-'N/A'}${NC}"
echo -e "Client Trust: ${CYAN}${CLIENT_TRUST_PATH:-'N/A'}${NC}"

# 5. Tests
CA_PATH="$(pwd)/tls-client/src/main/resources/client.crt"

echo -e "\n${GREEN}TEST 1: Positive Case (Full TLS Chain)${NC}"
echo -e "${BLUE}Executing:${NC} curl -v --cacert $CA_PATH https://localhost:8444/call-server"
echo -e "${YELLOW}Detailed TLS Handshake Summary:${NC}"
curl -v --cacert "$CA_PATH" https://localhost:8444/call-server 2>&1 | grep -E "TLS|handshake|SSL|ALPN|Connected to|common name|subject:|issuer:|HTTP/"

# Capture response and status code
FULL_RESPONSE=$(curl -s -w "\n%{http_code}" --cacert "$CA_PATH" https://localhost:8444/call-server)
HTTP_CODE=$(echo "$FULL_RESPONSE" | tail -n1)
RESPONSE=$(echo "$FULL_RESPONSE" | sed '$d')

echo -e "\n${YELLOW}HTTP Status Code:${NC} $HTTP_CODE"
echo -e "${GREEN}Final Response:${NC} $RESPONSE"

if [ "$HTTP_CODE" -eq 200 ] && [[ "$RESPONSE" == *"Hello from TLS secured server!"* ]]; then
    echo -e "${GREEN}✔ SUCCESS: Received 200 OK with valid response.${NC}"
    echo -e "\n${MAGENTA}--- INTERNAL PROXY AUDIT TRAIL (Client Logs) ---${NC}"
    grep -E "\[HOP" client.log | tail -n 2
    echo -e "${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
else
    echo -e "${RED}✘ FAILURE: Unexpected status code $HTTP_CODE or response.${NC}"
fi

echo -e "\n${RED}TEST 2: Negative Case (No CA)${NC}"
echo "Executing: curl -w \"\n%{http_code}\" https://localhost:8444/call-server"
CURL_OUT=$(curl -s -w "\n%{http_code}" https://localhost:8444/call-server 2>&1)
HTTP_CODE_NEG=$(echo "$CURL_OUT" | tail -n1)

if [[ "$CURL_OUT" == *"SSL certificate problem"* ]] || [[ "$CURL_OUT" == *"certificate verify failed"* ]] || [ "$HTTP_CODE_NEG" -eq 000 ]; then
    echo -e "${GREEN}✔ Blocked correctly (HTTP Code: $HTTP_CODE_NEG)${NC}"
else
    echo -e "${RED}✘ FAILURE: Connection should have been blocked (HTTP Code: $HTTP_CODE_NEG)${NC}"
fi

# 6. Final Clean up of background processes STARTED BY THIS SCRIPT
if [ ! -z "$SERVER_PID" ] || [ ! -z "$CLIENT_PID" ]; then
    echo -e "\n${YELLOW}Note: Services were started in background. Use pkill -f .jar to stop them.${NC}"
fi
