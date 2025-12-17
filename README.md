# OpenVPN UI

Simple web UI to manage OpenVPN users, their certificates & routes.

## Features

- Add, delete, revoke/restore OpenVPN users
- Generate ready-to-use client config files
- Rotate user certificates
- Client-config-dir (CCD) support for static IPs and custom routes
- Optional password authentication for OpenVPN
- Built-in web authentication
- Let's Encrypt HTTPS support

## Installation

```bash
curl -Ls https://raw.githubusercontent.com/oranguthang/openvpn_ui/main/install.sh | sudo bash
```

The script will:
- Check for Docker and Docker Compose
- Generate random admin credentials
- Select an available random port for web UI
- Optionally configure HTTPS with Let's Encrypt
- Start the containers
- Print access credentials

## Management

```bash
cd /opt/openvpn-ui

# View logs
sudo docker compose logs -f

# Restart
sudo docker compose restart

# Stop
sudo docker compose down

# Uninstall
sudo bash install.sh uninstall
```

## Requirements

- Linux server with root access
- Docker and Docker Compose
- Port 1194 (OpenVPN) available
- Port 80/443 available if using Let's Encrypt

## License

MIT
