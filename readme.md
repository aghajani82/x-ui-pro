# XUI-PRO

![XUI-PRO Logo](https://raw.githubusercontent.com/GFW4Fun/x-ui-pro/master/media/XUI_Pro_Logo.png)

A simplified and maintained server installation script for deploying:

- Nginx
- Let's Encrypt SSL
- 3x-UI
- Xray
- Reverse-proxy based subscription service

The current version focuses on a clean, predictable, and easy-to-maintain installation flow for Ubuntu servers.

---

## About This Project

This repository is a maintained and customized fork of the original **x-ui-pro** project.

The current version has been simplified and modified to focus on the core deployment stack:

```text
Internet
   │
   ▼
 Nginx
   │
   ├── HTTPS / TLS
   ├── 3x-UI Panel
   ├── Subscription Service
   └── Xray Traffic Paths
```

Several components and features found in older versions of the project are intentionally excluded from the current main installation flow.

The goal is to keep the installer easier to understand, easier to troubleshoot, and more predictable on a fresh server.

---

# Current Scope

The current installer deploys and configures:

- Nginx
- Let's Encrypt
- Certbot
- 3x-UI
- Xray
- Subscription service
- Nginx reverse proxy
- Automatic certificate renewal

The current 3x-UI version is pinned to:

```text
v3.7.0
```

---

# Supported Environment

The primary tested environment is:

```text
Ubuntu 24.04
```

The installer checks the operating system before continuing.

Other Ubuntu versions may work, but Ubuntu 24.04 is the main tested target.

---

# Installation

## Recommended Installation Method

The recommended installation method is to download the installer first.

### 1. Download the installer

```bash
curl -fsSL https://raw.githubusercontent.com/aghajani82/x-ui-pro/master/x-ui-pro.sh -o /root/x-ui-pro.sh
```

### 2. Verify the downloaded file

```bash
ls -lh /root/x-ui-pro.sh
```

### 3. Run the installer

```bash
bash /root/x-ui-pro.sh -subdomain web.example.com
```

Replace:

```text
web.example.com
```

with your own domain.

For example:

```bash
bash /root/x-ui-pro.sh -subdomain blog.example.com
```

---

## One-Line Installation

The installer can also be downloaded and executed directly:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/aghajani82/x-ui-pro/master/x-ui-pro.sh) -subdomain blog.example.com
```

For production systems, downloading the script first is recommended because it leaves a local copy that can be inspected or reused for troubleshooting.

---

# Before Installation

Make sure the following requirements are satisfied.

### Ubuntu Server

The primary target is:

```text
Ubuntu 24.04
```

### Domain DNS

Your domain must already point to the server.

Example:

```text
blog.example.com → SERVER_IP
```

### Port 80

Port `80/tcp` must be reachable from the Internet because Let's Encrypt uses it during certificate issuance.

### Root Access

The installer must be executed as `root`.

Check your current user:

```bash
whoami
```

Expected output:

```text
root
```

---

# Installation Flow

The installer follows this process:

```text
1. Check root privileges
2. Detect Ubuntu
3. Validate the domain
4. Check DNS → server IP
5. Install required packages
6. Configure Nginx
7. Request Let's Encrypt certificate
8. Install 3x-UI v3.7.0
9. Detect the generated 3x-UI panel port
10. Configure the subscription service
11. Configure Nginx reverse proxy
12. Enable required services
13. Enable Certbot renewal
14. Run final verification checks
```

---

# Nginx Architecture

Nginx acts as the public entry point.

```text
                     Internet
                        │
              ┌─────────┴─────────┐
              │                   │
             :80                 :443
              │                   │
              └─────────┬─────────┘
                        │
                      Nginx
                        │
          ┌─────────────┼─────────────┐
          │             │             │
       3x-UI        Subscription     Xray
        Panel          Service       Paths
```

Public access is handled through:

```text
HTTP  → :80
HTTPS → :443
```

HTTP traffic is redirected to HTTPS after the SSL certificate is installed.

The panel and subscription service are configured to remain on localhost where possible, with Nginx handling public access.

---

# SSL / Let's Encrypt

The installer automatically requests a Let's Encrypt certificate for the supplied domain.

Certificates are stored under:

```text
/etc/letsencrypt/live/<DOMAIN>/
```

Typical certificate files include:

```text
fullchain.pem
privkey.pem
```

Example:

```text
/etc/letsencrypt/live/blog.example.com/fullchain.pem
/etc/letsencrypt/live/blog.example.com/privkey.pem
```

The installer uses the Nginx webroot method for ACME validation.

---

# Automatic Certificate Renewal

Certbot renewal is enabled through the systemd timer:

```text
certbot.timer
```

Check the timer with:

```bash
systemctl status certbot.timer
```

You can also test the renewal process without actually renewing the certificate:

```bash
certbot renew --dry-run
```

---

# 3x-UI

The current installer installs:

```text
3x-UI v3.7.0
```

The version is intentionally pinned to provide a predictable installation environment.

The installation is performed using the official 3x-UI installer.

The 3x-UI database is stored at:

```text
/etc/x-ui/x-ui.db
```

The installer detects the generated panel configuration and uses the detected panel port when configuring Nginx.

---

# Panel Access

The final panel address follows this structure:

```text
https://<DOMAIN>/<PANEL_PATH>
```

The exact panel path is determined from the installed 3x-UI configuration.

The installer prints the final panel URL when installation completes.

Example:

```text
Panel:         https://blog.example.com/<panel-path>
```

---

# Subscription Service

The subscription service is configured to listen locally on:

```text
127.0.0.1:2096
```

The public subscription endpoint is exposed through Nginx.

Primary subscription URL:

```text
https://<DOMAIN>/2096/sub/
```

The installer also supports:

```text
https://<DOMAIN>/sub/
```

Nginx terminates TLS and forwards the request to the local subscription service.

Simplified flow:

```text
Client
  │
  ▼
HTTPS :443
  │
  ▼
Nginx
  │
  ▼
127.0.0.1:2096
  │
  ▼
Subscription Service
```

---

# Xray

Xray is managed by 3x-UI.

The installer configures Nginx as the public reverse proxy for the Xray paths.

Simplified traffic flow:

```text
Client
  │
  ▼
HTTPS :443
  │
  ▼
Nginx
  │
  ▼
Xray local listener
```

This allows the public service to use the standard HTTPS port:

```text
443/tcp
```

while the Xray service remains behind the Nginx reverse proxy.

---

# Firewall

The main installation script does **not** automatically modify UFW.

This is intentional.

The installer does not automatically:

- change the SSH port
- enable or disable UFW
- remove firewall rules
- rewrite an existing firewall configuration

This prevents the installer from unexpectedly changing an existing server's security configuration.

At minimum, the server normally needs:

```text
80/tcp
443/tcp
```

Your SSH port must also remain accessible.

---

# Command-Line Options

The primary installation option is:

```text
-subdomain DOMAIN
```

Example:

```bash
bash /root/x-ui-pro.sh -subdomain blog.example.com
```

The following compatibility options are also accepted:

```text
-panel
-xuiver
-cdn
-secure
-country
```

These options are retained mainly for compatibility with older versions of the project.

The current installer follows its own fixed installation design.

For example, the 3x-UI version remains:

```text
v3.7.0
```

---

# Help

Display the installer's built-in help:

```bash
bash /root/x-ui-pro.sh --help
```

---

# Installed Components

A successful installation provides the following major components:

```text
Nginx
Let's Encrypt
Certbot
3x-UI
Xray
SQLite
```

Important configuration locations include:

```text
/etc/nginx/
/etc/letsencrypt/
/etc/x-ui/
```

The 3x-UI database is located at:

```text
/etc/x-ui/x-ui.db
```

---

# Verification

After installation, the following checks can be used to verify the services.

## Nginx Configuration

```bash
nginx -t
```

Expected result:

```text
syntax is ok
test is successful
```

## Nginx Service

```bash
systemctl is-active nginx
```

Expected:

```text
active
```

## 3x-UI Service

```bash
systemctl is-active x-ui
```

Expected:

```text
active
```

## Certbot Timer

```bash
systemctl is-active certbot.timer
```

Expected:

```text
active
```

## 3x-UI Database

```bash
ls -lh /etc/x-ui/x-ui.db
```

The database file should exist after a successful installation.

---

# Final Installation Output

A successful installation ends with output similar to:

```text
Installation completed.

Domain:        blog.example.com
Panel:         https://blog.example.com/<panel-path>
Subscription:  https://blog.example.com/2096/sub/
Panel port:    <local-port> (localhost via Nginx)
Sub port:      2096 (localhost)
Xray:          managed by 3x-UI
```

The exact panel path and panel port depend on the configuration generated during installation.

---

# Project Philosophy

The current version intentionally keeps the main installer focused.

The core deployment stack is:

```text
Nginx
   +
Let's Encrypt
   +
3x-UI
   +
Xray
   +
Subscription Service
```

The project avoids placing unrelated server-management features inside the main installation flow.

This keeps the installer:

- easier to understand
- easier to maintain
- easier to troubleshoot
- less likely to modify unrelated server configuration

---

# Fork / Credits

This repository is based on previous open-source work in the XUI ecosystem and has been substantially customized and simplified for the current installation flow.

Special thanks to the developers and maintainers of the projects that make this stack possible, including:

- 3x-UI
- Xray
- Nginx
- Let's Encrypt
- Certbot
- SQLite
- Previous x-ui-pro contributors

The current repository is maintained and modified by:

**aghajani82**

---

# Disclaimer

This project is provided as-is.

Always review installation scripts before running them on production servers.

Make sure your:

- DNS configuration
- SSH access
- firewall rules
- server backups

are properly configured before making changes to a production environment.

---

# License

See the repository and upstream projects for the applicable licenses and attribution requirements.
