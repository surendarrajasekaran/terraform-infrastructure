terraform {
  required_version = ">= 1.10, < 2.0"
  required_providers {
    aws    = { source = "hashicorp/aws", version = "~> 5.100" }
    helm   = { source = "hashicorp/helm", version = "~> 3.3.0" }
    random = { source = "hashicorp/random", version = "~> 3.7" }
  }
}
