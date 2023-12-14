# Copyright 2023 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

packer {
  required_plugins {
    googlecompute = {
      version = "= 1.1.1"
      source  = "github.com/hashicorp/googlecompute"
    }
  }
}

variable "project_id" {
  type = string
}

variable "zone" {
  type = string
}

variable "builder_sa" {
  type = string
}

variable "stig_artifacts_bucket" {
  type = string
}

variable "output_image_name" {
  type = string
}

source "googlecompute" "rhel-image" {
  project_id                  = var.project_id
  source_image_family         = "rhel-8"
  image_description           = "RHEL Image with STIG Profile"
  disk_name                   = "packer-rhel"
  image_name                  = var.output_image_name
  ssh_username                = "packer"
  zone                        = var.zone
  tags                        = ["stig"]
  service_account_email       = var.builder_sa
  impersonate_service_account = var.builder_sa
  disk_size                   = "20"
  machine_type                = "n2-standard-2"
  use_iap                     = true
  omit_external_ip            = true
  use_internal_ip             = true
  use_os_login                = false
  enable_secure_boot          = true
  enable_integrity_monitoring = true
  enable_vtpm                 = true
  scopes                      = [
    "https://www.googleapis.com/auth/userinfo.email",
    "https://www.googleapis.com/auth/compute",
    "https://www.googleapis.com/auth/devstorage.full_control"
  ]
}

build {
  sources = ["sources.googlecompute.rhel-image"]

  provisioner "shell" {
    script            = "fix-partitions.sh"
    execute_command   = "sudo sh -c '{{ .Vars }} {{ .Path }}' 2>&1 || true"
  }

  provisioner "shell" {
    environment_vars  = [
      "BUCKET=${var.stig_artifacts_bucket}",
      "IMAGE_NAME=${var.output_image_name}"
    ]
    script            = "remediate.sh"
    execute_command   = "sudo sh -c '{{ .Vars }} {{ .Path }}' 2>&1 || true"
  }

  provisioner "shell" {
    script            = "reboot.sh"
    remote_folder     = "/var/lib/google"
    execute_command   = "sudo sh -c '{{ .Vars }} {{ .Path }}' 2>&1 || true"
    expect_disconnect = true
    pause_after       = "2m"
  }

  provisioner "shell" {
    environment_vars  = [
      "BUCKET=${var.stig_artifacts_bucket}",
      "IMAGE_NAME=${var.output_image_name}"
    ]
    script            = "additional-configurations.sh"
    remote_folder     = "/var/lib/google"
    execute_command   = "sudo sh -c '{{ .Vars }} {{ .Path }}' 2>&1 || true"
  }
}
