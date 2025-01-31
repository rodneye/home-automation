# Configure the Cloudflare provider.
# You may optionally use version directive to prevent breaking changes occurring unannounced.
terraform {
  required_providers {
    cloudflare = {
      source = "cloudflare/cloudflare"
      version = "3.31.0"
    }
  }
}

provider "cloudflare" { 
  api_token    = var.api_token
  account_id = var.account_id
}

# Create a records
resource "cloudflare_record" "alertmanager" {
  zone_id = var.zone_id
  name    = "alertmanager"
  value   = var.host
  type    = "A"
}

resource "cloudflare_record" "grafana" {
  zone_id = var.zone_id
  name    = "grafana"
  value   = var.host
  type    = "A"
}

resource "cloudflare_record" "heimdall" {
  zone_id = var.zone_id
  name    = "heimdall"
  value   = var.host
  type    = "A"
}

resource "cloudflare_record" "nginxmanager" {
  zone_id = var.zone_id
  name    = "nginxmanager"
  value   = var.host
  type    = "A"
}

resource "cloudflare_record" "portainer" {
  zone_id = var.zone_id
  name    = "portainer"
  value   = var.host
  type    = "A"
}

resource "cloudflare_record" "prometheus" {
  zone_id = var.zone_id
  name    = "prometheus"
  value   = var.host
  type    = "A"
}

resource "cloudflare_record" "adguard" {
  zone_id = var.zone_id
  name    = "adguard"
  value   = var.host
  type    = "A"
}

# Firewall Rules
resource "cloudflare_filter" "southafrica" {
  zone_id = var.zone_id
  description = "allow southafrica"
  expression = "ip.geoip.country ne \"ZA\""
}

resource "cloudflare_firewall_rule" "southafrica" {
  zone_id = var.zone_id
  description = "allow South Africa"
  filter_id = cloudflare_filter.southafrica.id
  action = "block"
}