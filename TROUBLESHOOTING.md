# hello-service: Implementation Troubleshooting Log

Six issues came up while building and deploying hello-service. None were bugs in the
application code: all came from the Windows workstation, Git, or the network path. This log
records each symptom, root cause and fix so the next engineer can resolve them in minutes.

**Environment:** Windows 11 with Git Bash (MINGW64) and PowerShell · Python 3.10 · Terraform ·
AWS CLI · AWS ap-south-1 (Mumbai), EC2 t3.micro running Amazon Linux 2023 · GitHub Actions on
ubuntu-latest.

## Issue log

Issues are listed in the order they were hit.

### 1. `deploy.sh`: "AWS credentials not working"

- **Symptom:** `./scripts/deploy.sh` failed with `ERROR: AWS credentials not working`, yet
  `aws sts get-caller-identity` worked when typed.
- **Root cause:** Git Bash had an alias `aws` → `aws.cmd`. Scripts ignore aliases, so the script
  ran a broken pip-installed AWS CLI v1 (`Python.3.10.4/Scripts/aws`), which failed with
  "cannot execute: required file not found". The script sent stderr to `/dev/null`, hiding this.
- **Diagnosis:**
  ```bash
  type aws                                   # aws is aliased to `aws.cmd'
  which -a aws                               # /d/Program Files/Python.3.10.4/Scripts/aws
  bash -x ./scripts/deploy.sh --plan-only    # shows caller= empty, then die
  ```
- **Fix:** run `pip uninstall awscli`, install
  [AWS CLI v2](https://awscli.amazonaws.com/AWSCLIV2.msi), remove the alias from `~/.bashrc`,
  and open a new shell.

### 2. Git Bash: `aws.cmd: command not found`

- **Symptom:** after the uninstall, every `aws` command failed with `aws.cmd: command not found`.
- **Root cause:** the alias was still loaded in the open shell. Editing `.bashrc` doesn't change a
  running session.
- **Fix:** run `unalias aws` or open a new Git Bash window. `type aws` should now print
  `/c/Program Files/Amazon/AWSCLIV2/aws`.

### 3. GitHub Actions: `Permission denied` in `test` and `systemd-install`

- **Symptom:** `./scripts/smoke-test.sh: Permission denied` (exit 126) and
  `sudo: cannot execute .../scripts/install.sh: Permission denied`.
- **Root cause:** files committed from Windows lose the Linux executable bit, so git stored the
  scripts as mode `100644`.
- **Fix:**
  ```bash
  git update-index --chmod=+x scripts/*.sh deploy/healthcheck.sh
  git commit -m "Mark shell scripts executable"
  git push
  git ls-files -s scripts deploy/healthcheck.sh   # expect 100755
  ```

### 4. Local run on Windows: `WinError 10013`

- **Symptom:** `cannot bind 127.0.0.1:8080: [WinError 10013] An attempt was made to access a
  socket in a way forbidden by its access permissions`.
- **Root cause:** Windows blocked the port. Port 8080 was not in an excluded range and was not in
  use, so local security software is the likely cause.
- **Diagnosis:**
  ```powershell
  netsh interface ipv4 show excludedportrange protocol=tcp
  netstat -ano | findstr :8080
  ```
- **Fix:** run on another port: `PORT=9090 python app/app.py`. CI and EC2 run Linux and are
  unaffected.

### 5. Browser → EC2: `ERR_TIMED_OUT`

- **Symptom:** `http://<public-ip>` timed out in the browser.
- **Root cause (to confirm):** a timeout means packets are dropped before reaching the app.
  Candidates:
  - `allowed_http_cidrs` is set to an old IP.
  - The instance is still booting.
  - The browser is forcing HTTPS.
  - The local network is blocking outbound port 80.
- **Fix / diagnosis:**
  1. In AWS CloudShell, run `curl -v http://<ip>/health`. It works there → the problem is your
     local network. It fails there too → the problem is on the AWS side.
  2. Check the security group's inbound source CIDR (EC2 → Instance → Security tab).
  3. In Session Manager (EC2 → Connect → Session Manager), run `curl localhost/health` and
     `systemctl status hello`.

### 6. Browser → EC2: `:8080` never loads

- **Symptom:** `http://<ip>:8080` never loads.
- **Root cause:** on EC2 the app listens on port 80, and the security group allows only port 80.
  Port 8080 is the local default only.
- **Fix:** use `http://<ip>` (port 80 is implied).

## Diagnostic commands

| Question | Command |
|---|---|
| Do my AWS credentials work? | `aws sts get-caller-identity` |
| Which `aws` does my shell vs a script run? | `type aws` and `which -a aws` |
| Which line of a script fails? | `bash -x ./scripts/deploy.sh --plan-only` |
| Are the scripts executable in git? | `git ls-files -s scripts deploy/healthcheck.sh` |
| Is a Windows port reserved or in use? | `netsh interface ipv4 show excludedportrange protocol=tcp` / `netstat -ano \| findstr :<port>` |
| What did Terraform create? | `terraform -chdir=terraform output` |
| Which ports does the security group allow? | `aws ec2 describe-security-group-rules --filters Name=group-id,Values=<sg-id>` |
| Is the service reachable from outside my network? | AWS CloudShell: `curl -v http://<ip>/health` |
| Is the app healthy on the server? | Session Manager: `curl localhost/health`, `systemctl status hello`, `journalctl -u hello -n 50` |
| Did the instance boot cleanly? | `aws ec2 get-console-output --instance-id <id> --latest` |

