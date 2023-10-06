# Enterprise Linux STIG Builder

## Purpose

The Enterprise Linux STIG Builder project is a Google Cloud Build automation 
to produce a [DISA STIG][disa-stig]-compliant RHEL 8 image, as well as an
[OpenSCAP][openscap] Compliance report.

[disa-stig]: https://public.cyber.mil/stigs/

[openscap]: https://www.open-scap.org/

There are three separate Cloud Builds to support this automation:

### Packer Cloud Builder
The Packer Cloud Builder creates a [HashiCorp Packer][packer] builder image
for use in [Google Cloud Build][cloud-build].

Arguments passed to this builder will be passed to `packer` directly, allowing
callers to run [any Packer command][packer-commands].

[cloud-build]: https://cloud.google.com/cloud-build

[packer]: https://www.packer.io

[packer-commands]: https://developer.hashicorp.com/packer/docs/commands


### Build Image

The `build-image` cloud build instantiates a GCE Instance with the latest
RHEL-8 public image, and applies a configuration intended to be compliant
with the DISA STIG.  It then creates a private image from the instance
disk.

### Evaluate Image

The `evaluate-image` cloud build instantiates a new GCE Instance with the
output of the `build-image` step, produces an OpenSCAP evaluation report,
and uploads it to GCS in the configured bucket.

## Setup

### Cloud Build Setup

Create Service Account

```
export PROJECT_ID=example-project-id
export GCP_ZONE=us-central1-c


gcloud auth login
gcloud config set project $PROJECT_ID


export PROJECT_NUMBER=`gcloud projects list --filter="$PROJECT_ID" \
  --format="value(PROJECT_NUMBER)"`


# Create Service Account for Packer

gcloud iam service-accounts create packer \
  --project $PROJECT_ID \
  --description="Packer Service Account" \
  --display-name="Packer Service Account"


# Grant roles to Packer's Service Account

gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member=serviceAccount:packer@${PROJECT_ID}.iam.gserviceaccount.com \
    --role=roles/compute.instanceAdmin.v1
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member=serviceAccount:packer@${PROJECT_ID}.iam.gserviceaccount.com \
    --role=roles/iam.serviceAccountUser


# Allow the Packer Service Account to use IAP Tunnels

gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member=serviceAccount:packer@${PROJECT_ID}.iam.gserviceaccount.com \
    --role=roles/iap.tunnelResourceAccessor


# Allow CloudBuild to impersonate Packer service account

gcloud iam service-accounts add-iam-policy-binding \
  packer@${PROJECT_ID}.iam.gserviceaccount.com \
  --role="roles/iam.serviceAccountTokenCreator" \
  --member="serviceAccount:${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com"


# Allow CloudBuild to use IAP Tunnels (for STIG evaluation)

gcloud projects add-iam-policy-binding $PROJECT_ID \
    --role=roles/iap.tunnelResourceAccessor \
    --member=serviceAccount:${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com
```

## Internet Access

The `generate-lockdown-script` step downloads the OVAL file from Red Hat to
retrieve the latest CVEs.  For this to work, internet access must be provided
within the VPC, by creating a [Cloud Router][cloud-router] and a
[NAT Gateway][nat-gateway]

Example of how to create a Cloud Router and NAT Gateway:
```
gcloud compute routers create router1 \
  --project=$PROJECT_ID \
  --network=default \
  --asn=64512 \
  --region=$REGION

gcloud compute routers nats create nat1 \
  --router=router1 \
  --region=$REGION \
  --auto-allocate-nat-external-ips \
  --nat-all-subnet-ip-ranges \
  --enable-logging
```

[cloud-router]: https://cloud.google.com/network-connectivity/docs/router/how-to/create-router-vpc-network#gcloud

[nat-gateway]: https://cloud.google.com/nat/docs/set-up-manage-network-address-translation


## Execution using Makefile

### Edit Variables in Makefile

Example content:

```
DATE  != date "+%Y-%m-%d-%H%M%S"
IMAGE_NAME = rhel8-stig-${DATE}
PROJECT_ID = example-project-id
PROJECT_NUMBER = 123456789012
ZONE = us-central1-c
BUILDER_SA = packer@example-project-id.iam.gserviceaccount.com
```

### Create Packer Builder

The packer cloud builder needs to exist in the registry for the project.
This step must be completed only once per project.

```
make builder
```

### Execute Build

The Makefile defines targets for `build`, `evaluate`, and `rebuild`, where:

`build`: creates RHEL-8 STIG Image\
`evaluate`: produces an OpenSCAP Report of the STIG Image\
`rebuild`: executes `build` and `evaluate` in sequence

```
make rebuild
```

## License

This source code is licensed under Apache 2.0. Full license text is available
in [LICENSE](LICENSE).

## Contributing

We welcome contributions!  See [CONTRIBUTING](CONTRIBUTING.md) for more information on how to get started.

