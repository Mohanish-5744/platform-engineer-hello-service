# Operations note: hello-service is down

Work outside-in: confirm the failure, find which layer is broken, restore
service, then find the cause. Past issues and fixes are in
[TROUBLESHOOTING.md](TROUBLESHOOTING.md).

## 1. Confirm and scope

```bash
curl -v --max-time 5 http://<ip>/health
```

Make sure the test itself is right before digging in:

- Plain `http://` on port 80. No HTTPS, no `:8080` (8080 is only the local default).
- Correct IP: compare with `terraform output service_url`. A replaced or stop/started instance gets a new IP.
- Test from a second network (AWS CloudShell). Works there but not from your laptop = your network, not the service.

The kind of failure narrows it down:

| Result | Points to |
|---|---|
| Timeout | Network path, security group (incl. stale `allowed_http_cidrs`), or instance down/booting |
| Connection refused | Instance up, nothing listening on 80 |
| 5xx / slow | App running but unhealthy, or host overloaded |

Also: did anything change? Last `terraform apply`, last CI run, a new instance.

## 2. AWS level

- Instance state: `aws ec2 describe-instances --instance-ids <id>`
- Status checks (CloudWatch): `StatusCheckFailed_System` = AWS hardware or network,
  fixed by stop/start (moves host). `StatusCheckFailed_Instance` = OS problem.
- Alarm `hello-service-instance-status-check`: in ALARM / recently rebooted?
  `aws cloudwatch describe-alarm-history --alarm-name hello-service-instance-status-check`
- Boot problems: `aws ec2 get-console-output --instance-id <id> --latest`
- Security group still allows tcp/80, and the source CIDR is what you expect:
  `aws ec2 describe-security-group-rules --filters Name=group-id,Values=<sg-id>`
- AWS Health Dashboard for a regional EC2 event.

## 3. Host level (`aws ssm start-session --target <id>`)

Or EC2 console → Connect → Session Manager. If SSM can't connect either, the
instance itself is unhealthy - back to step 2.

```bash
systemctl status hello hello-healthcheck.timer --no-pager
journalctl -u hello -n 100 --no-pager            # errors, tracebacks, restarts
journalctl -t hello-healthcheck --since -1h      # did the health check fire?
systemctl show hello -p NRestarts                # restart count
sudo ss -ltnp | grep ':80'                       # anything listening?
curl -s localhost/health                         # works locally, fails remotely => network/SG
curl -s localhost/metrics                        # request counts by status code
df -h / ; free -m ; uptime                       # disk, memory, load
journalctl -k --since -1h | grep -iE 'oom|killed'  # OOM killer (MemoryMax=128M)
sudo cat /var/log/cloud-init-output.log          # only if files/units are missing after first boot
```

## 4. Metrics

| Metric | Source | Why |
|---|---|---|
| `StatusCheckFailed_*` | CloudWatch | AWS vs OS fault |
| `CPUUtilization` | CloudWatch | Overload / runaway process |
| `CPUCreditBalance` | CloudWatch | Near 0 = throttled to baseline, everything slow |
| `NetworkIn/Out` | CloudWatch | Traffic spike, or drop to zero (path broken) |
| `hello_requests_total{code="..."}` | `/metrics` | Error rate, traffic per endpoint |
| `hello_uptime_seconds` | `/metrics` | Keeps resetting = restart loop |

Logs: `journalctl -u hello` (requests, errors) and `journalctl -t hello-healthcheck`
(`UNHEALTHY` / `restarted` lines).

## 5. Restore (least disruptive first)

1. `sudo systemctl restart hello`
2. `aws ec2 reboot-instances --instance-ids <id>`
3. Stop/start (new hardware; public IP changes)
4. Fresh instance from code: `terraform apply -replace=aws_instance.web`
5. Bad change: check out the last good commit, `./scripts/deploy.sh`

## 6. If the deploy itself fails

Not an outage of the running service, but blocks recovery steps 4–5:

| Symptom | Check |
|---|---|
| `deploy.sh`: "AWS credentials not working" | `aws sts get-caller-identity`; `type aws` / `which -a aws` (script may run a different `aws` than your shell); `bash -x ./scripts/deploy.sh --plan-only` |
| CI job: `Permission denied` on a script | `git ls-files -s scripts` – must be `100755` |
| `terraform plan`: no default VPC | `aws ec2 create-default-vpc` |

## 7. Afterwards

Timeline, root cause, fix, and one check that would have caught it sooner
(e.g. CloudWatch alarm on `StatusCheckFailed`, external uptime check). Add new
issues to TROUBLESHOOTING.md.
