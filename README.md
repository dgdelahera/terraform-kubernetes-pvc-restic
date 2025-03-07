<!-- BEGIN_TF_DOCS -->
# Terraform Kubernetes PVC Restic

This module provides an easy way to deploy Persistent Volume Claim (PVC) and a
Kubernetes cronjob to automatically backup the PVC to a remote storage.

### Supported Remote Storage

Currently there is only one remote storage supported. Feel free to open PR's to add support for others:

* Google Drive

## Providers

| Name | Version |
|------|---------|
| <a name="provider_kubernetes"></a> [kubernetes](#provider\_kubernetes) | n/a |
| <a name="provider_null"></a> [null](#provider\_null) | n/a |

## Inputs

- `metadata`: Object that contains the PVC configuration. It supports the following attributes:
  - `name`: Name of the PVC.
  - `storage_class`: (Optional) Storage class used to create the PVC. Defaults to the default storage class in the cluster.
  - `namespace`: (Optional) Namespace where the PVC is deployed. Defaults to `default`.
  - `storage`: (Optional) Size of the PVC. See the [Resource model](https://github.com/kubernetes/design-proposals-archive/blob/main/scheduling/resources.md)
  for valid values. Defaults to `2Gi`.
  - `node`: (Optional) Node where the PVC is deployed. This is requiered when using `local-path` storage class.
    See the [Kubernetes documentation](https://kubernetes.io/docs/reference/labels-annotations-taints/#volume-kubernetes-io-selected-node) for more information.
  - `access_modes`: (Optional) Access modes of the PVC. Valid values are `ReadWriteOnce`, `ReadWriteMany`, `ReadOnlyMany`. Defaults to [`ReadWriteOnce`].
- `backup`:   Object that contains the configuration for the backup. It supports the following attributes:
  - `schedule`: Restic schedule for the backups
  - `retries`: (Optional) Number of retries for the backup job. Defaults to 0
  - `restic_password`: (Optional) Restic password used to encrypt the backups. If not provided, the `--insecure-no-password` flag will be used.
  - `exclude_dirs`: (Optional) List of directories to exclude from the backup. It supports patterns like "config/transcodes"
  - `keep_last`: (Optional) Number of backups to keep. Defaults to 4
  - `remote`: (Optional) Object that contains the remote storage configuration. You must provide at least one of the following:
    - `gdrive`: (Optional) Object that contains the Google Drive configuration. It supports the following attributes:
      - `path`: (Optional) Path in Google Drive where the backups will be stored. Defaults to `/`
      - `token`: Access token for the Google Drive API. See the [rclone configuration](https://rclone.org/drive/) for more information 
        about how to get one.
- `restore`: (Optional) Object that contains the restore configuration. It supports the following attributes:
  - `enabled`: (Optional) If enabled, the backup will be restored from the snapshot. It only runs once. Defaults to false
  - `snapshot_id`: (Optional) ID of the snapshot to restore. If not provided, the latest snapshot will be used. Changing this
  value will force the recreation of the restore job.

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_pvc_name"></a> [pvc\_name](#output\_pvc\_name) | Name of the PVC created. If you are using the `WaitForFirstConsumer` storage class,<br/>  don't use this output. Terraform adds an implicit dependency to the PVC resource<br/>  so it will wait for the PVC to be created before creating the pod, resulting in a<br/>  circular dependency. |

## Using a Storage Class with WaitForFirstConsumer

If you are using a Storage Class with `WaitForFirstConsumer`, don't use the `pvc_name` output to mount
the PVC. The `WaitForFirstConsumer` volume binding mode will wait for the pod to be scheduled before
binding the PVC, and using the output will add a terraform dependency on the pod, which won't be created
until the PVC is bound. This will cause a circular dependency.

Instead, store the `pvc_name` in a local and use it in both places. (See the examples below)

## Rate limiting

To avoid hitting the rate limit of Google Drive, it is recommended to schedule the backups in different
hours if you are creating multiple backups.

## How to get the snapshot ID

To get the snapshot ID, you can use the `restic snapshots` command. This will list all the snapshots available
and the date of the snapshot.

```bash
restic -r rclone:gdrive:/my/path/backup snapshots
```

Additionally, you can check the backup cronjob logs to see the snapshot available.

## Examples

On the following example we are deploying a PVC and a cronjob to backup the PVC to Google Drive.
Note that we are storing the `pvc_name` in a local and using it in both the PVC and the cronjob
because we are using a Storage Class with `WaitForFirstConsumer`.

```hcl
locals {
  pvc_name = "example-basic"
}

module "pvc" {
  source  = "dgdelahera/pvc-restic/kubernetes"
  version = "1.4.0"

  pvc = {
    name = local.pvc_name
  }

  backup = {
    schedule        = "0 0 * * *"
    restic_password = "NotASecureP1ssword"
    exclude_dirs    = ["/foo", "/bar"]
    remote = {
      gdrive = {
        path  = "/Homelab/Backups"
        token = "NotASecureToken"
      }
    }
  }
}

# Create a dummy pod that consumes the PVC. This is used to trigger the PVC creation when using the `WaitForFirstConsumer` storage class.
resource "kubernetes_pod_v1" "dummy" {
  metadata {
    name = "example-terraform-pvc-restic"
  }
  spec {
    container {
      name    = "dummy"
      image   = "busybox"
      command = ["sh", "-c", "sleep 100"]
      volume_mount {
        name       = "test-pvc"
        mount_path = "/mnt/test-data"
      }
    }
    volume {
      name = "test-pvc"
      persistent_volume_claim {
        claim_name = local.pvc_name
      }
    }
  }
}
```

On the following example we are restoring the PVC from a Google Drive backup.

```hcl
module "pvc" {
  source  = "dgdelahera/pvc-restic/kubernetes"
  version = "1.4.0"

  pvc = {
    name = "example-restore"
  }

  backup = {
    schedule        = "0 0 * * *"
    restic_password = "NotASecureP1ssword"
    exclude_dirs    = ["/foo", "/bar"]
    remote = {
      gdrive = {
        path  = "/Homelab/Backups"
        token = "NotASecureToken"
      }
    }
  }

  restore = {
    enabled     = true
    snapshot_id = "081b201f"
  }
}
```
<!-- END_TF_DOCS -->