# Host-level failure detection and reporting.
# The on-instance timer handles the app; this handles the instance itself
# (frozen OS, kernel panic, out of memory) where nothing local can run.

# Optional e-mail alerts. AWS sends a confirmation mail you must accept.
resource "aws_sns_topic" "alerts" {
  count = var.alert_email == "" ? 0 : 1
  name  = "${var.project_name}-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.alert_email == "" ? 0 : 1
  topic_arn = aws_sns_topic.alerts[0].arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# Instance status check fails for 3 minutes in a row -> reboot it (and e-mail).
resource "aws_cloudwatch_metric_alarm" "instance_check" {
  alarm_name          = "${var.project_name}-instance-status-check"
  alarm_description   = "OS on ${var.project_name} unresponsive; rebooting"
  namespace           = "AWS/EC2"
  metric_name         = "StatusCheckFailed_Instance"
  dimensions          = { InstanceId = aws_instance.web.id }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 3
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"

  alarm_actions = concat(
    ["arn:aws:automate:${var.aws_region}:ec2:reboot"],
    aws_sns_topic.alerts[*].arn,
  )
  ok_actions = aws_sns_topic.alerts[*].arn
}
