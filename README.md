# Learning Platform - Docker Development Setup

## About

The Learning Platform is a comprehensive education management system built for Nashville Software School. It consists of a Django REST API backend and a React frontend, allowing instructors to track student progress, create courses, manage cohorts, and facilitate collaborative learning through integrated GitHub and Slack functionality.

**Tech Stack:**
- **Backend:** Django, Django REST Framework, PostgreSQL
- **Frontend:** React, JavaScript
- **Authentication:** GitHub OAuth
- **Containerization:** Docker, Docker Compose

## Developer Prerequisites

### Required Software
- **Git** - for version control
- **Docker** - for containerization
- **Docker Compose** - for orchestrating multi-container applications

### Docker Installation

#### Windows
1. Download Docker Desktop from [docker.com](https://www.docker.com/products/docker-desktop/)
2. Run the installer and follow the setup wizard
3. Docker Desktop includes both Docker and Docker Compose
4. After installation, ensure Docker Desktop is running (check system tray)

#### macOS
1. Download Docker Desktop from [docker.com](https://www.docker.com/products/docker-desktop/)
2. Drag Docker.app to your Applications folder
3. Launch Docker Desktop from Applications
4. Docker Desktop includes both Docker and Docker Compose

#### Linux (Ubuntu/Debian)
1. Update package index: `sudo apt-get update`
2. Install Docker:
   ```bash
   sudo apt-get install docker.io
   sudo systemctl start docker
   sudo systemctl enable docker
   ```
3. Install Docker Compose:
   ```bash
   sudo apt-get install docker-compose
   ```
4. Add your user to the docker group: `sudo usermod -aG docker $USER`
5. Log out and back in for the group change to take effect

#### Verify Installation
After installing Docker on any platform, verify it's working:
```bash
docker --version
docker compose version
```

### SSH Key Setup
If working with private repositories, ensure you have:
1. SSH key pair generated for your OS
2. Public SSH key added to your GitHub account
3. SSH agent running with your private key added

## GitHub OAuth Application Setup

The Learning Platform uses GitHub for authentication. You'll need to create your own OAuth application:

1. Go to your GitHub account **Settings**
2. Navigate to **Developer Settings** → **OAuth Apps**
3. Click **New OAuth App**
4. Fill in the application details:
   - **Application name:** Learning Platform
   - **Homepage URL:** `http://localhost:3000`
   - **Authorization callback URL:** `http://localhost:8000/auth/github/callback`
   - **Description:** (optional)
5. Leave **Enable Device Flow** unchecked
6. Click **Register Application**
7. Click **Generate a new client secret**
8. **Keep this tab open** - you'll need both the Client ID and Client Secret for the next step

## Getting Started

### 1. Create parent directory
Create a directory called `learning-platform`. This will be the parent directory for the project. This is important because Docker Compose depends on a specific file structure.

```sh
mkdir learning-platform
cd learning-platform 
```

### 2. Fork and Clone Repositories

You'll need to fork and clone three repositories:
1. The infrastructure repo (this repo)
2. [The Learning Platform API](https://github.com/NSS-Workshops/learn-ops-api)
3. [The Learning Platform Client](https://github.com/NSS-Workshops/learn-ops-client)


Clone each repo in the `learning-platform` directory.

### 2. Directory Structure
Your directory structure should look like this
```
learning-platform/
├── learn-ops-api/
├── learn-ops-client/
└── learn-ops-infrastructure/
```

### 3. Environment Variables Setup

#### API Environment Variables
1. Navigate to the `learn-ops-api` directory
2. Copy the environment template: 
```shell
cp .env.template .env
```
1. Fill in the `replace_me` values in `.env`:
  - **LEARN_OPS_CLIENT_ID**: The client ID from the OAuth app you created in Github
  - **LEARN_OPS_SECRET_KEY**: The secret key from the OAuth app you created in Github
  - **LEARN_OPS_DJANGO_SECRET_KEY**: Create a random string of 20-30 alphanumerical characters (*no special characters such as $%@-*)
  - **LEARN_OPS_SUPERUSER_NAME**: Create a simple username for the django admin panel
  - **LEARN_OPS_SUPERUSER_PASSWORD**: Create a simple password for the django admin panel

## Running with Docker

### 1. Start the Application
From the `learn-ops-infrastructure` directory, run:
```bash
docker compose up -d
```

This will:
- Start a PostgreSQL database
- Build and run the Django API (with automatic database setup and seeding)
- Build and run the React client
- Set up networking between all services

### 2. Access the Application
- **Client (React):** http://localhost:3000
- **API (Django):** http://localhost:8000
- **Database:** localhost:5432 (if you need direct access)

### 3. Initial Database Setup
The API container automatically handles:
- Database migrations
- Loading initial data and fixtures
- Creating the superuser account

### 4. Stopping the Application
```bash
# Stop services but keep data
docker compose stop

# Stop and remove containers/networks (keeps volumes)  
docker compose down

# Stop and remove everything including data
docker compose down -v
```

## Development Workflow

### Making Code Changes
- The containers use volume mounts, so changes to your local code will be reflected immediately
- API changes *may* require restarting the API container 
- Client changes will hot-reload automatically

### Viewing Logs
```bash
# All services
docker compose logs -f

# Specific services  
docker compose logs -f api database
docker compose logs -f client
```

### Rebuilding After Changes
```bash
# Rebuild specific service 
docker compose build api
docker compose build client

# Rebuild and restart everything
docker compose up --build --force-recreate
```

### Running the API with VS Code Debugger

To debug the api with the VS Code debugger, the api container will need to be started with VS Code. 

1. Close the api VS Code instance if it is already opened. 
2. Stop all services

```shell
docker compose down
```
3. Start ONLY the database and the client services
```shell
docker compose up -d database client
```
4. Open the api with VS Code. You should see a prompt in the bottom right-hand corner that says, "Folder contains a Dev Container configuration file. Reopen folder to develop in a container." Click `Reopen in Container`.
5. Once the container has finished building, in the vscode integrated terminal you should see:
```shell
⠹ Creating virtual environment...✔ Successfully created virtual environment!
Virtualenv location: /root/.local/share/virtualenvs/app-4PlAip0Q
To activate this project's virtualenv, run pipenv shell.
Alternatively, run a command inside the virtualenv with pipenv run.
Installing dependencies from Pipfile.lock (9e6e4d)...
Installing dependencies from Pipfile.lock (9e6e4d)...
Done. Press any key to close the terminal.
```
6. Now you can place breakpoints in the code and start the development server with the vs code debugger.




## Troubleshooting

### Port Conflicts
If you get port binding errors, make sure ports 3000, 8000, and 5432 are not in use by other applications.

## Next Steps

Once everything is running:
1. Visit http://localhost:3000 to access the Learning Platform
2. Test GitHub authentication by logging in
3. Access the Django admin at http://localhost:8000/admin using your superuser credentials
4. Start developing and debugging in your containerized environment!