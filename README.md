# macOS Cloud Desktop on GitHub Actions 🍏

Run a full, interactive **macOS Desktop GUI (Apple Silicon / Intel)** inside GitHub Actions runners and connect directly from **Kali Linux**, Linux, Windows, or mobile with near-zero latency.

---

## ⚡ Features

- **Apple Silicon & Intel Support**: Runs natively on `macos-latest` (Apple Silicon M-series) or configurable to `macos-14`, `macos-15`, and `macos-13`.
- **Multiple Zero-Friction Tunneling Engines**:
  - **Ngrok (Fastest)**: Low latency with region selection (e.g., `in` for India / Chennai).
  - **Pinggy (Tokenless Backup)**: Direct public TCP endpoint without needing any accounts.
  - **tmate (Encrypted SSH Tunnel)**: Bulletproof, encrypted SSH port-forwarding straight into your Kali terminal.
- **6-Hour Persistent Sessions**: Maxes out GitHub Actions runner duration (360 minutes).
- **Pre-Configured Audio & Screen Sharing**: Native Apple Remote Management enabled with full root/admin permissions.

---

## 🚀 How to Run

1. Go to the **Actions** tab in this repository.
2. Select **macOS Cloud Desktop (VNC)**.
3. Click **Run workflow**:
   - *(Optional)* Paste your **Ngrok Auth Token** (or add `NGROK_AUTH_TOKEN` in Repo Secrets).
   - *(Optional)* Change Password (default: `FarisMac2026`).
   - *(Optional)* Choose Region (default: `in` for lowest ping in India).
   - *(Optional)* Choose macOS Runner (default: `macos-latest`).
4. Click **Run workflow**.
5. Click on the active workflow run and open the **macOS Desktop Runner** log.
6. Copy the connection endpoint from the banner!

---

## 💻 How to Connect from Kali Linux

Default credentials:
- **Username**: `runner` (or `runneradmin`)
- **Password**: `FarisMac2026`

### Option 1: Remmina (Recommended GUI)

Remmina is the best graphical remote client on Kali Linux:

1. Launch Remmina from Kali application menu or run in terminal:
   ```bash
   remmina &
   ```
2. In the top connection bar:
   - Protocol: Select **VNC**
   - Address: Enter the Ngrok or Pinggy address (e.g. `0.tcp.in.ngrok.io:12345` or `...a.pinggy.link:4321`)
3. Hit **Enter** and type the password: `FarisMac2026`.
4. You are inside macOS!

### Option 2: CLI TigerVNC (`vncviewer`)

If you prefer lightweight command line:

```bash
sudo apt update && sudo apt install -y tigervnc-viewer
vncviewer <tunnel-address>:<port>
```
*Example:*
```bash
vncviewer 0.tcp.in.ngrok.io:12345
```

### Option 3: Encrypted SSH Tunnel via tmate (No Ngrok Needed)

If you don't have an Ngrok token:
1. In the GitHub Actions log, copy the `ssh ...` command printed by the `action-tmate` step.
2. On Kali Linux, add local port forwarding `-L 5900:localhost:5900`:
   ```bash
   ssh -L 5900:localhost:5900 <user>@<host>
   ```
3. In another terminal on Kali, simply connect to localhost:
   ```bash
   vncviewer localhost:5900
   ```
   *(Or in Remmina: connect to `localhost:5900`)*

---

## 🛡️ Architecture & Security

- macOS Ventura, Sonoma, and Sequoia runners natively run Aqua WindowServer for CI testing.
- Remote Management (`kickstart`) activates Apple's RFB/VNC daemon on port 5900.
- All sessions are isolated and ephemeral.
