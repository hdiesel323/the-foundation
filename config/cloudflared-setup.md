# Cloudflare Tunnel Setup Guide

## Prerequisites

- Cloudflare account with a domain configured
- Cloudflare Zero Trust dashboard access

## 1. Create the Tunnel

1. Log in to [Cloudflare Zero Trust](https://one.dash.cloudflare.com)
2. Navigate to **Networks > Tunnels**
3. Click **Create a tunnel**
4. Select **Cloudflared** connector type
5. Name the tunnel: `openclaw-tunnel`
6. Copy the tunnel token

## 2. Save the Token

```bash
# Save the tunnel token (replace with your actual token)
echo "eyJ..." > secrets/cf_tunnel_token.txt
chmod 600 secrets/cf_tunnel_token.txt

# Also update .env
# CF_TUNNEL_TOKEN=eyJ...
```

## 3. Configure Public Hostnames

In the Cloudflare Zero Trust dashboard, add these public hostname routes for your tunnel:

| Public Hostname               | Service                  | Purpose                        |
|-------------------------------|--------------------------|--------------------------------|
| `openclaw.yourdomain.com`     | `http://openclaw:8080`   | Main Gateway (Seldon Protocol) |
| `grafana.yourdomain.com`      | `http://grafana:3000`    | Dashboards (debug/admin only)  |

### How to Add Hostnames

1. In the tunnel configuration, click **Public Hostname** tab
2. Click **Add a public hostname**
3. For the main gateway:
   - Subdomain: `openclaw`
   - Domain: select your domain
   - Type: `HTTP`
   - URL: `openclaw:8080`
4. For Grafana (optional):
   - Subdomain: `grafana`
   - Domain: select your domain
   - Type: `HTTP`
   - URL: `grafana:3000`

## 4. Cloudflare Access Policy (Zero-Trust Auth)

Cloudflare Access enforces authentication at the edge — requests are blocked by Cloudflare
before they ever reach the VPS. Combined with the tunnel (no open ports), this gives full
zero-trust access: **Cloudflare Tunnel + Cloudflare Access = zero exposed ports on the VPS.**

### Authentication Method: Email-Only

Access uses **email-based authentication only**. No passwords, no OAuth providers, no SSO.
Cloudflare sends a one-time code to the allowed email address. This is the simplest and
most secure method for a single-admin system.

### Create the Access Application

1. Navigate to **Access > Applications** in the Zero Trust dashboard
2. Click **Add an application** > **Self-hosted**
3. Configure the application:
   - Application name: `OpenClaw`
   - Application domain: `openclaw.yourdomain.com`
   - (Optional) Add `grafana.yourdomain.com` as an additional hostname

### Create the "Only Me" Policy

4. Add an access policy:
   - Policy name: **`Only Me`**
   - Action: **Allow**
   - Include rule: **Emails** — enter your admin email address
   - No other rules needed. This restricts access to a single email address.
5. Session duration: **24 hours**
   - After 24 hours, Cloudflare re-prompts for email verification.

### Repeat for Grafana (If Configured)

6. If `grafana.yourdomain.com` is exposed via the tunnel, create a second application:
   - Application name: `OpenClaw Grafana`
   - Application domain: `grafana.yourdomain.com`
   - Same **"Only Me"** policy: email-only, your admin email, 24-hour session

### Access Policy Summary

| Setting              | Value                          |
|----------------------|--------------------------------|
| Policy Name          | `Only Me`                      |
| Auth Method          | Email-only (one-time code)     |
| Allowed Email        | Your admin email address       |
| Session Duration     | 24 hours                       |
| Protected Hostnames  | `openclaw.yourdomain.com`, optionally `grafana.yourdomain.com` |

## 5. Docker Compose Service

The cloudflared service is already configured in `docker-compose.yml`:

```yaml
cloudflared:
  image: cloudflare/cloudflared:latest
  container_name: openclaw-tunnel
  restart: unless-stopped
  command: tunnel run
  environment:
    TUNNEL_TOKEN: ${CF_TUNNEL_TOKEN}
  networks:
    - openclaw-net
  depends_on:
    - openclaw
```

The `CF_TUNNEL_TOKEN` is loaded from `.env`.

## 6. Verify

```bash
# Start the tunnel
docker compose up -d cloudflared

# Check status
docker compose ps cloudflared

# Check logs for successful connection
docker compose logs cloudflared --tail 20
# Should show: "Connection registered" and "Registered tunnel connection"
```

## Security Notes — Zero-Trust Architecture

- **Zero exposed ports**: No inbound ports open on the VPS. All external access goes through
  the Cloudflare Tunnel. `ufw` firewall blocks all incoming connections.
- **Cloudflare Tunnel + Access = zero-trust**: The tunnel provides encrypted connectivity
  without opening ports. Access enforces email-only authentication at the Cloudflare edge
  before any request reaches the VPS.
- **No direct access possible**: Even knowing the VPS IP address is insufficient — there are
  no listening ports to connect to. All traffic must flow through Cloudflare.
- Tunnel token should be rotated annually (see secrets rotation schedule).
- All secret files should be `chmod 600`, owned by the `openclaw` user.
