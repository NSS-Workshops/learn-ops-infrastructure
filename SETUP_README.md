# LMS setup package

Contents covered:
- `Makefile`
- `scripts/setup.sh`

---

## Makefile targets

| Target | Description |
|---|---|
| `make setup` | Run the full first-time setup wizard (`scripts/setup.sh`) |
| `make doctor` | Run setup in doctor-only mode to check prerequisites without making changes |
| `make up` | Build and start all Docker services in detached mode |
| `make up-api` | Build and start only the `api` service |
| `make up-client-api` | Build and start the `api` and `client` services |
| `make down` | Stop and remove all running containers |
| `make logs` | Stream live logs from all running services |
| `make restart` | Stop all containers, then rebuild and start them again |
| `make ps` | Show the status of all Docker Compose services |
| `make reset` | Stop containers and remove all volumes and orphaned containers (destructive — clears database data) |

---

## setup.sh overview

An interactive wizard that takes a fresh machine from zero to a fully running local LMS stack. It supports macOS, Ubuntu on WSL, and Linux. The script is idempotent — re-running it skips steps that are already complete.

**What it does, in order:**

1. **Detect platform** — identifies macOS, WSL, or Linux.
2. **Check prerequisites** — verifies `git`, `docker`, `docker compose`, `python3`, and `make` are installed.
3. **Check Docker** — waits for the Docker daemon to be running and enforces minimum version requirements.
4. **Clean up existing resources** — removes any leftover LMS containers, images, and volumes from a previous install.
5. **Prepare workspace** — creates `~/workspace/lms/` and confirms the infrastructure repo is in the expected location.
6. **Clone repos** — clones `learn-ops-api`, `learn-ops-client`, and `service-monarch` if they aren't already present.
7. **Collect identity** — prompts for your name, email, and GitHub username (pre-fills from `git config`).
8. **Collect config** — interactively gathers secrets: GitHub PAT, Slack token, Slack webhook URL, and instructor-provided OAuth credentials. Generates a random Django secret key.
9. **Check org membership** — uses the GitHub API to verify your account is a member of the `System-Explorer-Cohorts` org.
10. **Set up student forks** — forks each course repo to your GitHub account and reconfigures remotes so `origin` points to your fork and `upstream` points to the NSS-Workshops source.
11. **Write environment files** — populates `.env` files for the API, Monarch service, and client from their templates using the collected values.
12. **Write instructor fixture** — generates a Django fixture that seeds your user account with instructor (`is_staff`) permissions.
13. **Validate layout** — confirms all expected directories and `.env` files are in place.
14. **Optionally start the stack** — offers to run `docker compose up`, then polls until the API (`localhost:8000`) and client (`localhost:3000`) respond.
15. **GitHub OAuth** — guides you through authorizing the LearnOps GitHub OAuth app so your local account is linked.

**Flags:**

- `--doctor` — skips setup and only runs the prerequisite and Docker checks.
- `--yes` — auto-confirms all yes/no prompts (useful for scripted runs).
