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

sudo yum -y install openscap-scanner scap-security-guide-doc


# Test to see if the OVAL file can be downloaded.
# This sometimes errors with a 404, so skip download if it is
# currently failing

oscap info --fetch-remote-resources \
     /usr/share/xml/scap/ssg/content/ssg-rhel8-ds.xml &> /dev/null
retVal=$?

if [[ $retVal -gt 0 ]]
then
  FETCH_REMOTE=""
else
  FETCH_REMOTE="--fetch-remote-resources"
fi


# Generate lockdown script
sudo oscap xccdf generate fix \
  $FETCH_REMOTE \
  --profile stig \
  /usr/share/xml/scap/ssg/content/ssg-rhel8-ds.xml > disa-stig.sh


sudo gsutil cp disa-stig.sh "gs://${BUCKET}/${IMAGE_NAME}/"
