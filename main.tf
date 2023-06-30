# create VPC
resource "google_compute_network" "vpc" {
  name                    = "vpc-test"
  auto_create_subnetworks = false
}

# Create Subnet
resource "google_compute_subnetwork" "subnet" {
  name          = "subnet-test"
  region        = "asia-southeast2"
  network       = google_compute_network.vpc.name
  ip_cidr_range = "10.0.0.0/24"
}



# Create GKE cluster with 2 nodes in our custom VPC/Subnet
resource "google_container_cluster" "primary" {
  name                     = "synergize-cluster-1"
  location                 = "asia-southeast2-a"
  network                  = google_compute_network.vpc.name
  subnetwork               = google_compute_subnetwork.subnet.name
  remove_default_node_pool = true 
  initial_node_count = 1

  private_cluster_config {
    enable_private_endpoint = true
    enable_private_nodes    = true
    master_ipv4_cidr_block  = "10.1.0.0/28"
  }
  ip_allocation_policy {
    cluster_ipv4_cidr_block  = "10.2.0.0/21"
    services_ipv4_cidr_block = "10.3.0.0/21"
  }
  master_authorized_networks_config {
    cidr_blocks {
      cidr_block   = "10.0.0.10/32"
      display_name = "conn1"
    }

  }
}

# Create managed node pool
resource "google_container_node_pool" "primary_nodes" {
  name       = google_container_cluster.primary.name
  location   = "asia-southeast2-a"
  cluster    = google_container_cluster.primary.name
  node_count = 3

  node_config {
    oauth_scopes = [
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring",
    ]

    labels = {
      env = "testing"
    }

    machine_type = "n1-standard-1"
    disk_size_gb = 30
    preemptible  = true

    metadata = {
      disable-legacy-endpoints = "true"
    }
  }
}



## Create jump host . We will allow this jump host to access GKE cluster. the ip of this jump host is already authorized to allowin the GKE cluster

resource "google_compute_address" "jumphost_ip_addr" {
  project      = "synergize-tech"
  address_type = "INTERNAL"
  region       = "asia-southeast2"
  subnetwork   = google_compute_subnetwork.subnet.name
  name         = "ip-jumhost"
  address      = "10.0.0.10"
  description  = "An internal IP address for my jump host"
}

resource "google_compute_instance" "vm_jumphost" {
  project        = "synergize-tech"
  zone           = "asia-southeast2-a"
  name           = "jump-host"
  machine_type   = "e2-medium"
  can_ip_forward = true

  boot_disk {
    initialize_params {
      image = "ubuntu-2004-focal-arm64-v20230628"
      size  = 50
    }
  }
  network_interface {
    network    = google_compute_network.vpc.name
    subnetwork = google_compute_subnetwork.subnet.name
    network_ip = google_compute_address.jumphost_ip_addr.address

  }

}

# Create VM Postgresql
resource "google_compute_address" "internal_ip_postgres" {
  project      = "synergize-tech"
  address_type = "INTERNAL"
  region       = "asia-southeast2"
  subnetwork   = google_compute_subnetwork.subnet.name
  name         = "ip-postgres"
  address      = "10.0.0.8"
  description  = "An internal IP address for my postgres"
}

resource "google_compute_instance" "wm_postgres" {
  project        = "synergize-tech"
  zone           = "asia-southeast2-a"
  name           = "postgres"
  machine_type   = "e2-medium"

  boot_disk {
    initialize_params {
      image = "ubuntu-2004-focal-arm64-v20230628"
      size  = 50
    }
  }
  network_interface {
    network    = google_compute_network.vpc.name
    subnetwork = google_compute_subnetwork.subnet.name
    network_ip = google_compute_address.internal_ip_postgres.address

  }

}

# Create VM Redis
resource "google_compute_address" "internal_ip_redis" {
  project      = "synergize-tech"
  address_type = "INTERNAL"
  region       = "asia-southeast2"
  subnetwork   = google_compute_subnetwork.subnet.name
  name         = "ip-redis"
  address      = "10.0.0.9"
  description  = "An internal IP address for my redis"
}

resource "google_compute_instance" "vm_redis" {
  project        = "synergize-tech"
  zone           = "asia-southeast2-a"
  name           = "redis"
  machine_type   = "e2-medium"

  boot_disk {
    initialize_params {
      image = "ubuntu-2004-focal-arm64-v20230628"
      size  = 50
    }
  }
  network_interface {
    network    = google_compute_network.vpc.name
    subnetwork = google_compute_subnetwork.subnet.name
    network_ip = google_compute_address.internal_ip_redis.address

  }

}

## Creare Firewall to access jump host via iap


resource "google_compute_firewall" "default" {
  project = "synergize-tech"
  name    = "allow-ssh"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
  source_ranges = ["35.235.240.0/20"]
}

resource "google_compute_firewall" "internal_rules" {
  project = "synergize-tech"
  name    = "allow-all-internal"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }
  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }
  allow {
    protocol = "icmp"
  }
  source_ranges = ["10.0.0.0/24"]
}



## Create IAP SSH permissions for your test instance

resource "google_project_iam_member" "project" {
  project  = "synergize-tech"
  role     = "roles/iap.tunnelResourceAccessor"
  member   = "serviceAccount:synergize@synergize-tech.iam.gserviceaccount.com"
}
resource "google_iap_tunnel_instance_iam_member" "instance" {
  instance = "jump-host"
  zone     = "asia-southeast2-a"
  role     = "roles/iap.tunnelResourceAccessor"
  member   = "serviceAccount:synergize@synergize-tech.iam.gserviceaccount.com"
  depends_on = [google_compute_instance.vm_jumphost]
}

# create cloud router for nat gateway
resource "google_compute_router" "router" {
  project = "synergize-tech"
  name    = "nat-router"
  network = google_compute_network.vpc.name
  region  = "asia-southeast2"
}

## Create Nat Gateway with module

module "cloud-nat" {
  source     = "terraform-google-modules/cloud-nat/google"
  version    = "~> 1.2"
  project_id = "synergize-tech"
  region     = "asia-southeast2"
  router     = google_compute_router.router.name
  name       = "nat-config"

}


############Output############################################
output "kubernetes_cluster_host" {
  value       = google_container_cluster.primary.endpoint
  description = "GKE Cluster Host"
}

output "kubernetes_cluster_name" {
  value       = google_container_cluster.primary.name
  description = "GKE Cluster Name"
}

# Create Storage For Static Website

resource "random_id" "bucket_prefix" {
  byte_length = 10
}

resource "google_storage_bucket" "static_website" {
  name          = "${random_id.bucket_prefix.hex}-static-website-bucket"
  location      = "asia-southeast2"
  storage_class = "STANDARD"
  website {
    main_page_suffix = "index.html"
    not_found_page   = "404.html"
  }
}

resource "google_storage_bucket_access_control" "public_rule" {
  bucket = google_storage_bucket.static_website.id
  role   = "READER"
  entity = "allUsers"
}

resource "google_storage_bucket_object" "indexpage" {
  name         = "index.html"
  content      = "<html><body>Hello World!</body></html>"
  content_type = "text/html"
  bucket       = google_storage_bucket.static_website.id
}

# Upload a simple 404 / error page to the bucket
resource "google_storage_bucket_object" "errorpage" {
  name         = "404.html"
  content      = "<html><body>404!</body></html>"
  content_type = "text/html"
  bucket       = google_storage_bucket.static_website.id
}