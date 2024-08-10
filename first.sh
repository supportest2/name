#!/bin/bash

set -e  # Exit immediately if a command exits with a non-zero status.

# Prompt for user input
read -p "Enter the username: " USER
read -p "Enter the device name: " HOSTNAME
read -p "Enter the PIN (6 digits): " PIN
read -p "Enter the AUTH_COMMAND: " AUTH_COMMAND
read -p "Enter the desired resolutions (comma-separated, e.g., 1920x1080,1600x900,1366x768,1280x720): " RESOLUTIONS

# Set environment variables
export DEBIAN_FRONTEND=noninteractive
export USER=$USER
export PIN=$PIN
export HOSTNAME=$HOSTNAME
export AUTH_COMMAND=$AUTH_COMMAND

# Function to check if user exists and create if not
create_user_if_not_exists() {
    if id "$USER" &>/dev/null; then
        echo "User $USER already exists. Continuing with setup."
    else
        echo "User $USER does not exist. Creating user."
        adduser --disabled-password --gecos '' $USER
        mkhomedir_helper $USER
        adduser $USER sudo
        echo '%sudo ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers
        usermod -aG chrome-remote-desktop $USER
    fi
}

# Function to check if a package is installed
is_package_installed() {
    dpkg -s "$1" >/dev/null 2>&1
}

# Function to check and install Min browser
check_and_install_min_browser() {
    if ! is_package_installed min; then
        echo "Min browser is not installed. Installing now..."
        wget https://github.com/minbrowser/min/releases/download/v1.32.1/min-1.32.1-amd64.deb
        dpkg -i min-1.32.1-amd64.deb || apt-get -f install -y
        rm min-1.32.1-amd64.deb  # Clean up the downloaded .deb file
    else
        echo "Min browser is already installed."
    fi
}

# Update and upgrade system
apt-get update && apt-get upgrade --assume-yes

# Install basic utilities if not already installed
for pkg in curl gpg wget; do
    if ! is_package_installed $pkg; then
        apt-get --assume-yes install $pkg
    else
        echo "$pkg is already installed."
    fi
done

# Add Microsoft and Google repositories if not already added
if [ ! -f /etc/apt/trusted.gpg.d/microsoft.gpg ]; then
    curl https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > microsoft.gpg
    mv microsoft.gpg /etc/apt/trusted.gpg.d/microsoft.gpg
fi

if ! apt-key list | grep -q "Google Inc"; then
    wget -q -O - https://dl.google.com/linux/linux_signing_key.pub | apt-key add -
fi

if [ ! -f /etc/apt/sources.list.d/vs-code.list ]; then
    echo "deb [arch=amd64] http://packages.microsoft.com/repos/vscode stable main" | tee /etc/apt/sources.list.d/vs-code.list
fi

if [ ! -f /etc/apt/sources.list.d/google-chrome.list ]; then
    echo "deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main" >> /etc/apt/sources.list.d/google-chrome.list
fi

# Update package lists
apt-get update && apt-get upgrade --assume-yes

# Install XFCE Desktop and dependencies if not already installed
packages="sudo wget apt-utils xvfb xfce4 xfce4-terminal xbase-clients desktop-base vim xscreensaver google-chrome-stable python3-psutil psmisc xserver-xorg-video-dummy ffmpeg python3-packaging python3-xdg libutempter0"

for pkg in $packages; do
    if ! is_package_installed $pkg; then
        apt-get install --assume-yes --fix-missing $pkg
    else
        echo "$pkg is already installed."
    fi
done

# Install Min browser
check_and_install_min_browser

# Install Chrome Remote Desktop if not already installed
if ! is_package_installed chrome-remote-desktop; then
    wget https://dl.google.com/linux/direct/chrome-remote-desktop_current_amd64.deb
    dpkg --install chrome-remote-desktop_current_amd64.deb || apt-get -f install -y
    apt-get install --assume-yes --fix-broken
else
    echo "Chrome Remote Desktop is already installed."
fi

# Configure Chrome Remote Desktop
echo "exec /usr/bin/xfce4-session" > /etc/chrome-remote-desktop-session

# Install Firefox if not already installed
if ! is_package_installed firefox; then
    apt-get install --assume-yes firefox
else
    echo "Firefox is already installed."
fi

# Check if user exists and create if not
create_user_if_not_exists

# Extract the code from AUTH_COMMAND
EXTRACTED_CODE=$(echo $AUTH_COMMAND | grep -oP '(?<=--code=")[^"]*')

# Set up user directory for Chrome Remote Desktop
su - $USER << EOF
mkdir -p ~/.config/chrome-remote-desktop
chmod 700 ~/.config/chrome-remote-desktop
touch ~/.config/chrome-remote-desktop/host.json
echo "export CHROME_REMOTE_DESKTOP_DEFAULT_DESKTOP_SIZES=$RESOLUTIONS" >> ~/.profile
echo "export DISPLAY=:0" >> ~/.profile
echo "export DESKTOP_SESSION=xfce" >> ~/.profile
echo "export GDMSESSION=xfce" >> ~/.profile
echo "export XDG_SESSION_TYPE=x11" >> ~/.profile
echo "/usr/bin/pulseaudio --start" > ~/.chrome-remote-desktop-session
echo "exec /usr/bin/xfce4-session" >> ~/.chrome-remote-desktop-session

# Install Chrome Remote Desktop with specified settings
DISPLAY= /opt/google/chrome-remote-desktop/start-host --code=$EXTRACTED_CODE --redirect-url="https://remotedesktop.google.com/_/oauthredirect" --name=$HOSTNAME --pin=$PIN

# Copy configuration to the correct filename
HOST_HASH=$(echo -n $HOSTNAME | md5sum | cut -c -32)
FILENAME=~/.config/chrome-remote-desktop/host#${HOST_HASH}.json
if [ -f ~/.config/chrome-remote-desktop/host#*.json ]; then
    cp ~/.config/chrome-remote-desktop/host#*.json $FILENAME
else
    echo "Warning: No host configuration file found to copy."
fi
EOF

# Modify Chrome Remote Desktop service
sed -i 's/^ExecStart=.*/ExecStart=\/opt\/google\/chrome-remote-desktop\/chrome-remote-desktop --start --foreground --account-type=SYSTEM/' /etc/systemd/system/chrome-remote-desktop@.service

# Print hostname and keep the script running
echo $HOSTNAME

while true; do
    sleep 99999
    echo "Still running... Press Ctrl+C to exit."
done
