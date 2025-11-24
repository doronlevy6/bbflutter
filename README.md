# 📘 Baller Project Guide (Manual Workflow)

## 🎯 Overview
This guide explains how to manually manage the development environment and deploy the application.

---

## 🛠️ Development Setup

### 1. Start Database (Docker)
Required for **Local Development**.
```bash
cd BB_server
./start_local_db.sh
```
*   **Check status:** `docker ps` (should show `bb-db` and `pgadmin`)

### 2. Configure Backend (Server)
The server connects to the database defined in `BB_server/.env`.

**Option A: Local DB (Docker)**
1.  Copy contents of `.env.local` to `.env`.
2.  **Verify:** `PGHOST='localhost'`

**Option B: Remote DB (Neon)**
1.  Copy contents of `.env.production` to `.env`.
2.  **Verify:** `PGHOST='...neon.tech'`

**🚀 Start Server:**
*   **Check if running:** `lsof -i :9090` (if empty, it's not running)
```bash
cd BB_server
npm run dev
```

### 3. Configure Frontend (Flutter)
The app connects to the server defined in `lib/managers/environment_manager.dart`.

**Open:** `BB_flutter/lib/managers/environment_manager.dart`
**Edit:** `_currentEnvironment`

| Scenario | Setting | Description |
|----------|---------|-------------|
| **Emulator** | `Environment.LOCAL` | Connects to `localhost` |
| **Real Phone** | `Environment.DEVICE_LOCAL` | Connects to Computer IP |
| **Production** | `Environment.PROD` | Connects to Render URL |

**🚀 Start App:**
```bash
cd BB_flutter
flutter run
```

---

## 🚢 Deployment

### 🌐 Web (GitHub Pages)
Deploys to: https://doronlevy6.github.io/

```bash
cd BB_flutter
./deploy_web.sh
cd ../BB_web
git add .
git commit -m "Deploy web update"
git push
```

### 📱 Android (Google Play)
1.  **Set Environment:** Change `environment_manager.dart` to `Environment.PROD`.
2.  **Build Bundle:**
    ```bash
    cd BB_flutter
    flutter build appbundle --release
    ```
3.  **Upload:** File is located at `build/app/outputs/bundle/release/app-release.aab`. Upload manually to Google Play Console.

### 🖥️ Server (Render)
Deploys to: https://renderbbserver.onrender.com
Render automatically deploys when you push to the `main` branch.

```bash
cd BB_server
git add .
git commit -m "Update server"
git push
```
*   **Note:** Production environment variables are managed in the Render Dashboard, not in the `.env` file.
