terraform {
  required_version = "~> 1.3"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "< 5.0, >= 3.83"
    }
  }

  provider_meta "google" {
    module_name = "blueprints/terraform/terraform-google-network:firewall-rules/v7.0.0"
  }
}
provider "google" {
  region      = "asia-southeast2"
  project     = "synergize-tech"
  credentials = file("synergize-tech.json")
  zone        = "asia-southeast2-a"
}

