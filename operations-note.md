# Operations note: hello-service is down

Work outside-in: confirm the failure, find which layer is broken, restore
service, then find the cause.

## 1. Confirm and scope

```bash
curl -v --max-time 5 http://<ip>/health
```

The kind of failure narrows it down:

| Result | Points to |
|---|---|
| Timeout | Network path, security group, or instance down |
| Connection refused | Instance up, nothing listening on 80 |
| 5xx / slow | App running but unhealthy, or host overloaded |

Also: did anything change? Last `terraform apply`, last CI run, a replaced
instance (new IP - compare with `terraform output service_url`).

## 2. AWS level

- Instance state: `aws ec2 describe-instances --instance-ids <id>`
- Status checks (CloudWatch): `StatusCheckFailed_System` = AWS hardware or network,
  fixed by stop/start (moves host). `StatusCheckFailed_Instance` = OS problem.
- Alarm `hello-service-instance-status-check`: in ALARM / recently rebooted?
  `aws cloudwatch describe-alarm-history --alarm-name hello-service-instance-status-check`
- Boot problems: `aws ec2 get-console-output --instance-id <id> --latest`
- Security group still allows tcp/80 inbound.
- AWS Health Dashboard for a regional EC2 event.

## 3. Host level (`aws ssm start-session --target <id>`)

If SSM can't connect either, the instance itself is unhealthy - back to step 2.

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

## 5. Restore (least disruptive first)

1. `sudo systemctl restart hello`
2. `aws ec2 reboot-instances --instance-ids <id>`
3. Stop/start (new hardware; public IP changes)
4. Fresh instance from code: `terraform apply -replace=aws_instance.web`
5. Bad change: check out the last good commit, `./scripts/deploy.sh`

## 6. Afterwards

Timeline, root cause, fix, and one check that would have caught it sooner
(e.g. CloudWatch alarm on `StatusCheckFailed`, external uptime check).
