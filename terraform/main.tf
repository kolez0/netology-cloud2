resource "yandex_vpc_network" "netology_vpc" {
  name = var.netology_vpc
}

resource "yandex_vpc_subnet" "public" {
  name           = "public"
  zone           = var.default_zone
  network_id     = yandex_vpc_network.netology_vpc.id
  v4_cidr_blocks = var.netology_public_subnet
}

resource "yandex_iam_service_account" "instance_group_sa" {
  name        = "instance-group-sa"
  folder_id   = var.folder_id
}

resource "yandex_resourcemanager_folder_iam_member" "instance_group_sa_roles" {
  for_each = toset([
    "storage.viewer",
    "vpc.user",
    "compute.editor",
    "load-balancer.editor",
    "monitoring.editor",
    "vpc.publicAdmin",
  ])

  folder_id = var.folder_id
  role      = each.key
  member    = "serviceAccount:${yandex_iam_service_account.instance_group_sa.id}"
}

resource "yandex_storage_bucket" "bucket" {
  bucket     = var.bucket_name
  folder_id  = var.folder_id
  access_key = null 
}

resource "yandex_storage_bucket_grant" "public_read" {
  bucket = yandex_storage_bucket.bucket.id

  grant {
    uri         = "http://acs.amazonaws.com/groups/global/AllUsers"
    permissions = ["READ"]
    type        = "Group"
  }

  depends_on = [yandex_storage_bucket.bucket]
}

resource "yandex_storage_object" "image" {
  bucket      = yandex_storage_bucket.bucket.id
  key         = "image.jpg"
  source      = var.image_path
  acl         = "public-read"
  depends_on  = [yandex_storage_bucket.bucket]
}


resource "yandex_compute_instance_group" "lamp_group" {
  name               = "lamp-instance-group"
  folder_id          = var.folder_id
  service_account_id = yandex_iam_service_account.instance_group_sa.id

  instance_template {
    platform_id = var.vm_platform_id

    resources {
      cores  = var.vms_resources["public_vm"].cores
      memory = var.vms_resources["public_vm"].memory
    }

    boot_disk {
      initialize_params {
        image_id = "fd827b91d99psvq5fjit" 
        size     = var.vms_resources["public_vm"].disk_size
        type     = "network-hdd"
      }
    }

    network_interface {
      network_id = yandex_vpc_network.netology_vpc.id
      subnet_ids = [yandex_vpc_subnet.public.id]
      nat        = var.vms_resources["public_vm"].nat
    }

    metadata = {
      ssh-keys = "${var.vm_user}:${file(var.ssh_public_key_path)}"
       user-data = <<-EOF
        #cloud-config
        runcmd:
          - |
            IP=$(curl -s -H "Metadata-Flavor: Google" http://169.254.169.254/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip)
            cat <<HTML > /var/www/html/index.html
            <!DOCTYPE html>
            <html lang="ru">
            <head>
              <meta charset="utf-8">
              <title>LAMP + Object Storage</title>
            </head>
            <body>
              <h1>Ответ от ВМ с IP: $IP</h1>
              <p>Картинка из бакета Object Storage:</p>
              <img src="https://storage.yandexcloud.net/${yandex_storage_bucket.bucket.bucket}/image.jpg"
                   alt="RoboCat" width="600">
            </body>
            </html>
            HTML
      EOF
      }
    }
  
  timeouts {
    create = "40m"
    update = "40m"
    delete = "20m"
  }

  scale_policy {
    fixed_scale {
      size = 3
    }
  }

  allocation_policy {
    zones = [var.default_zone]
  }

  deploy_policy {
    max_unavailable = 1
    max_creating    = 1
    max_expansion   = 1
    max_deleting    = 1
  }

  health_check {
    interval            = 60
    timeout             = 20
    healthy_threshold   = 3
    unhealthy_threshold = 5
    http_options {
      port = 80
      path = "/"
    }
  }

  depends_on = [
    yandex_resourcemanager_folder_iam_member.instance_group_sa_roles,
    yandex_storage_object.image,
  ]
}

resource "yandex_lb_target_group" "lb_target_group" {
  name      = "lamp-target-group"
  folder_id = var.folder_id
  region_id = "ru-central1"

  dynamic "target" {
    for_each = yandex_compute_instance_group.lamp_group.instances[*].network_interface[0].ip_address
    content {
      subnet_id = yandex_vpc_subnet.public.id
      address   = target.value
    }
  }
}

resource "yandex_lb_network_load_balancer" "nlb" {
  name      = "lamp-nlb"
  folder_id = var.folder_id

  listener {
    name        = "http"
    port        = 80
    target_port = 80
    protocol    = "tcp"
    external_address_spec {
      ip_version = "ipv4"
    }
  }

  attached_target_group {
    target_group_id = yandex_lb_target_group.lb_target_group.id

    healthcheck {
      name = "http-check"
      http_options {
        port = 80
        path = "/"
      }
      interval            = 30
      timeout             = 10
      healthy_threshold   = 2
      unhealthy_threshold = 2
    }
  }
}