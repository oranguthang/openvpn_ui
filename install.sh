#!/bin/bash

# OpenVPN UI Installation Script
# Similar to 3x-ui install approach

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Installation directory
INSTALL_DIR="/opt/openvpn-ui"

print_banner() {
    echo -e "${CYAN}"
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║                                                           ║"
    echo "║              OpenVPN UI Installation Script               ║"
    echo "║                                                           ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_info() {
    echo -e "${BLUE}[i]${NC} $1"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root"
        exit 1
    fi
}

# Check dependencies
check_dependencies() {
    print_info "Checking dependencies..."

    local missing=()

    if ! command -v docker &> /dev/null; then
        missing+=("docker")
    fi

    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
        missing+=("docker-compose")
    fi

    if [ ${#missing[@]} -ne 0 ]; then
        print_error "Missing dependencies: ${missing[*]}"
        print_info "Please install Docker and Docker Compose first"
        print_info "Run: curl -fsSL https://get.docker.com | sh"
        exit 1
    fi

    print_success "All dependencies are installed"
}

# Generate random string
generate_random() {
    local length=$1
    tr -dc 'a-zA-Z0-9' < /dev/urandom | fold -w "$length" | head -n 1
}

# Generate random port
generate_random_port() {
    local min=10000
    local max=65000
    local port

    while true; do
        port=$((RANDOM % (max - min + 1) + min))
        # Check if port is available
        if ! ss -tuln | grep -q ":$port "; then
            echo "$port"
            return
        fi
    done
}

# Get server public IP
get_public_ip() {
    local ip=""

    # Try multiple services
    for service in "https://api.ipify.org" "https://ident.me" "https://ifconfig.me" "https://icanhazip.com"; do
        ip=$(curl -s --max-time 5 "$service" 2>/dev/null)
        if [[ $ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo "$ip"
            return
        fi
    done

    # Fallback to local detection
    ip=$(hostname -I | awk '{print $1}')
    echo "$ip"
}

# Main installation
install() {
    print_banner
    check_root
    check_dependencies

    echo ""
    print_info "Starting installation..."
    echo ""

    # Create installation directory
    mkdir -p "$INSTALL_DIR"
    cd "$INSTALL_DIR"

    # Generate credentials
    ADMIN_USER=$(generate_random 10)
    ADMIN_PASS=$(generate_random 16)
    WEB_PORT=$(generate_random_port)
    OVPN_PORT=1194
    SERVER_IP=$(get_public_ip)

    print_info "Generated admin username: $ADMIN_USER"
    print_info "Generated admin password: $ADMIN_PASS"
    print_info "Generated web UI port: $WEB_PORT"

    # Ask for domain (optional, for Let's Encrypt)
    echo ""
    echo -e "${YELLOW}Do you want to configure HTTPS with Let's Encrypt?${NC}"
    echo -e "Enter your domain (e.g., vpn.example.com) or press Enter to skip:"
    read -r DOMAIN

    if [ -n "$DOMAIN" ]; then
        print_info "Domain configured: $DOMAIN"
        print_warning "Make sure DNS A record points to this server!"
    else
        print_info "HTTPS disabled (no domain specified)"
    fi

    # Create .env file
    print_info "Creating configuration..."

    cat > "$INSTALL_DIR/.env" << EOF
# OpenVPN UI Configuration
# Generated on $(date)

ADMIN_USERNAME=$ADMIN_USER
ADMIN_PASSWORD=$ADMIN_PASS
WEB_PORT=$WEB_PORT
DOMAIN=$DOMAIN

# OpenVPN settings
OVPN_SERVER_NET=10.8.0.0
OVPN_SERVER_MASK=255.255.255.0
OVPN_SERVER_PORT=$OVPN_PORT

# Timezone
TZ=UTC
EOF

    chmod 600 "$INSTALL_DIR/.env"
    print_success "Configuration created"

    # Download or copy docker-compose.yml if not exists
    if [ ! -f "$INSTALL_DIR/docker-compose.yml" ]; then
        # If running from repo, copy files
        if [ -f "$(dirname "$0")/docker-compose.yml" ]; then
            cp "$(dirname "$0")/docker-compose.yml" "$INSTALL_DIR/"
            cp "$(dirname "$0")/Dockerfile" "$INSTALL_DIR/"
            cp -r "$(dirname "$0")/backend" "$INSTALL_DIR/"
            cp -r "$(dirname "$0")/frontend" "$INSTALL_DIR/"
            cp -r "$(dirname "$0")/setup" "$INSTALL_DIR/"
            cp -r "$(dirname "$0")/templates" "$INSTALL_DIR/"
            cp "$(dirname "$0")/docker-entrypoint.sh" "$INSTALL_DIR/"
        else
            print_error "docker-compose.yml not found. Please run from the project directory."
            exit 1
        fi
    fi

    # Create data directories
    mkdir -p "$INSTALL_DIR/data/easyrsa"
    mkdir -p "$INSTALL_DIR/data/ccd"
    mkdir -p "$INSTALL_DIR/data/config"

    # Build and start containers
    print_info "Building Docker images (this may take a few minutes)..."
    docker compose build --quiet

    print_info "Starting containers..."
    docker compose up -d

    # Wait for services to start
    print_info "Waiting for services to start..."
    sleep 10

    # Check if running
    if docker compose ps | grep -q "Up"; then
        print_success "OpenVPN UI is running!"
    else
        print_error "Failed to start containers. Check logs with: docker compose logs"
        exit 1
    fi

    # Print final info
    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}           OpenVPN UI Successfully Installed!              ${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
    echo ""

    if [ -n "$DOMAIN" ]; then
        echo -e "  ${CYAN}Panel URL:${NC}     https://$DOMAIN:$WEB_PORT"
    else
        echo -e "  ${CYAN}Panel URL:${NC}     http://$SERVER_IP:$WEB_PORT"
    fi
    echo -e "  ${CYAN}Username:${NC}      $ADMIN_USER"
    echo -e "  ${CYAN}Password:${NC}      $ADMIN_PASS"
    echo ""
    echo -e "  ${CYAN}OpenVPN Port:${NC}  $OVPN_PORT (TCP/UDP)"
    echo -e "  ${CYAN}Install Dir:${NC}   $INSTALL_DIR"
    echo ""
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}  IMPORTANT: Save these credentials securely!              ${NC}"
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "Management commands:"
    echo -e "  ${BLUE}cd $INSTALL_DIR && docker compose logs -f${NC}     # View logs"
    echo -e "  ${BLUE}cd $INSTALL_DIR && docker compose restart${NC}     # Restart"
    echo -e "  ${BLUE}cd $INSTALL_DIR && docker compose down${NC}        # Stop"
    echo ""
}

# Uninstall function
uninstall() {
    print_banner
    check_root

    print_warning "This will remove OpenVPN UI and all data!"
    echo -n "Are you sure? (y/N): "
    read -r confirm

    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        print_info "Uninstall cancelled"
        exit 0
    fi

    cd "$INSTALL_DIR" 2>/dev/null || true

    # Stop and remove containers
    if [ -f "$INSTALL_DIR/docker-compose.yml" ]; then
        print_info "Stopping containers..."
        docker compose down -v 2>/dev/null || true
    fi

    # Remove installation directory
    if [ -d "$INSTALL_DIR" ]; then
        print_info "Removing installation directory..."
        rm -rf "$INSTALL_DIR"
    fi

    print_success "OpenVPN UI has been uninstalled"
}

# Update function
update() {
    print_banner
    check_root

    if [ ! -d "$INSTALL_DIR" ]; then
        print_error "OpenVPN UI is not installed"
        exit 1
    fi

    cd "$INSTALL_DIR"

    print_info "Updating OpenVPN UI..."

    # Pull latest changes (if git repo) or rebuild
    docker compose build --pull --quiet
    docker compose up -d

    print_success "OpenVPN UI has been updated"
}

# Show status
status() {
    print_banner

    if [ ! -d "$INSTALL_DIR" ]; then
        print_error "OpenVPN UI is not installed"
        exit 1
    fi

    cd "$INSTALL_DIR"

    print_info "Container status:"
    docker compose ps

    echo ""
    print_info "Resource usage:"
    docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}"
}

# Show help
show_help() {
    print_banner
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  install     Install OpenVPN UI (default)"
    echo "  uninstall   Remove OpenVPN UI and all data"
    echo "  update      Update to the latest version"
    echo "  status      Show container status"
    echo "  help        Show this help message"
    echo ""
}

# Main
case "${1:-install}" in
    install)
        install
        ;;
    uninstall)
        uninstall
        ;;
    update)
        update
        ;;
    status)
        status
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        print_error "Unknown command: $1"
        show_help
        exit 1
        ;;
esac
