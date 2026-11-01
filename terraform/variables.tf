variable "aws_region" {
  description = "AWS region (ap-south-1 = Mumbai)."
  type        = string
  default     = "ap-south-1"
}

variable "project_name" {
  description = "Prefix for resource names and the Project tag."
  type        = string
  default     = "hello-service"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,24}$", var.project_name))
    error_message = "Use 3-25 chars: lowercase letters, digits, hyphens."
  }
}

variable "instance_type" {
  description = "Free Tier x86 type. Accounts created after 15 Jul 2025: t3.micro. Older accounts: t2.micro where available."
  type        = string
  default     = "t3.micro"

  # Guardrail so a typo can't launch something billable.
  validation {
    condition     = contains(["t2.micro", "t3.micro"], var.instance_type)
    error_message = "Only t2.micro or t3.micro are allowed."
  }
}

variable "allowed_http_cidrs" {
  description = "CIDRs allowed to reach port 80. Use [\"<your-ip>/32\"] to restrict while testing."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "app_version" {
  description = "Version reported by /health. Changing it replaces the instance."
  type        = string
  default     = "1.0.0"
}

variable "alert_email" {
  description = "E-mail for CloudWatch alarm notifications. Empty = no e-mail, alarm still reboots."
  type        = string
  default     = ""
}
