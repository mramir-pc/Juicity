#!/bin/bash

# Variables
INSTALL_DIR="/root/juicity"
CONFIG_FILE="$INSTALL_DIR/config.json"
SERVICE_FILE="/etc/systemd/system/juicity.service"
JUICITY_SERVER="$INSTALL_DIR/juicity-server"

# Function to print characters with delay
print_with_delay() {
    text="$1"
    for ((i = 0; i < ${#text}; i++)); do
        echo -n "${text:$i:1}"
        sleep 0.1
    done
    echo
}

# Introduction animation
echo ""
print_with_delay "juicity-installer by mrAmirPc | @mramir-pc" 0.1
echo ""

# Install required packages
sudo apt-get update > /dev/null 2>&1
sudo apt-get install -y unzip jq uuid-runtime > /dev/null 2>&1

# Check for an existing installation
if [[ -d $INSTALL_DIR && -f $SERVICE_FILE ]]; then
    echo "Juicity installed :] "
    echo ""
    echo "1. Reinstall"
    echo ""
    echo "2. Change Port"
    echo ""
    echo "3. Change Domain"
    echo ""
    echo "4. Uninstall"
    echo ""
    read -p "Enter your choice (1/2/3/4): " choice

    case $choice in
        1)
	echo ""
            echo "Reinstalling..."
            sudo systemctl stop juicity
            sudo systemctl disable juicity > /dev/null 2>&1
            rm -rf $INSTALL_DIR
            rm -f $SERVICE_FILE
            ;;
        2)
	read -p "Enter new listen port: " PORT
	sed -i "s/\"listen\": \":.*\"/\"listen\": \":$PORT\"/" $CONFIG_FILE
	sudo systemctl restart juicity
	SHARE_LINK=$($JUICITY_SERVER generate-sharelink -c $CONFIG_FILE)
	echo "New Link: "
     	echo ""
        echo "$SHARE_LINK&allow_insecure=1#mramir-pc"
	echo ""
	exit 0
	;;
 	3)
  	read -p "Enter domain config : " DOMAIN_CONFIG
        echo ""
        openssl req -new -x509 -days 36500 -key "$INSTALL_DIR/private.key" -out "$INSTALL_DIR/fullchain.cer" -subj "/CN=$DOMAIN_CONFIG"
        SHARE_LINK=$($JUICITY_SERVER generate-sharelink -c $CONFIG_FILE)
	echo "New Link: "
     	echo ""
        echo "$SHARE_LINK#mramir-pc"
	echo ""
        exit 
	;;
        4)
            sudo systemctl stop juicity
            sudo systemctl disable juicity > /dev/null 2>&1
            rm -rf $INSTALL_DIR
            rm -f $SERVICE_FILE
            echo "Uninstalled successfully!"
            exit 0
            ;;
        *)
            echo "Invalid choice!"
            exit 1
            ;;
    esac
fi

# Detect Architecture
ARCH=$(uname -m)
BINARY_NAME="juicity-linux"

case "$ARCH" in
    "x86_64")
        BINARY_NAME+="-x86_64.zip"
        ;;
    "arm64")
        BINARY_NAME+="-arm64.zip"
        ;;
    "armv7")
        BINARY_NAME+="-armv7.zip"
        ;;
    "mips32")
        BINARY_NAME+="-mips32.zip"
        ;;
    "mips64")
        BINARY_NAME+="-mips64.zip"
        ;;
    "riscv64")
        BINARY_NAME+="-riscv64.zip"
        ;;
    "i686")
        BINARY_NAME+="-x86_32.zip"
        ;;
    *)
        echo "Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

LATEST_RELEASE_URL=$(curl --silent "https://api.github.com/repos/juicity/juicity/releases" | jq -r ".[0].assets[] | select(.name == \"$BINARY_NAME\") | .browser_download_url")

# Download and extract
mkdir -p $INSTALL_DIR
curl -sL $LATEST_RELEASE_URL -o "$INSTALL_DIR/juicity.zip"
unzip -q "$INSTALL_DIR/juicity.zip" -d $INSTALL_DIR

# Delete all files except juicity-server
find $INSTALL_DIR ! -name 'juicity-server' -type f -exec rm -f {} +

# Set permissions
chmod +x $JUICITY_SERVER

# Create config.json
echo ""
read -p "Enter listen port (or press enter to randomize between 10000 and 65535): " PORT
echo ""
[[ -z "$PORT" ]] && PORT=$((RANDOM % 55536 + 10000))

read -p "Enter password (or press Enter to generate random): " PASSWORD
echo ""
if [[ -z "$PASSWORD" ]]; then
    PASSWORD=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 8 | head -n 1)
    echo "Generated Password: $PASSWORD"
fi

read -p "Enter domain config ( or press Enter for speedtest.net ) : " DOMAIN_CONFIG
echo ""
if [[ -z "$DOMAIN_CONFIG" ]]; then
DOMAIN_CONFIG="www.speedtest.net"
echo "Domain: $DOMAIN_CONFIG"
fi

UUID=$(uuidgen)

# Generate keys
openssl ecparam -genkey -name prime256v1 -out "$INSTALL_DIR/private.key"
openssl req -new -x509 -days 36500 -key "$INSTALL_DIR/private.key" -out "$INSTALL_DIR/fullchain.cer" -subj "/CN=$DOMAIN_CONFIG"

cat > $CONFIG_FILE <<EOL
{
  "listen": ":$PORT",
  "users": {
    "$UUID": "$PASSWORD"
  },
  "certificate": "$INSTALL_DIR/fullchain.cer",
  "private_key": "$INSTALL_DIR/private.key",
  "congestion_control": "bbr",
  "log_level": "info"
}
EOL

# Create systemd service file
cat > $SERVICE_FILE <<EOL
[Unit]
Description=juicity-server Service
Documentation=https://github.com/juicity/juicity
After=network.target nss-lookup.target

[Service]
Type=simple
User=root
ExecStart=$JUICITY_SERVER run -c $CONFIG_FILE
StandardOutput=file:$INSTALL_DIR/juicity-server.log
StandardError=file:$INSTALL_DIR/juicity-server.log
Restart=on-failure
LimitNPROC=512
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOL

# Reload systemd, enable and start the service
sudo systemctl daemon-reload
sudo systemctl enable juicity > /dev/null 2>&1
sudo systemctl start juicity

# Modified share link output
SHARE_LINK=$($JUICITY_SERVER generate-sharelink -c $CONFIG_FILE)
echo ""
echo ""
echo "$SHARE_LINK#mramir-pc"
echo ""
echo ""
