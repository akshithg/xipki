# Builder stage
FROM maven:3.9.6-eclipse-temurin-17 AS builder

WORKDIR /workspace
COPY . .

# Build the project
# Skip tests to speed up build
RUN mvn clean install -DskipTests

# Runtime stage
FROM tomcat:10.1-jdk17

WORKDIR /usr/local/tomcat

# Install dependencies
RUN apt-get update && \
    apt-get install -y unzip netcat-openbsd && \
    rm -rf /var/lib/apt/lists/*

# Copy the built zip file and gateway WAR
COPY --from=builder /workspace/assemblies/xipki-ca/target/xipki-ca-*.zip .
COPY --from=builder /workspace/assemblies/xipki-gateway/target/webapps/gateway-servlet5.war webapps/gateway.war

# Copy gateway configurations
COPY gateway.json xipki/etc/
COPY acme-gateway.json xipki/etc/
COPY acme-db.properties xipki/etc/acme/database/

# Copy CA configuration and init script
COPY ca-conf.json xipki/etc/ca/
COPY init-ca.sh .

# Unzip and organize
# The zip contains:
# tomcat/bin/setenv.sh
# tomcat/lib/*.jar
# tomcat/xipki/...
# tomcat10on/conf/catalina.properties
# tomcat10on/webapps/ca.war
RUN unzip xipki-ca-*.zip && \
    # Move common files
    cp -r xipki-ca-*/tomcat/bin/* bin/ && \
    cp -r xipki-ca-*/tomcat/lib/* lib/ && \
    # Move xipki config directory to /usr/local/tomcat/xipki
    cp -r xipki-ca-*/tomcat/xipki . && \
    # Move Tomcat 10 specific files
    cp xipki-ca-*/tomcat10on/conf/catalina.properties conf/ && \
    cp xipki-ca-*/tomcat10on/webapps/ca.war webapps/ && \
    # Cleanup extracted archive remains
    rm -rf xipki-ca-* xipki-ca-*.zip && \
    # Expand gateway WAR to allow direct injection of ACME config
    cd webapps && mkdir gateway && cd gateway && jar -xf ../gateway.war && rm ../gateway.war && \
    # Place gateway and ACME configs onto classpath
    mkdir -p WEB-INF/classes && \
    cp /usr/local/tomcat/xipki/etc/gateway.json WEB-INF/classes/ && \
    cp /usr/local/tomcat/xipki/etc/acme-gateway.json WEB-INF/classes/

# Configure Database
# Config files are now in xipki/etc/ca/database
RUN cd xipki/etc/ca/database && \
    sed -i 's/localhost:3306/xipki-db:3306/g' ca-db.properties && \
    sed -i 's/dataSource.user = root/dataSource.user = xipki/g' ca-db.properties && \
    sed -i 's/dataSource.password = 123456/dataSource.password = xipkipw/g' ca-db.properties && \
    # Also configure caconf-db.properties
    sed -i 's/localhost:3306/xipki-db:3306/g' caconf-db.properties && \
    sed -i 's/dataSource.user = root/dataSource.user = xipki/g' caconf-db.properties && \
    sed -i 's/dataSource.password = 123456/dataSource.password = xipkipw/g' caconf-db.properties && \
    # Disable remote management to avoid missing keycerts error
    sed -i '/"remoteMgmt":{/,/}/ s/"enabled":true/"enabled":false/' ../ca.json

# Ensure scripts are executable
RUN chmod +x bin/*.sh init-ca.sh

# Expose ports
EXPOSE 8080 8443

# Entrypoint
COPY docker-entrypoint.sh .
RUN chmod +x docker-entrypoint.sh

# Generate dummy PKCS12 keystore and truststore for gateway SSL config
RUN mkdir -p xipki/etc/keystore && \
    keytool -genkeypair -alias gateway -keyalg RSA -keysize 2048 -validity 3650 \
        -dname "CN=Gateway,O=XiPKI,L=Test,ST=Test,C=US" \
        -storetype PKCS12 -keystore xipki/etc/keystore/gateway.p12 \
        -storepass changeit -keypass changeit && \
    keytool -exportcert -alias gateway -keystore xipki/etc/keystore/gateway.p12 \
        -storepass changeit -rfc > /tmp/gateway.crt && \
    keytool -importcert -noprompt -alias gateway -file /tmp/gateway.crt \
        -storetype PKCS12 -keystore xipki/etc/keystore/gateway-trust.p12 \
        -storepass changeit && \
    rm /tmp/gateway.crt

CMD ["./docker-entrypoint.sh"]
