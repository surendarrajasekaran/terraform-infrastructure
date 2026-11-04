terraform {
  required_version = ">= 1.10, < 2.0"
  required_providers {
    helm   = { source = "hashicorp/helm", version = "~> 3.3.0" }
    google = { source = "hashicorp/google", version = "~> 6.50" }
    random = { source = "hashicorp/random", version = "~> 3.7" }
  }
}
