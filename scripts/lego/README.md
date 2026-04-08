# Lego Certificate Acquisition Workflow

This directory contains the scripts and systemd units for the first stage of the certificate management system: acquiring certificates from Let's Encrypt and uploading them to Infisical.

This process is designed to run on a single, designated server that has access to the DNS provider's API.

## Overview

The workflow automates the following steps:
1.  **Certificate Request**: The `run.sh` script uses the `lego` ACME client to request a certificate for the specified domains (including wildcards).
2.  **DNS-01 Challenge**: It performs a DNS-01 challenge using the configured DNS provider. This requires the provider API credentials.
3.  **Certificate Storage**: Certificates are stored locally in a standard Let's Encrypt directory structure.
4.  **Infisical Upload**: Upon successful renewal, the `run.sh` script calls `upload-cert.sh` to push the new certificate and private key to a designated Infisical project.
5.  **Service Reload**: Finally, it reloads relevant services like Nginx to apply the new certificate.

This centralized approach solves the challenge of distributing certificates by making a single, trusted source (Infisical) available to all clients in the Yggdrasil network.

## Setup

1.  **Placement**: Copy the contents of this `lego` directory to a suitable location on your certificate management server. A recommended path is `/opt/ygg/certs`.
2.  **Configuration**:
    -   Copy `config/certs.example.env` to `config/certs.local.env`.
    -   Fill `config/certs.local.env` with the real certificate, DNS-provider, and Infisical values.
    -   Never commit `config/certs.local.env`.
3.  **Systemd Integration**:
    -   Copy the `ygg-lego-cert.service` and `ygg-lego-cert.timer` files to `/etc/systemd/system/`.
    -   Review the paths in the service file to ensure they match your setup.
    -   Enable and start the timer:
        ```bash
        sudo systemctl enable --now ygg-lego-cert.timer
        ```

## File Descriptions

-   `run.sh`: The main execution script that handles the entire certificate renewal and upload process.
-   `upload-cert.sh`: A helper script called by `run.sh` to upload certificate files to Infisical.
-   `ygg-lego-cert.service`: A systemd service unit that runs `run.sh`.
-   `ygg-lego-cert.timer`: A systemd timer that triggers the service periodically to ensure certificates are always up-to-date.

## Secret Handling

The public repository must not contain:

- DNS-provider API keys
- Infisical machine tokens
- live project IDs copied from production

Keep those in `config/certs.local.env` for repo-local runs or in a root-owned environment file on the target machine.

## Example Directory Structure

After a successful run, your directory structure on the certificate server might look like this:

```
/etc/letsencrypt/
└── example.com
    ├── accounts/
    ├── certificates/
    │   ├── example.com.crt
    │   ├── example.com.fullchain.pem
    │   ├── example.com.issuer.crt
    │   ├── example.com.json
    │   └── example.com.key
    └── lego/
        ├── lego
        ├── ygg-lego-cert.service
        ├── ygg-lego-cert.timer
        ├── lego.local.env
        └── run.sh
```
