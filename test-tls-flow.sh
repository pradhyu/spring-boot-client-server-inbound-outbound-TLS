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
if [[ ! -f "tls-server/target/tls-server-0.0.1-SNAPSHOT.jar" ]] || \
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
echo -e "${YELLOW}Tier 1:${NC} External User (curl) -> trusts -> ${CYAN}user.crt${NC} (User App's Identity)"
echo -e "${YELLOW}Tier 2:${NC} User App (8445)      -> trusts -> ${CYAN}client-trust.crt${NC} (Copy of client.crt)"
echo -e "${YELLOW}Tier 3:${NC} Client Proxy (8444)  -> trusts -> ${CYAN}server-trust.crt${NC} (Copy of server.crt)"
echo -e "${YELLOW}Final :${NC} Server Identity      -> uses   -> ${CYAN}server.crt / server.key${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

# 2. Check if already running
for entry in "8443:tls-server:server.log" "8444:tls-client:client.log" "8445:tls-user:user.log"; do
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
wait_for_https "https://localhost:8443/hello" "Server (8443)"
wait_for_https "https://localhost:8444/call-server" "Client (8444)"
wait_for_https "https://localhost:8445/test-full-chain" "User App (8445)"

# 4. Report Certificate Details from Logs
echo -e "\n${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${MAGENTA}--- 3-TIER CERTIFICATE VERIFICATION (Runtime) ---${NC}"

echo -e "${YELLOW}[User App (8445) -> Client Proxy]${NC}"
grep -A 3 "USER APP LOADING TRUST CERT" user.log | sed 's/^/    /' || echo "    Details not found in user.log"

echo -e "\n${YELLOW}[Client Proxy (8444) -> Server]${NC}"
grep -A 3 "CLIENT PROXY LOADING TRUST CERT" client.log | sed 's/^/    /' || echo "    Details not found in client.log"

echo -e "\n${YELLOW}[Final Server (8443) Identity]${NC}"
grep -A 4 "SERVER IDENTITY CERT" server.log | sed 's/^/    /' || echo "    Details not found in server.log"
echo -e "${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

# 5. Tests
USER_CA="$(pwd)/tls-user/src/main/resources/user.crt"
echo -e "${GREEN}TEST: Full 3-Tier Certificate Chain Call${NC}"
echo -e "${BLUE}Executing:${NC} curl -s --cacert $USER_CA https://localhost:8445/test-full-chain"
RESPONSE=$(curl -s --cacert "$USER_CA" https://localhost:8445/test-full-chain)

echo -e "\n${GREEN}Final Response:${NC} ${CYAN}$RESPONSE${NC}"

echo -e "\n${MAGENTA}--- 3-TIER AUDIT TRAIL ---${NC}"
echo -e "${YELLOW}[User Application]:${NC}"
grep "\[USER APP\]" user.log | tail -n 1
echo -e "${YELLOW}[Client Proxy]:${NC}"
grep "\[HOP 1\]" client.log | tail -n 1
echo -e "${YELLOW}[Final Server]:${NC}"
grep "Hello from" server.log | tail -n 1 || echo "Request reached server controller"
echo -e "${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Check for success
if [[ "$RESPONSE" == *"Hello from TLS secured server!"* ]]; then
    echo -e "${GREEN}✔ SUCCESS: Verified full flow: User -> User App -> Client Proxy -> Server${NC}"
else
    echo -e "${RED}✘ FAILURE: Chain broken.${NC}"
    exit 1
fi
