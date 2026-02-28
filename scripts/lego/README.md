# Lego Certificate Acquisition Workflow

This directory contains the scripts and systemd units for the first stage of the certificate management system: acquiring certificates from Let's Encrypt and uploading them to Infisical.

This process is designed to run on a single, designated server (e.g., an Nginx reverse proxy container) that has access to the DNS provider's API.

## Overview

The workflow automates the following steps:
1.  **Certificate Request**: The `run.sh` script uses the `lego` ACME client to request a certificate for the specified domains (including wildcards).
2.  **DNS-01 Challenge**: It performs a DNS-01 challenge using the Porkbun DNS provider. This requires Porkbun API credentials.
3.  **Certificate Storage**: Certificates are stored locally in a standard Let's Encrypt directory structure.
4.  **Infisical Upload**: Upon successful renewal, the `run.sh` script calls `upload-cert.sh` to push the new certificate and private key to a designated Infisical project.
5.  **Service Reload**: Finally, it reloads relevant services like Nginx to apply the new certificate.

This centralized approach solves the challenge of distributing certificates by making a single, trusted source (Infisical) available to all clients in the Yggdrasil network.

## Setup

1.  **Placement**: Copy the contents of this `lego` directory to a suitable location on your certificate management server. A recommended path is `/etc/letsencrypt/gour.top/lego`.
2.  **Configuration**:
    -   Edit `run.sh` and configure the variables at the top, including `LEGO_ACCOUNT_EMAIL`, `DOMAINS_TO_CERTIFY`, and `LEGO_STORAGE_PATH`.
    -   Set your Porkbun API credentials (`PORKBUN_SECRET_API_KEY` and `PORKBUN_API_KEY`) as environment variables. For better security, it is highly recommended to use a systemd `EnvironmentFile` instead of exporting them directly in the script.
3.  **Systemd Integration**:
    -   Copy the `lego-gour-top.service` and `lego-gour-top.timer` files to `/etc/systemd/system/`.
    -   Review the paths in the service file to ensure they match your setup.
    -   Enable and start the timer:
        ```bash
        sudo systemctl enable --now lego-gour-top.timer
        ```

## File Descriptions

-   `run.sh`: The main execution script that handles the entire certificate renewal and upload process.
-   `upload-cert.sh`: A helper script called by `run.sh` to upload certificate files to Infisical.
-   `lego-gour-top.service`: A systemd service unit that runs `run.sh`.
-   `lego-gour-top.timer`: A systemd timer that triggers the service periodically to ensure certificates are always up-to-date.

## Example Directory Structure

After a successful run, your directory structure on the certificate server might look like this:

```
/etc/letsencrypt/
└── gour.top
    ├── accounts/
    ├── certificates/
    │   ├── gour.top.crt
    │   ├── gour.top.fullchain.pem
    │   ├── gour.top.issuer.crt
    │   ├── gour.top.json
    │   └── gour.top.key
    └── lego/
        ├── lego
        ├── lego-gour-top.service
        ├── lego-gour-top.timer
        └── run.sh
```