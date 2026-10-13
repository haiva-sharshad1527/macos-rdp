#!/usr/bin/env bash
set -e

VNC_PASSWORD="${1:-FarisMac2026}"
NGROK_TOKEN="${2}"
NGROK_REGION="${3:-in}"
CURRENT_USER="${USER:-runner}"

echo "=========================================================="
echo "🍏 Configuring macOS GUI Screen Sharing & VNC Service..."
echo "=========================================================="

# 1. Disable spotlight indexing to conserve VM resources
sudo mdutil -i off -a 2>/dev/null || true

# 2. Prevent display sleep & screensaver (critical: prevents blank/black screen)
echo "==> Disabling display sleep and screensaver..."
sudo pmset -a displaysleep 0 sleep 0 disablesleep 1 2>/dev/null || true
defaults -currentHost write com.apple.screensaver idleTime 0 2>/dev/null || true

# 3. Set password for the active GUI console user ($CURRENT_USER)
echo "==> Setting password for user '$CURRENT_USER'..."
sudo sysadminctl -resetPasswordFor "$CURRENT_USER" -newPassword "$VNC_PASSWORD" 2>/dev/null || \
  echo "$CURRENT_USER:$VNC_PASSWORD" | sudo chpasswd 2>/dev/null || \
  sudo dscl . -passwd "/Users/$CURRENT_USER" "$VNC_PASSWORD" 2>/dev/null || true

# 4. Also configure runneradmin as backup admin account
if ! dscl . -read /Users/runneradmin &>/dev/null; then
  echo "==> Creating admin user 'runneradmin'..."
  sudo dscl . -create /Users/runneradmin UserShell /bin/bash 2>/dev/null || true
  sudo dscl . -create /Users/runneradmin RealName "Runner Admin" 2>/dev/null || true
  sudo dscl . -create /Users/runneradmin UniqueID 1001 2>/dev/null || true
  sudo dscl . -create /Users/runneradmin PrimaryGroupID 80 2>/dev/null || true
  sudo dscl . -create /Users/runneradmin NFSHomeDirectory /Users/runneradmin 2>/dev/null || true
  sudo dscl . -passwd /Users/runneradmin "$VNC_PASSWORD" 2>/dev/null || true
  sudo createhomedir -c -u runneradmin 2>/dev/null || true
  sudo dscl . -append /Groups/admin GroupMembership runneradmin 2>/dev/null || true
fi

# 5. Fix TCC (Transparency, Consent, and Control) permissions
# This prevents the black screen caused by macOS denying screen capture to ARD/VNC
echo "==> Pre-authorizing Screen Capture & Remote Management in TCC..."
CLIENTS=(
  "com.apple.RemoteDesktop.agent"
  "com.apple.screensharing.agent"
  "com.apple.screensharing.menuextra"
  "/System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/MacOS/ARDAgent"
  "/System/Library/CoreServices/RemoteManagement/screensharingd"
  "/System/Library/CoreServices/RemoteManagement/AppleVNCServer.bundle/Contents/MacOS/AppleVNCServer"
  "/System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Support/vncagent"
  "/bin/bash"
  "com.apple.Terminal"
)

SERVICES=(
  "kTCCServiceScreenCapture"
  "kTCCServicePostEvent"
  "kTCCServiceAccessibility"
  "kTCCServiceSystemPolicyAllFiles"
)

for db in "/Library/Application Support/com.apple.TCC/TCC.db" "$HOME/Library/Application Support/com.apple.TCC/TCC.db"; do
  if [ -e "$db" ]; then
    for client in "${CLIENTS[@]}"; do
      for service in "${SERVICES[@]}"; do
        sudo sqlite3 "$db" "INSERT OR REPLACE INTO access (service, client, client_type, allowed, prompt_count, csreq, indirect_object_identifier_type, indirect_object_identifier, flags, last_modified) VALUES ('$service','$client',0,2,4,1,NULL,'UNUSED',0,0);" 2>/dev/null || true
      done
    done
  fi
done

# 6. Enable Apple Remote Management (Screen Sharing / VNC on port 5900)
echo "==> Activating Apple Remote Desktop (Screen Sharing)..."
sudo /System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart \
  -activate -configure -access -on -users "$CURRENT_USER" -privs -all \
  -clientopts -setvnclegacy -vnclegacy yes

# 7. Set legacy VNC password hash
echo "==> Setting legacy VNC authentication hash..."
echo "$VNC_PASSWORD" | perl -we 'BEGIN { @k = unpack "C*", pack "H*", "1734516E8BA8C5E2"}; $_ = <>; chomp; s/^(.{8}).*/$1/; @p = unpack "C*", $_; foreach (@k) { printf "%02X", $_ ^ (shift @p || 0) }; print "\n"' | sudo tee /Library/Preferences/com.apple.VNCSettings.txt

# 8. Restart ARD Agent to apply changes
echo "==> Restarting ARD service..."
sudo /System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart \
  -restart -agent -console
sudo /System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart \
  -activate

echo "✅ macOS Screen Sharing & VNC is active on port 5900!"

# 9. Start tunnels
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
  sleep 4

  NGROK_URL=$(curl -s http://127.0.0.1:4040/api/tunnels | grep -o '"public_url":"[^"]*' | sed 's/"public_url":"//' | head -n1 || true)
  if [ -n "$NGROK_URL" ]; then
    NGROK_ACTIVE="true"
  fi
fi

# Always launch Pinggy in background as tokenless backup
echo "==> Launching Pinggy TCP tunnel (tokenless backup)..."
ssh -T -p 443 -R0:localhost:5900 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ServerAliveInterval=30 a.pinggy.io > /tmp/pinggy.log 2>&1 &
sleep 6

PINGGY_URL=$(grep -o 'tcp://[^ ]*' /tmp/pinggy.log | head -n1 || true)

echo ""
echo "=========================================================="
echo "🎉 MACOS DESKTOP CONNECTION DETAILS"
echo "=========================================================="
echo "👤 Username:   $CURRENT_USER (or runneradmin)"
echo "🔑 Password:   $VNC_PASSWORD"
echo "🖥️  OS:         $(sw_vers -productName 2>/dev/null || echo macOS) $(sw_vers -productVersion 2>/dev/null || true)"
echo ""

if [ "$NGROK_ACTIVE" = "true" ]; then
  CLEAN_NGROK=$(echo "$NGROK_URL" | sed 's#tcp://##')
  echo "⚡ NGROK TUNNEL (PRIMARY):"
  echo "   VNC Target: $NGROK_URL"
  echo "   Connect directly to: $CLEAN_NGROK"
  echo ""
fi

if [ -n "$PINGGY_URL" ]; then
  CLEAN_PINGGY=$(echo "$PINGGY_URL" | sed 's#tcp://##')
  echo "⚡ PINGGY TUNNEL (TOKENLESS BACKUP):"
  echo "   VNC Target: $PINGGY_URL"
  echo "   Connect directly to: $CLEAN_PINGGY"
  echo ""
fi

echo "=========================================================="

# Also write to GitHub Actions Step Summary if in CI environment
if [ -n "$GITHUB_STEP_SUMMARY" ]; then
  cat << EOF >> "$GITHUB_STEP_SUMMARY"
## 🍏 macOS Cloud Desktop Ready!

- **Username:** \`$CURRENT_USER\` *(or \`runneradmin\`)*
- **Password:** \`$VNC_PASSWORD\`
- **Resolution:** Full Native macOS Virtual Display

### ⚡ Connection Endpoints:

EOF

  if [ "$NGROK_ACTIVE" = "true" ]; then
    CLEAN_NGROK=$(echo "$NGROK_URL" | sed 's#tcp://##')
    cat << EOF >> "$GITHUB_STEP_SUMMARY"
#### 🚀 Ngrok (Direct TCP):
- **Server Address:** \`$CLEAN_NGROK\`
- **Remmina Protocol:** \`VNC\`
EOF
  fi

  if [ -n "$PINGGY_URL" ]; then
    CLEAN_PINGGY=$(echo "$PINGGY_URL" | sed 's#tcp://##')
    cat << EOF >> "$GITHUB_STEP_SUMMARY"
#### 🌐 Pinggy (No Token Needed):
- **Server Address:** \`$CLEAN_PINGGY\`
- **Remmina Protocol:** \`VNC\`
EOF
  fi

  cat << EOF >> "$GITHUB_STEP_SUMMARY"

### 💻 Kali Linux Quick Connect:
\`\`\`bash
# Method 1: Remmina GUI (Recommended)
# 1. Open Remmina -> Set protocol to VNC
# 2. Paste the Server Address above (WITHOUT tcp://)
# 3. Enter password: $VNC_PASSWORD

# Method 2: CLI vncviewer
vncviewer <SERVER_ADDRESS>
\`\`\`
EOF
fi
