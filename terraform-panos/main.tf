# ── Palo Alto VM-Series policy as code ───────────────────────────────────────
# A separate root module so it can run AFTER the firewall boots and its
# management plane is reachable (the appliance is not up during the infra
# apply). It configures the security posture on the running VM-Series with the
# official panos provider, the same way you would manage any cloud resource.
#
# Usage (after `terraform apply` in ../terraform brings the VM-Series up):
#   export PANOS_HOSTNAME=<firewall_mgmt_ip>
#   export PANOS_USERNAME=admin
#   export PANOS_PASSWORD=<your-admin-password>
#   terraform init && terraform apply
#
# The rules below implement least-privilege egress for the protected jump host:
# permit DNS + updates outbound, deny everything else, log both.

terraform {
  required_version = ">= 1.6"

  required_providers {
    panos = {
      source  = "PaloAltoNetworks/panos"
      version = "~> 1.11"
    }
  }
}

# Reads PANOS_HOSTNAME / PANOS_USERNAME / PANOS_PASSWORD from the environment.
provider "panos" {}

# --- Zones ---
resource "panos_zone" "trust" {
  name = "trust"
  mode = "layer3"
}

resource "panos_zone" "untrust" {
  name = "untrust"
  mode = "layer3"
}

# --- Least-privilege egress from the protected subnet ---
resource "panos_security_policy" "egress" {
  rule {
    name                  = "allow-dns-out"
    source_zones          = [panos_zone.trust.name]
    destination_zones     = [panos_zone.untrust.name]
    source_addresses      = ["any"]
    source_users          = ["any"]
    categories            = ["any"]
    destination_addresses = ["any"]
    applications          = ["dns"]
    services              = ["application-default"]
    action                = "allow"
    log_end               = true
  }

  rule {
    name                  = "allow-updates-out"
    source_zones          = [panos_zone.trust.name]
    destination_zones     = [panos_zone.untrust.name]
    source_addresses      = ["any"]
    source_users          = ["any"]
    categories            = ["any"]
    destination_addresses = ["any"]
    applications          = ["ssl", "web-browsing", "apt-get", "ntp"]
    services              = ["application-default"]
    action                = "allow"
    log_end               = true
  }

  rule {
    name                  = "deny-all"
    source_zones          = [panos_zone.trust.name]
    destination_zones     = [panos_zone.untrust.name]
    source_addresses      = ["any"]
    source_users          = ["any"]
    categories            = ["any"]
    destination_addresses = ["any"]
    applications          = ["any"]
    services              = ["any"]
    action                = "deny"
    log_end               = true
  }
}
