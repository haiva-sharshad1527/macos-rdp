#!/usr/bin/env bash
set -e

VNC_PASSWORD="${1:-FarisMac2026}"
NGROK_TOKEN="${2}"
NGROK_REGION="${3:-in}"

echo "=========================================================="
echo "🍏 Configuring macOS GUI Screen Sharing & VNC Service..."
echo "=========================================================="

# 1. Disable spotlight indexing to conserve VM resources
sudo mdutil -i off -a 2>/dev/null || true

# 2. Set runner password (so runner can authenticate via GUI / VNC)
echo "Setting password for user 'runner'..."
sudo dscl . -passwd /Users/runner "$VNC_PASSWORD" 2>/dev/null || echo "runner:$VNC_PASSWORD" | sudo chpasswd 2>/dev/null || true

# 3. Create runneradmin account with administrative privileges
echo "Creating admin user 'runneradmin'..."
sudo dscl . -create /Users/runneradmin UserShell /bin/bash 2>/dev/null || true
sudo dscl . -create /Users/runneradmin RealName "Runner Admin" 2>/dev/null || true
sudo dscl . -create /Users/runneradmin UniqueID 1001 2>/dev/null || true
sudo dscl . -create /Users/runneradmin PrimaryGroupID 80 2>/dev/null || true
sudo dscl . -create /Users/runneradmin NFSHomeDirectory /Users/runneradmin 2>/dev/null || true
sudo dscl . -passwd /Users/runneradmin "$VNC_PASSWORD" 2>/dev/null || true
sudo createhomedir -c -u runneradmin 2>/dev/null || true
sudo dscl . -append /Groups/admin GroupMembership runneradmin 2>/dev/null || true

# 4. Enable macOS Remote Management (Apple Screen Sharing / VNC on port 5900)
echo "Enabling Apple Remote Management..."
sudo /System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart \
  -activate -configure -allowAccessFor -allUsers -privs -all

# 5. Enable legacy VNC client support
sudo /System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart \
  -configure -clientopts -setvnclegacy -vnclegacy yes

# 6. Set legacy VNC password hash
echo "Setting VNC password hash..."
echo "$VNC_PASSWORD" | perl -we 'BEGIN { @k = unpack "C*", pack "H*", "1734516E8BA8C5E2"}; $_ = <>; chomp; s/^(.{8}).*/$1/; @p = unpack "C*", $_; foreach (@k) { printf "%02X", $_ ^ (shift @p || 0) }; print "\n"' | sudo tee /Library/Preferences/com.apple.VNCSettings.txt

# 7. Restart ARD Agent to apply changes
echo "Restarting ARD service..."
sudo /System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart \
  -restart -agent -console
sudo /System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart \
  -activate

echo "✅ macOS Screen Sharing & VNC is active on port 5900!"

# 8. Start tunnels
echo ""
echo "=========================================================="
echo "🌐 Starting Remote Tunnels..."
echo "=========================================================="

NGROK_ACTIVE="false"
if [ -n "$NGROK_TOKEN" ]; then
  echo "==> Configuring Ngrok..."
  if ! command -v ngrok &>/dev/null; then
    ARCH=$(uname -m)
    echo "Downloading ngrok for $ARCH..."
    if [ "$ARCH" = "arm64" ]; then
      curl -sSL https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-darwin-arm64.zip -o /tmp/ngrok.zip
    else
      curl -sSL https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-darwin-amd64.zip -o /tmp/ngrok.zip
    fi
    sudo unzip -q -o /tmp/ngrok.zip -d /usr/local/bin/
    chmod +x /usr/local/bin/ngrok
  fi

  ngrok authtoken "$NGROK_TOKEN"
  ngrok tcp 5900 --region="$NGROK_REGION" --log=stdout > /tmp/ngrok.log 2>&1 &
  sleep 5

  NGROK_URL=$(curl -s http://127.0.0.1:4040/api/tunnels | grep -o '"public_url":"[^"]*' | sed 's/"public_url":"//' | head -n1 || true)
  if [ -n "$NGROK_URL" ]; then
    NGROK_ACTIVE="true"
  fi
fi

# Also launch Pinggy in background as tokenless fallback
echo "==> Launching Pinggy TCP tunnel (tokenless backup)..."
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ServerAliveInterval=30 -p 443 -R0:localhost:5900 tcp@a.pinggy.io > /tmp/pinggy.log 2>&1 &
sleep 5
PINGGY_URL=$(grep -o 'tcp://[^ ]*' /tmp/pinggy.log | head -n1 || true)

echo ""
echo "=========================================================="
echo "🎉 MACOS DESKTOP CONNECTION DETAILS"
echo "=========================================================="
echo "👤 Username:   runner (or runneradmin)"
echo "🔑 Password:   $VNC_PASSWORD"
echo "🖥️  Resolution: Default Retina Virtual Display"
echo ""

if [ "$NGROK_ACTIVE" = "true" ]; then
  echo "⚡ NGROK TUNNEL (PRIMARY):"
  echo "   VNC Target: $NGROK_URL"
  CLEAN_NGROK=$(echo "$NGROK_URL" | sed 's#tcp://##')
  echo "   Connect directly to: $CLEAN_NGROK"
  echo ""
fi

if [ -n "$PINGGY_URL" ]; then
  echo "⚡ PINGGY TUNNEL (TOKENLESS BACKUP):"
  echo "   VNC Target: $PINGGY_URL"
  CLEAN_PINGGY=$(echo "$PINGGY_URL" | sed 's#tcp://##')
  echo "   Connect directly to: $CLEAN_PINGGY"
  echo ""
fi

echo "=========================================================="

# Also write to GitHub Actions Step Summary if in CI environment
if [ -n "$GITHUB_STEP_SUMMARY" ]; then
  cat << EOF >> "$GITHUB_STEP_SUMMARY"
## 🍏 macOS Cloud Desktop Ready!

- **Username:** \`runner\` (or \`runneradmin\`)
- **Password:** \`$VNC_PASSWORD\`
- **Resolution:** Default Virtual Retina Display

### ⚡ Connection Methods:

EOF

  if [ "$NGROK_ACTIVE" = "true" ]; then
    CLEAN_NGROK=$(echo "$NGROK_URL" | sed 's#tcp://##')
    cat << EOF >> "$GITHUB_STEP_SUMMARY"
- **Ngrok (Direct TCP):**
  - Host/Port: \`$CLEAN_NGROK\`
  - Remmina/VNC Target: \`$CLEAN_NGROK\`
EOF
  fi

  if [ -n "$PINGGY_URL" ]; then
    CLEAN_PINGGY=$(echo "$PINGGY_URL" | sed 's#tcp://##')
    cat << EOF >> "$GITHUB_STEP_SUMMARY"
- **Pinggy (Tokenless TCP):**
  - Host/Port: \`$CLEAN_PINGGY\`
  - Remmina/VNC Target: \`$CLEAN_PINGGY\`
EOF
  fi

  cat << EOF >> "$GITHUB_STEP_SUMMARY"

- **tmate (Encrypted SSH Tunnel):**
  - Check the live \`action-tmate\` step log for your SSH command.
  - Forward port: \`ssh -L 5900:localhost:5900 <tmate-user>@<tmate-host>\`
  - Connect client to: \`localhost:5900\`

### 💻 Kali Linux Quick Connect:
\`\`\`bash
# Method 1: Remmina GUI
remmina & # Choose VNC -> enter the Host/Port above -> password: $VNC_PASSWORD

# Method 2: CLI vncviewer
vncviewer <HOST>:<PORT>
\`\`\`
EOF
fi

