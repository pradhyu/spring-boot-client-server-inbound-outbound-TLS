#!/bin/bash
set -e

BASE="$(cd "$(dirname "$0")" && pwd)"

echo "=== Generating Server-A certificate ==="
openssl req -x509 -newkey rsa:2048 \
  -keyout "$BASE/tls-server-A/src/main/resources/server-a.key" \
  -out "$BASE/tls-server-A/src/main/resources/server-a.crt" \
  -days 365 -nodes \
  -subj "/CN=server-a.localhost" \
  -addext "subjectAltName=DNS:localhost,DNS:server-a.localhost,IP:127.0.0.1"

echo "=== Generating Server-B certificate ==="
openssl req -x509 -newkey rsa:2048 \
  -keyout "$BASE/tls-server-B/src/main/resources/server-b.key" \
  -out "$BASE/tls-server-B/src/main/resources/server-b.crt" \
  -days 365 -nodes \
  -subj "/CN=server-b.localhost" \
  -addext "subjectAltName=DNS:localhost,DNS:server-b.localhost,IP:127.0.0.1"

echo "=== Generating Client certificate ==="
openssl req -x509 -newkey rsa:2048 \
  -keyout "$BASE/tls-client/src/main/resources/client.key" \
  -out "$BASE/tls-client/src/main/resources/client.crt" \
  -days 365 -nodes \
  -subj "/CN=localhost" \
  -addext "subjectAltName=DNS:localhost,IP:127.0.0.1"

echo "=== Generating User certificate ==="
openssl req -x509 -newkey rsa:2048 \
  -keyout "$BASE/tls-user/src/main/resources/user.key" \
  -out "$BASE/tls-user/src/main/resources/user.crt" \
  -days 365 -nodes \
  -subj "/CN=user.localhost" \
  -addext "subjectAltName=DNS:localhost,DNS:user.localhost,IP:127.0.0.1"

echo "=== Distributing Client cert to servers and user app for trust ==="
cp "$BASE/tls-client/src/main/resources/client.crt" "$BASE/tls-server-A/src/main/resources/"
cp "$BASE/tls-client/src/main/resources/client.crt" "$BASE/tls-server-B/src/main/resources/"
cp "$BASE/tls-client/src/main/resources/client.crt" "$BASE/tls-user/src/main/resources/client-trust.crt"

echo "=== Creating combined trust bundle for tls-client ==="
cat "$BASE/tls-server-A/src/main/resources/server-a.crt" \
    "$BASE/tls-server-B/src/main/resources/server-b.crt" \
    > "$BASE/tls-client/src/main/resources/servers-trust.crt"

echo "=== Done! ==="
echo "Client cert:"
openssl x509 -in "$BASE/tls-client/src/main/resources/client.crt" -noout -subject
echo "Server-A cert:"
openssl x509 -in "$BASE/tls-server-A/src/main/resources/server-a.crt" -noout -subject -ext subjectAltName
echo "Server-B cert:"
openssl x509 -in "$BASE/tls-server-B/src/main/resources/server-b.crt" -noout -subject -ext subjectAltName
echo "Combined trust bundle:"
grep "BEGIN CERTIFICATE" "$BASE/tls-client/src/main/resources/servers-trust.crt" | wc -l
echo "certificates in bundle"
