#!/usr/bin/env bash
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

gcloud compute disks resize packer-rhel --size=100GB  --zone=us-central1-c -q 2>&1

sudo yum install -y rsync
sudo yum clean all

sed -e 's/\s*\([\+0-9a-zA-Z]*\).*/\1/' << EOF | sudo fdisk /dev/sda 2>&1
  n # new partition
    # default partition number (3)
    # default, start immediately after preceding partition
  +10G # 10 GB /var partition
  n # new partition
    # default partition number (4)
    # default, start immediately after preceding partition
  +10G  # 10 GB /var/log partition
  n # new partition
    # default partition number (5)
    # default, start immediately after preceding partition
  +10G  # 10 GB /var/log/audit partition
  n # new partition
    # default partition number (6)
    # default, start immediately after preceding partition
  +5G  # 5 GB /var/tmp partition
  n # new partition
    # default partition number (7)
    # default, start immediately after preceding partition
  +20G  # 20 GB /usr partition
  n # new partition
    # default partition number (8)
    # default, start immediately after preceding partition
  +5G  # 5 GB /tmp partition
  n # new partition
    # default partition number (9)
    # default, start immediately after preceding partition
    # default, use rest of the disk (20G)
  w # write the partition table
EOF


# create /var, /var/log, /var/tmp /var/log/audit
sudo mkfs.xfs /dev/sda3
sudo mkfs.xfs /dev/sda4
sudo mkfs.xfs /dev/sda5
sudo mkfs.xfs /dev/sda6
sudo mount /dev/sda3 /mnt
sudo mkdir /mnt/log
sudo mount /dev/sda4 /mnt/log
sudo mkdir /mnt/log/audit
sudo mount /dev/sda5 /mnt/log/audit
sudo mkdir /mnt/tmp
sudo mount /dev/sda6 /mnt/tmp
cd /
sudo rsync -aAX var/ /mnt
sudo umount /mnt/log/audit
sudo umount /mnt/log
sudo umount /mnt/tmp
sudo umount /mnt

# create /usr
sudo mkfs.xfs /dev/sda7
sudo mount /dev/sda7 /mnt
cd /
sudo rsync -aAX usr/ /mnt
sudo umount /mnt

# create /tmp
sudo mkfs.xfs /dev/sda8
sudo mount /dev/sda8 /mnt
cd /
sudo rsync -aAX tmp/ /mnt
sudo umount /mnt

# create /home
sudo mkfs.xfs /dev/sda9
sudo mount /dev/sda9 /mnt
cd /
sudo rsync -aAX home/ /mnt
sudo umount /mnt

# Update fstab
sudo cp /etc/fstab /etc/fstab.orig
echo -e "UUID=$(lsblk -no UUID /dev/sda3)\t/var\txfs\tdefaults\t0 0" | sudo tee -a /etc/fstab
echo -e "UUID=$(lsblk -no UUID /dev/sda4)\t/var/log\txfs\tdefaults\t0 0" | sudo tee -a /etc/fstab
echo -e "UUID=$(lsblk -no UUID /dev/sda5)\t/var/log/audit\txfs\tdefaults\t0 0" | sudo tee -a /etc/fstab
echo -e "UUID=$(lsblk -no UUID /dev/sda6)\t/var/tmp\txfs\tdefaults\t0 0" | sudo tee -a /etc/fstab
echo -e "UUID=$(lsblk -no UUID /dev/sda7)\t/usr\txfs\tdefaults\t0 0" | sudo tee -a /etc/fstab
echo -e "UUID=$(lsblk -no UUID /dev/sda8)\t/tmp\txfs\tdefaults\t0 0" | sudo tee -a /etc/fstab
echo -e "UUID=$(lsblk -no UUID /dev/sda9)\t/home\txfs\tdefaults\t0 0" | sudo tee -a /etc/fstab
sudo mount -a
sudo systemctl daemon-reload

# clean up old files
sudo mount --bind / /mnt
sudo rm -rf /mnt/var/*
sudo rm -rf /mnt/usr/*
sudo rm -rf /mnt/home/*
sudo rm -rf /mnt/tmp/*
sudo umount /mnt

# relabel SELinux
sudo touch /.autorelabel
