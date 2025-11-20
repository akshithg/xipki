# XiPKI Docker Deployment (CA + ACME Gateway)

Developer-focused guide to stand up a working XiPKI CA plus ACME gateway via Docker. This replaces multi‑Tomcat manual steps with a single reproducible composition suitable for local development and test automation.

## What the Image Does

1. Builds XiPKI assemblies with Maven (tests skipped for speed).
2. Expands `xipki-ca` to obtain Tomcat libs and the `xipki` runtime tree.
3. Deploys the gateway servlet (`gateway-servlet5.war` -> `gateway.war`).
4. Copies configuration: `gateway.json`, `acme-gateway.json`, `acme-db.properties`, `ca-conf.json`.
5. Generates a demo PKCS#12 keystore for the gateway client.
6. Initializes MariaDB schemas (CA / CACONF / OCSP / ACME) via one SQL script.
7. Runs `init-ca.sh` to bootstrap CA (myca1) and keypair.
8. Starts Tomcat and the ACME gateway.

## Core Configuration Files

`acme-db.properties` (must use `jdbcUrl`, `username`, `password` for ACME):

```properties
jdbcUrl = jdbc:mariadb://xipki-db:3306/acme
username = xipki
password = xipkipw
```

`acme-gateway.json` points to `etc/acme/database/acme-db.properties`.
`gateway.json` enables only ACME (other protocols disabled).
`docker-mariadb-init.sql` embeds required tables (ACCOUNT, ORDER2, DBSCHEMA) so no separate `ca:sql acme-init.sql` run is needed.

## Run & Smoke Test

Start services:

```sh
docker compose up -d xipki-db xipki-ca
```

Verify ACME endpoints:

```sh
curl -s http://localhost:8080/gateway/acme/directory | jq .
curl -I http://localhost:8080/gateway/acme/newNonce
```

Successful directory output lists `newNonce`, `newAccount`, `newOrder`, `revokeCert`, `keyChange`, and a `meta` block.

## Troubleshooting

| Symptom | Cause | Resolution |
|---------|-------|------------|
| `error starting ACME gateway, could not initialize database` | Wrong property keys or missing ACME tables | Use `jdbcUrl / username / password`; ensure ACCOUNT, ORDER2, DBSCHEMA exist in `acme` DB |
| Hikari driver class load failure | Forced `driverClassName` with mismatched driver protocol | Remove `driverClassName`; rely on `jdbc:mariadb://` auto driver detection |
| 404 on `/gateway/acme/directory` | Gateway servlet not deployed or ACME disabled | Confirm `gateway.war` present and `"acme": true` in `gateway.json` |
| Empty / truncated JSON | Incorrect `baseUrl` in `acme-gateway.json` | Set `baseUrl` to `http://localhost:8080/gateway/acme/` (trailing slash) |
| Connection timeout to DB | DB not ready when Tomcat starts | Ensure entrypoint waits for `xipki-db:3306` before starting Tomcat |

## Notes

This setup is for local development only (plaintext passwords, single Tomcat). For production, split CA and Gateway into separate containers and harden credentials.
