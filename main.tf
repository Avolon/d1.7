terraform {
  required_providers {
    yandex = {
      source  = "yandex-cloud/yandex"
      version = "0.71.0"
    }
  }
}

provider "yandex" {
  token     = var.yandex_token
  cloud_id  = var.cloud_id
  folder_id = var.folder_id
  zone      = "ru-central1-a"
}

variable "ubuntu_image_id" {
  description = "Ubuntu image ID"
  type        = string
  default     = "fd8re3hiqnikqr7j7m8s" # Ubuntu 20.04 LTS
}

resource "yandex_vpc_network" "network" {
  name = "sock-shop-network"
}

resource "yandex_vpc_subnet" "subnet" {
  name           = "sock-shop-subnet"
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.network.id
  v4_cidr_blocks = ["10.2.0.0/24"]
}

resource "yandex_compute_instance" "manager" {
  name                      = "manager-node"
  hostname                  = "manager-node"
  zone                      = "ru-central1-a"
  allow_stopping_for_update = true
  platform_id               = "standard-v3"

  resources {
    cores         = 2
    memory        = 2
    core_fraction = 20
  }

  boot_disk {
    initialize_params {
      image_id = var.ubuntu_image_id
    }
  }

  network_interface {
    subnet_id = yandex_vpc_subnet.subnet.id
    nat       = true
  }

  metadata = {
    ssh-keys = "ubuntu:${file(var.public_key_path)}"
  }

  provisioner "remote-exec" {
    inline = [
      "curl -fsSL https://get.docker.com -o get-docker.sh",
      "sh get-docker.sh",
      "sudo usermod -aG docker ubuntu",
      "sudo systemctl enable docker",
      "sudo systemctl start docker",
      "sudo docker swarm init --advertise-addr $(hostname -I | awk '{print $1}')"
    ]
    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = file(var.private_key_path)
      host        = self.network_interface.0.nat_ip_address
    }
  }
}

resource "yandex_compute_instance" "worker" {
  count                    = 2
  name                     = "worker-node-${count.index + 1}"
  hostname                 = "worker-node-${count.index + 1}"
  zone                     = "ru-central1-a"
  allow_stopping_for_update = true
  platform_id              = "standard-v3"

  resources {
    cores         = 2
    memory        = 2
    core_fraction = 20
  }

  boot_disk {
    initialize_params {
      image_id = var.ubuntu_image_id
    }
  }

  network_interface {
    subnet_id = yandex_vpc_subnet.subnet.id
    nat       = true
  }

  metadata = {
    ssh-keys = "ubuntu:${file(var.public_key_path)}"
  }

  provisioner "remote-exec" {
    inline = [
      "curl -fsSL https://get.docker.com -o get-docker.sh",
      "sh get-docker.sh",
      "sudo usermod -aG docker ubuntu",
      "sudo systemctl enable docker",
      "sudo systemctl start docker"
    ]
    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = file(var.private_key_path)
      host        = self.network_interface.0.nat_ip_address
    }
  }
}

output "manager_node_ip" {
  value = yandex_compute_instance.manager.network_interface.0.nat_ip_address
}

output "worker_ips" {
  value = [for instance in yandex_compute_instance.worker : instance.network_interface.0.nat_ip_address]
}
