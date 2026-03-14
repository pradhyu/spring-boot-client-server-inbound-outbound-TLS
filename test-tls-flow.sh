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
    local cert_args=$3
    echo -ne "${YELLOW}⌛ Waiting for $name readiness... ${NC}"
    for i in {1..30}; do
        if curl -s -k $cert_args "$url" > /dev/null 2>&1 || [[ "$(curl -s -k $cert_args -o /dev/null -w "%{http_code}" "$url")" == "403" ]]; then
            echo -e "${GREEN}Ready!${NC}"
            return 0
        fi
        echo -ne "."
        sleep 2
    done
    echo -e "${RED}Failed to start $name${NC}"
    return 1
}

# 1. Build
echo -e "${BLUE}▶ Building project...${NC}"
mvn clean package -Dmaven.test.skip=true > build.log 2>&1

echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}--- CERTIFICATE TOPOLOGY & TRUST RELATIONSHIPS (mTLS) ---${NC}"
echo -e "${YELLOW}Tier 1:${NC} External User (curl) -> trusts -> ${CYAN}user.crt${NC}"
echo -e "${YELLOW}Tier 2:${NC} User App (8445)      -> uses   -> ${MAGENTA}user.crt/key${NC}, trusts -> ${CYAN}client.crt${NC}"
echo -e "${YELLOW}Tier 3:${NC} Client Proxy (8444)  -> uses   -> ${MAGENTA}client.crt/key${NC}, trusts -> ${CYAN}servers-trust.crt${NC}"
echo -e "${YELLOW}Final :${NC} Server-A (8446)      -> uses   -> ${MAGENTA}server-a.crt/key${NC}, ${BLUE}trusts -> client.crt (mTLS REQUIRED)${NC}"
echo -e "         Server-B (8447)      -> uses   -> ${MAGENTA}server-b.crt/key${NC}, ${BLUE}trusts -> client.crt (mTLS REQUIRED)${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

# 2. Start services
for entry in "8446:tls-server-A:server-a.log" "8447:tls-server-B:server-b.log" "8444:tls-client:client.log" "8445:tls-user:user.log"; do
    port="${entry%%:*}"
    rest="${entry#*:}"
    module="${rest%%:*}"
    log_file="${rest#*:}"
    
    if lsof -Pi :$port -sTCP:LISTEN -t >/dev/null ; then
        echo -e "${GREEN}✔ $module already running on $port${NC}"
    else
        echo -e "${BLUE}▶ Starting $module on $port...${NC}"
        java -Djavax.net.debug=ssl,handshake,keymanager,trustmanager -jar $module/target/$module-0.0.1-SNAPSHOT.jar > $log_file 2>&1 &
    fi
done

CLIENT_CERT="--cert tls-client/src/main/resources/client.crt --key tls-client/src/main/resources/client.key"

# 3. Wait for readiness
wait_for_https "https://localhost:8446/hello" "Server-A (8446)" "$CLIENT_CERT"
wait_for_https "https://localhost:8447/hello" "Server-B (8447)" "$CLIENT_CERT"
wait_for_https "https://localhost:8444/call-server" "Client (8444)"
wait_for_https "https://localhost:8445/test-full-chain" "User App (8445)"

# 4. Tests
USER_CA="$(pwd)/tls-user/src/main/resources/user.crt"

echo -e "\n${GREEN}TEST 1: Positive Case (Full TLS Chain with mTLS)${NC}"
FULL_OUT=$(curl -s -w "\n%{http_code}" --cacert "$USER_CA" https://localhost:8445/test-full-chain)
HTTP_CODE=$(echo "$FULL_OUT" | tail -n1)
RESPONSE=$(echo "$FULL_OUT" | sed '$d')
echo -e "Final Response: ${CYAN}$RESPONSE${NC} (Status: $HTTP_CODE)"

if [ "$HTTP_CODE" -eq 200 ] && [[ "$RESPONSE" == *"Server-A"* ]] && [[ "$RESPONSE" == *"Server-B"* ]]; then
    echo -e "${GREEN}✔ SUCCESS: Verified mTLS flow: User -> User App -> Client Proxy -> (Server-A + Server-B)${NC}"
else
    echo -e "${RED}✘ FAILURE: Unexpected Response.${NC}"
    exit 1
fi

echo -e "\n${RED}TEST 2: Negative Case (Direct Server Call - NO Client Cert)${NC}"
CODE=$(curl -s -k -o /dev/null -w "%{http_code}" https://localhost:8446/hello)
if [ "$CODE" -eq 000 ] || [ "$CODE" -eq 403 ]; then
    echo -e "${GREEN}✔ Blocked correctly: ${NC}Server rejected request without client certificate (Status $CODE)"
else
    echo -e "${RED}✘ FAILURE: Server allowed request without client certificate! (Status $CODE)${NC}"
    exit 1
fi

echo -e "\n${GREEN}TEST 3: Positive Case (Direct Server Call - WITH Client Cert)${NC}"
CODE=$(curl -s -k -o /dev/null -w "%{http_code}" $CLIENT_CERT https://localhost:8446/hello)
if [ "$CODE" -eq 200 ]; then
    echo -e "${GREEN}✔ SUCCESS: ${NC}Server accepted request with valid client certificate"
else
    echo -e "${RED}✘ FAILURE: Server rejected valid client certificate! (Status $CODE)${NC}"
    exit 1
fi
