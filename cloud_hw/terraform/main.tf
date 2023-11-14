terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
    }
  }
  required_version = ">= 0.13"
}

provider "yandex" {
  service_account_key_file = "./key.json"
  folder_id                = local.folder_id
  zone                     = local.zone
}

data "yandex_vpc_network" "foo" {
  network_id = "enp9dckkdc3d2bctujsl"
}

data "yandex_vpc_subnet" "foo" {
  subnet_id = "e9bhbi90cm2vac4rm89i"
}

locals {
  zone      = "ru-central1-a"
  folder_id = "b1gre325j3po0m6040ie"
  service-accounts = toset([
    "catgpt-sa-olada",
  ])
  catgpt-sa-roles = toset([
    "container-registry.images.puller",
    "monitoring.editor",
  ])
}
resource "yandex_iam_service_account" "service-accounts" {
  for_each = local.service-accounts
  name     = each.key
}
resource "yandex_resourcemanager_folder_iam_member" "catgpt-roles" {
  for_each  = local.catgpt-sa-roles
  folder_id = local.folder_id
  member    = "serviceAccount:${yandex_iam_service_account.service-accounts["catgpt-sa-olada"].id}"
  role      = each.key
}

data "yandex_compute_image" "coi" {
  family = "container-optimized-image"
}

resource "yandex_iam_service_account" "ig-sa" {
  name        = "ig-sa-olada666"
  description = "service account to manage IG"
}

resource "yandex_resourcemanager_folder_iam_binding" "editor" {
  folder_id = local.folder_id
  role      = "editor"
  members = [
    "serviceAccount:${yandex_iam_service_account.ig-sa.id}",
  ]
  depends_on = [
    yandex_iam_service_account.ig-sa,
  ]
}

resource "yandex_compute_instance_group" "catgpt" {
  depends_on = [yandex_resourcemanager_folder_iam_binding.editor]

  folder_id          = local.folder_id
  service_account_id = yandex_iam_service_account.ig-sa.id

  instance_template {
    platform_id        = "standard-v2"
    service_account_id = yandex_iam_service_account.service-accounts["catgpt-sa-olada"].id

    resources {
      cores         = 2
      memory        = 1
      core_fraction = 5
    }
    scheduling_policy {
      preemptible = true
    }
    network_interface {
      network_id = data.yandex_vpc_network.foo.id
      subnet_ids = ["${data.yandex_vpc_subnet.foo.id}"]
      #nat        = true
    }
    boot_disk {
      initialize_params {
        type     = "network-hdd"
        size     = "30"
        image_id = data.yandex_compute_image.coi.id
      }
    }
    metadata = {
      docker-compose = file("${path.module}/docker-compose.yaml")
      ssh-keys  = "ubuntu:${file("~/.ssh/devops_train.pub")}"
    }
  }

  scale_policy {
    fixed_scale {
      size = 2
    }
  }

  allocation_policy {
    zones = [local.zone]
  }

  deploy_policy {
    max_unavailable = 1
    max_creating    = 1
    max_expansion   = 1
    max_deleting    = 1
  }
}

resource "yandex_lb_target_group" "foo" {
  name      = "catgpt-nb-group"
  target {
    subnet_id = "${data.yandex_vpc_subnet.foo.id}"
    address   = "${yandex_compute_instance_group.catgpt.instances[0].network_interface[0].ip_address}"
  }
  target {
    subnet_id = "${data.yandex_vpc_subnet.foo.id}"
    address   = "${yandex_compute_instance_group.catgpt.instances[1].network_interface[0].ip_address}"
  }
}


resource "yandex_lb_network_load_balancer" "foo" {
  name = "catgpt-nlb"
  listener {
    name = "catgpt-network-balancer"
    port = 8080
    external_address_spec {}
  }
  attached_target_group {
    target_group_id = "${yandex_lb_target_group.foo.id}"
    healthcheck {
      name = "http"
      http_options {
        port = 8080
        path = "/ping"
      }
    }
  }
}

resource "yandex_vpc_gateway" "nat_gateway" {
  name = "test-gateway"
  shared_egress_gateway {}
}

resource "yandex_vpc_route_table" "rt" {
  name       = "test-route-table"
  network_id = "enp9dckkdc3d2bctujsl"

  static_route {
    destination_prefix = "0.0.0.0/0"
    gateway_id         = yandex_vpc_gateway.nat_gateway.id
  }
}
