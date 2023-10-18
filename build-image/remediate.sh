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

# Enable echo of commands as they execute for visibility in the logs
set -x

# retrieve the lockdown script that was generated in
# the `generate-lockdown-script` step
gsutil cp "gs://${BUCKET}/${IMAGE_NAME}/disa-stig.sh" /root/disa-stig.sh

# DISA STIG script will output to stderr and report some failures for 
#  some individual fixes. The `|| true` will allow the lockdown to continue
bash /root/disa-stig.sh 2>&1 || true


# Fix /boot/efi mount options
echo "fixing /boot/efi mount options"
mount_point_match_regexp="$(printf "[[:space:]]%s[[:space:]]" /boot/efi)"
if [[ "$(grep "$mount_point_match_regexp" /etc/fstab | grep -c "nosuid")" -eq 0 ]]; then
    previous_mount_opts=$(grep "$mount_point_match_regexp" /etc/fstab | awk '{print $4}')
    sed -i "s|\(${mount_point_match_regexp}.*${previous_mount_opts}\)|\1,nosuid|" /etc/fstab
    mount -o remount --target "/boot/efi"
fi


# Ensure google-sudoers is enabled with NOPASSWD option.
# This is to avoid hardcoded root passwords, and integrates with
# Google Cloud IAM for permission management.
echo "fixing google_sudoers file"
sed -i -e 's/# %google-sudoers/%google-sudoers/' /etc/sudoers.d/google_sudoers


# For startup-scripts set in metadata, Google Cloud by default uses /tmp
# On a locked-down system, /tmp has a 'noexec' flag, which causes a 
# permission-denied error on executing the startup-script.
# The following setting changes the startup script to use /var instead
echo "fixing Google startup-scripts run_dir location"
mkdir -p /var/lib/google
chmod 775 /var/lib/google
chown root:google-sudoers /var/lib/google
sed -i 's|run_dir =.*|run_dir = /var/lib/google|g' /etc/default/instance_configs.cfg
