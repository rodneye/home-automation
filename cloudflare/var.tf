variable "email" {
  description = "email for account"
  default     = "<XXXXXXXXXX>"
}

variable "account_id" {
  description = "account_id for account stored in TF Cloud variables"
}

variable "zone_id" {
  description = "api_token for account"
  default     = "<CLOUDFLARE_ZONE_ID>"    
}

variable "api_token" {
  description = "api_token for account stored in TF Cloud variables"
}

variable "host" {
  description = "api_token for account"
  default     = "<NGINX-PROXY-IP>"    
}