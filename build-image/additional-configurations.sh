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

# Any additional configuration needed after reboot can be executed here

# Install the Guest Environment
#  https://cloud.google.com/compute/docs/images/guest-environment

eval "$(grep VERSION_ID /etc/os-release)"
sudo tee /etc/yum.repos.d/google-cloud.repo << EOM
[google-compute-engine]
name=Google Compute Engine
baseurl=https://packages.cloud.google.com/yum/repos/google-compute-engine-el${VERSION_ID/.*}-x86_64-stable
enabled=1
gpgcheck=1
repo_gpgcheck=0
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg
      https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOM

sudo yum makecache
sudo yum updateinfo
sudo yum install -y google-compute-engine google-osconfig-agent


# Install the Google Cloud Ops Agent
#  https://cloud.google.com/stackdriver/docs/solutions/agents/ops-agent/installation

curl -sSO https://dl.google.com/cloudagents/add-google-cloud-ops-agent-repo.sh
sudo bash add-google-cloud-ops-agent-repo.sh --also-install
rm add-google-cloud-ops-agent-repo.sh

sudo tee /etc/google-cloud-ops-agent/config.yaml << EOM
# Copyright 2020 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# <== Enter custom agent configurations in this file.
# See https://cloud.google.com/stackdriver/docs/solutions/agents/ops-agent/configuration
# for more details.

logging:
  receivers:
    syslog:
      type: files
      include_paths:
      - /var/log/audit/audit.log
    journald:
      type: systemd_journald
  service:
    pipelines:
      default_pipeline:
        receivers: [syslog, journald]
metrics:
  receivers:
    hostmetrics:
      type: hostmetrics
      collection_interval: 60s
  processors:
    metrics_filter:
      type: exclude_metrics
      metrics_pattern: []
  service:
    pipelines:
      default_pipeline:
        receivers: [hostmetrics]
        processors: [metrics_filter]

EOM

# Disable rsyslog forwarding,
#  Google Cloud Ops Agent is fulfilling requirement CCE-27343-3
sudo sed -i -e 's/^\*\.\* @@logcollector/#\*\.\* @@logcollector/' \
      /etc/rsyslog.conf

# Configure ClamAV
sudo yum -y install \
        https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm
sudo yum -y install clamav clamav-update clamd
sudo setsebool -P antivirus_can_scan_system 1
sudo setsebool -P antivirus_use_jit 1
sudo setsebool -P daemons_use_tty 1

sudo sed -i -e 's/^#LocalSocket/LocalSocket/g' /etc/clamd.d/scan.conf
sudo sed -i -e 's/^#ExcludePath/ExcludePath/g' /etc/clamd.d/scan.conf
sudo sed -i -e '/ExcludePath \^\/sys\//a ExcludePath \^\/dev\/' \
                /etc/clamd.d/scan.conf
sudo sed -i -e 's/^#LogSyslog yes/LogSyslog yes/' /etc/freshclam.conf

# ClamAV needs additional SELinux permission to read the entire filesystem.
#  This may need additional permissions, depending on what software is
#  installed on the system, as additional types may be added that ClamAV
#  needs permission to read.
sudo tee /root/antivirus_custom.te << EOM
module antivirus_custom 1.0;

require {
        type auditd_etc_t;
        type auditd_log_t;
        type antivirus_t;
        type semanage_store_t;
        type shadow_t;
        type init_var_run_t;
        type default_context_t;
        type selinux_config_t;
        class file { getattr open read };
        class chr_file getattr;
        class blk_file getattr;
}

#============= antivirus_t ==============

allow antivirus_t auditd_etc_t:file { open getattr read };
allow antivirus_t auditd_log_t:file { open getattr read };
allow antivirus_t default_context_t:file { open getattr read };
allow antivirus_t selinux_config_t:file { open getattr read };
allow antivirus_t semanage_store_t:file { open getattr read };
allow antivirus_t shadow_t:file { open getattr read };
allow antivirus_t init_var_run_t:blk_file getattr;
allow antivirus_t init_var_run_t:chr_file getattr;
EOM

# Compile the module
sudo checkmodule -M -m -o /root/antivirus_custom.mod /root/antivirus_custom.te

# Create the package
sudo semodule_package -o /root/antivirus_custom.pp -m /root/antivirus_custom.mod

# Load the module into the kernel
sudo semodule -i /root/antivirus_custom.pp

# Create daily cronjob to execute scan
sudo tee /etc/cron.daily/clamscan.sh << "EOM"
#!/usr/bin/env bash

# Redirect all output to syslog
exec 1> >(logger -t antivirus) 2>&1

# Update antivirus database
freshclam --foreground --quiet

# Ensure clamd is running
systemctl status clamd@scan
if [[ "$?" -ne "0" ]]; then
  systemctl enable clamd@scan
  systemctl start clamd@scan
  if [[ "$?" -ne "0" ]]; then
    logger "ANTIVIRUS SCAN ERROR - Cannot start clamav"
  fi
fi

# Tell clamd to reload the antivirus database
clamdscan --reload

# Begin scan
clamdscan --multiscan --fdpass /

EOM
sudo chmod 755 /etc/cron.daily/clamscan.sh

# Remove TMUX lock timeout
#  User management with oslogin provisions SSH keys for authentication rather
#  than passwords.  Tmux session locking creates an uncoverable session, since
#  no password is set.  Instead of tmux session locking, systemd-logind is used
#  to terminate idle sessions (StopIdleSessionSec setting in
#  /etc/systemd/logind.conf)
sudo sed -i -e '/lock/d' /etc/tmux.conf
sudo rm /etc/profile.d/tmux.sh

# Reset audit logs and users
sudo truncate -s 0 /var/log/messages
sudo rm /var/log/audit/audit.log.*
sudo truncate -s 0 /var/log/audit/audit.log
ls /home | xargs -l userdel -rf
rm -rf /etc/ssh/ssh_host_*_key*

echo "${0} script complete."

