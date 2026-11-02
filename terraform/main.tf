# hello-service on a single Free Tier EC2 instance.
# Inbound: TCP 80 only. Admin access: SSM Session Manager (no SSH, no key pair).

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"] # excludes the "minimal" variant
  }
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }

  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

locals {
  subnet_id = sort(data.aws_subnets.default.ids)[0] # sorted so the choice is stable
}

# --- Security group ---------------------------------------------------------

resource "aws_security_group" "web" {
  name_prefix = "${var.project_name}-web-"
  description = "hello-service: inbound HTTP 80 only, no SSH"
  vpc_id      = data.aws_vpc.default.id

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "http" {
  for_each = toset(var.allowed_http_cidrs)

  security_group_id = aws_security_group.web.id
  description       = "HTTP to hello-service"
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
}

# SSM agent and dnf both use HTTPS. DNS, NTP and instance metadata go to
# link-local AWS addresses that security groups don't filter.
resource "aws_vpc_security_group_egress_rule" "https" {
  security_group_id = aws_security_group.web.id
  description       = "HTTPS out for SSM agent and package updates"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

# --- IAM: just enough for the SSM agent -----------------------------------------

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "instance" {
  name_prefix        = "${var.project_name}-"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "instance" {
  name_prefix = "${var.project_name}-"
  role        = aws_iam_role.instance.name
}

# --- Instance -------------------------------------------------------------------

resource "aws_instance" "web" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = var.instance_type
  subnet_id                   = local.subnet_id
  vpc_security_group_ids      = [aws_security_group.web.id]
  iam_instance_profile        = aws_iam_instance_profile.instance.name
  associate_public_ip_address = true
  # no key_name: there is no SSH key

  # gzip+base64 keeps file contents from breaking the YAML and keeps
  # user_data well under the 16 KB limit.
  user_data = templatefile("${path.module}/cloud-init.yaml.tftpl", {
    app_py              = base64gzip(file("${path.module}/../app/app.py"))
    service_unit        = base64gzip(file("${path.module}/../deploy/systemd/hello.service"))
    healthcheck_sh      = base64gzip(file("${path.module}/../deploy/healthcheck.sh"))
    healthcheck_service = base64gzip(file("${path.module}/../deploy/systemd/hello-healthcheck.service"))
    healthcheck_timer   = base64gzip(file("${path.module}/../deploy/systemd/hello-healthcheck.timer"))
    app_version         = var.app_version
  })


  user_data_replace_on_change = true

  # IMDSv2 only; hop limit 1 keeps containers on the host away from it.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  # t3 defaults to "unlimited", which can bill for burst CPU. Throttle instead.
  credit_specification {
    cpu_credits = "standard"
  }

  monitoring = false # detailed monitoring costs money; basic 5-min metrics are free

  root_block_device {
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  tags = {
    Name = var.project_name
  }

  lifecycle {
    # New AMIs come out often; don't replace the instance on every apply.
    ignore_changes = [ami]
  }
}
