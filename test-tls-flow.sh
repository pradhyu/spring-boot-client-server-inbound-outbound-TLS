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
if [[ ! -f "tls-server-A/target/tls-server-A-0.0.1-SNAPSHOT.jar" ]] || \
   [[ ! -f "tls-server-B/target/tls-server-B-0.0.1-SNAPSHOT.jar" ]] || \
   [[ ! -f "tls-client/target/tls-client-0.0.1-SNAPSHOT.jar" ]] || \
   [[ ! -f "tls-user/target/tls-user-0.0.1-SNAPSHOT.jar" ]]; then
    echo -e "${BLUE}▶ Building project...${NC}"
    mvn clean package -Dmaven.test.skip=true > build.log 2>&1
fi

echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}--- CERTIFICATE TOPOLOGY & TRUST RELATIONSHIPS ---${NC}"
echo -e "${YELLOW}Note:${NC} All .crt/key files are in ${MAGENTA}PEM (Privacy-Enhanced Mail)${NC} format."
echo -e "      PEM is a text based format (Base64) that acts as a Trust Store."
echo -e "      One PEM file can contain multiple certificates (a bundle)."
echo -e ""
echo -e "${YELLOW}Tier 1:${NC} External User (curl) -> trusts -> ${CYAN}user.crt${NC} (Public Copy of User App's ID)"
echo -e "${YELLOW}Tier 2:${NC} User App (8445)      -> uses   -> ${MAGENTA}user.crt/key${NC} (Identity)"
echo -e "                            trusts -> ${CYAN}client-trust.crt${NC} (Public Copy of ${MAGENTA}client.crt${NC})"
echo -e "${YELLOW}Tier 3:${NC} Client Proxy (8444)  -> uses   -> ${MAGENTA}client.crt/key${NC} (Identity)"
echo -e "                            trusts -> ${CYAN}servers-trust.crt${NC} (Combined: ${MAGENTA}server-a.crt + server-b.crt${NC})"
echo -e "${YELLOW}Final :${NC} Server-A (8446)      -> uses   -> ${MAGENTA}server-a.crt/key${NC} (Identity, CN=server-a.localhost)"
echo -e "         Server-B (8447)      -> uses   -> ${MAGENTA}server-b.crt/key${NC} (Identity, CN=server-b.localhost)"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

# 2. Check if already running, start if not
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

# 3. Wait for readiness
wait_for_https "https://localhost:8446/hello" "Server-A (8446)"
wait_for_https "https://localhost:8447/hello" "Server-B (8447)"
wait_for_https "https://localhost:8444/call-server" "Client (8444)"
wait_for_https "https://localhost:8445/test-full-chain" "User App (8445)"

# 4. Report Certificate Details from Logs
sleep 2 # Allow logs to flush
echo -e "\n${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${MAGENTA}--- MULTI-SERVER CERTIFICATE VERIFICATION (Runtime) ---${NC}"

echo -e "${YELLOW}[User App (8445)]${NC}"
echo -e "  ${BLUE}Identity (Inbound):${NC}"
grep -A 2 "IDENTITY (Inbound)" user.log | sed 's/^/    /' || echo "    Details not found"
echo -e "  ${BLUE}Trust Store (Outbound):${NC}"
grep -A 3 "LOADING TRUST CERT" user.log | sed 's/^/    /' || echo "    Details not found"

echo -e "\n${YELLOW}[Client Proxy (8444)]${NC}"
echo -e "  ${BLUE}Identity (Inbound):${NC}"
grep -A 2 "IDENTITY (Inbound)" client.log | sed 's/^/    /' || echo "    Details not found"
echo -e "  ${BLUE}Trust Store (Combined Bundle):${NC}"
grep -A 10 "LOADING TRUST CERTS" client.log | sed 's/^/    /' || echo "    Details not found"

echo -e "\n${YELLOW}[Server-A (8446)]${NC}"
echo -e "  ${BLUE}Identity (Inbound):${NC}"
grep -A 4 "SERVER-A IDENTITY" server-a.log | sed 's/^/    /' || echo "    Details not found"

echo -e "\n${YELLOW}[Server-B (8447)]${NC}"
echo -e "  ${BLUE}Identity (Inbound):${NC}"
grep -A 4 "SERVER-B IDENTITY" server-b.log | sed 's/^/    /' || echo "    Details not found"
echo -e "${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

# 5. Positive Test: Full Multi-Server Chain Call
USER_CA="$(pwd)/tls-user/src/main/resources/user.crt"
echo -e "${GREEN}TEST 1: Positive Case (Full TLS Chain - Both Servers)${NC}"
echo -e "${BLUE}Executing:${NC} curl -s -w \"\\n%{http_code}\" --cacert $USER_CA https://localhost:8445/test-full-chain"
FULL_OUT=$(curl -s -w "\n%{http_code}" --cacert "$USER_CA" https://localhost:8445/test-full-chain)
HTTP_CODE=$(echo "$FULL_OUT" | tail -n1)
RESPONSE=$(echo "$FULL_OUT" | sed '$d')

echo -e "\n${YELLOW}HTTP Status Code:${NC} $HTTP_CODE"
echo -e "${GREEN}Final Response:${NC} ${CYAN}$RESPONSE${NC}"

echo -e "\n${MAGENTA}--- MULTI-SERVER AUDIT TRAIL ---${NC}"
echo -e "${YELLOW}[User Application]:${NC}"
grep "\[USER APP\]" user.log | tail -n 1
echo -e "${YELLOW}[Client Proxy]:${NC}"
grep "\[HOP 1\]" client.log | tail -n 1
echo -e "${YELLOW}[Server-A Response]:${NC}"
grep "\[HOP 2a" client.log | tail -n 1
echo -e "${YELLOW}[Server-B Response]:${NC}"
grep "\[HOP 2b" client.log | tail -n 1
echo -e "${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Check for success - response should contain both Server-A and Server-B
if [ "$HTTP_CODE" -eq 200 ] && [[ "$RESPONSE" == *"Server-A"* ]] && [[ "$RESPONSE" == *"Server-B"* ]]; then
    echo -e "${GREEN}✔ SUCCESS: Verified full flow: User -> User App -> Client Proxy -> (Server-A + Server-B)${NC}"
else
    echo -e "${RED}✘ FAILURE: Unexpected Status ($HTTP_CODE) or Response.${NC}"
    echo -e "${RED}  Expected combined response containing both Server-A and Server-B${NC}"
    exit 1
fi

echo -e "\n${RED}TEST 2: Negative Case (No CA Certificate)${NC}"
echo -e "${BLUE}Executing:${NC} curl -s -w \"%{http_code}\" https://localhost:8445/test-full-chain"
CURL_OUT=$(curl -s -w "\n%{http_code}" https://localhost:8445/test-full-chain 2>&1)
HTTP_CODE_NEG=$(echo "$CURL_OUT" | tail -n1)
CURL_ERROR=$(echo "$CURL_OUT" | sed '$d')

echo -e "${YELLOW}HTTP Status Code:${NC} $HTTP_CODE_NEG"
if [[ "$CURL_OUT" == *"SSL certificate problem"* ]] || [[ "$CURL_OUT" == *"certificate verify failed"* ]] || [ "$HTTP_CODE_NEG" -eq 000 ]; then
    echo -e "${GREEN}✔ Blocked correctly: ${NC}Handshake failed (Status 000)"
else
    echo -e "${RED}✘ FAILURE: Connection should have been blocked!${NC}"
    echo -e "Debug Info: $CURL_OUT"
    exit 1
fi

echo -e "\n${RED}TEST 3: Negative Case (Mismatch CA - using server-a cert against user endpoint)${NC}"
SERVER_A_CA="$(pwd)/tls-server-A/src/main/resources/server-a.crt"
echo -e "${BLUE}Executing:${NC} curl -s -w \"%{http_code}\" --cacert $SERVER_A_CA https://localhost:8445/test-full-chain"
CURL_OUT=$(curl -s -w "\n%{http_code}" --cacert "$SERVER_A_CA" https://localhost:8445/test-full-chain 2>&1)
HTTP_CODE_NEG=$(echo "$CURL_OUT" | tail -n1)

echo -e "${YELLOW}HTTP Status Code:${NC} $HTTP_CODE_NEG"
if [[ "$CURL_OUT" == *"SSL certificate problem"* ]] || [[ "$CURL_OUT" == *"certificate verify failed"* ]] || [ "$HTTP_CODE_NEG" -eq 000 ]; then
    echo -e "${GREEN}✔ Blocked correctly: ${NC}Handshake failed (Status 000)"
else
    echo -e "${RED}✘ FAILURE: Connection should have been blocked!${NC}"
    echo -e "Debug Info: $CURL_OUT"
    exit 1
fi
