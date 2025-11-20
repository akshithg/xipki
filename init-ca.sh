#!/bin/bash
set -e

echo "Initializing XiPKI CA..."

# Wait for Tomcat to be fully started
echo "Waiting for Tomcat to start..."
for i in {1..30}; do
  if curl --silent --fail http://localhost:8080/ca/rest >/dev/null 2>&1; then
    echo "Tomcat is ready"
    break
  fi
  echo "Waiting for Tomcat... ($i/30)"
  sleep 2
done

# Generate CA key pair (EC key for simplicity)
echo "Generating CA keypair..."
mkdir -p /usr/local/tomcat/xipki/keycerts

if [ ! -f /usr/local/tomcat/xipki/keycerts/myca1.p12 ]; then
  # Use openssl to generate an EC key and convert to P12
  openssl ecparam -genkey -name prime256v1 -out /tmp/ca-key.pem
  openssl req -new -x509 -key /tmp/ca-key.pem -out /tmp/ca-cert.pem -days 3650 \
    -subj "/CN=MyCA1/O=XiPKI Demo"
  openssl pkcs12 -export -out /usr/local/tomcat/xipki/keycerts/myca1.p12 \
    -inkey /tmp/ca-key.pem -in /tmp/ca-cert.pem -password pass:1234
  rm /tmp/ca-key.pem /tmp/ca-cert.pem
  echo "CA keypair generated"
else
  echo "CA keypair already exists, skipping generation"
fi

# Load CA configuration via REST API
echo "Loading CA configuration..."
curl -X POST http://localhost:8080/ca/rest/v1/ca-conf \
  -H "Content-Type: application/json" \
  -d @/usr/local/tomcat/xipki/etc/ca/ca-conf.json \
  --fail --silent --show-error || echo "CA configuration may already be loaded"

echo "XiPKI CA initialization complete"
