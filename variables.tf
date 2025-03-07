variable "pvc" {
  type = object({
    name          = string
    storage_class = optional(string, "")
    namespace     = optional(string, "default")
    storage       = optional(string, "2Gi")
    node          = optional(string)
    access_modes  = optional(list(string), ["ReadWriteOnce"])
  })
  description = <<-EOF
  Object that contains the PVC configuration. It supports the following attributes:
  - name: Name of the PVC.
  - storage_class: (Optional) Storage class used to create the PVC. Defaults to the default storage class in the cluster.
  - namespace:(Optional) Namespace where the PVC is deployed. Defaults to `default`.
  - storage: (Optional) Size of the PVC. See the [Resource model](https://github.com/kubernetes/design-proposals-archive/blob/main/scheduling/resources.md) for valid values. Defaults to `2Gi`.
  - node: (Optional) Node where the PVC is deployed. This is requiered when using `local-path` storage class.
    See the [Kubernetes documentation](https://kubernetes.io/docs/reference/labels-annotations-taints/#volume-kubernetes-io-selected-node) for more information.
  - access_modes: (Optional) Access modes of the PVC. Valid values are `ReadWriteOnce`, `ReadWriteMany`, `ReadOnlyMany`. Defaults to [`ReadWriteOnce`].
  EOF

  validation {
    condition     = alltrue([for access_mode in var.pvc.access_modes : contains(["ReadWriteOnce", "ReadWriteMany", "ReadOnlyMany"], access_mode)])
    error_message = "Access modes must be one of the following: ReadWriteOnce, ReadWriteMany, ReadOnlyMany."
  }

  validation {
    condition     = var.pvc.storage_class == "local-path" ? var.pvc.node != "" : true
    error_message = "Node is required when using local-path storage class."
  }

  validation {
    condition     = can(regex("^[0-9]+(([EPTGMK]i)|[EPTGMKm])?$", var.pvc.storage))
    error_message = <<EOF
    Storage quantities must be represented externally as unadorned integers, or as fixed-point integers with one
    of these SI suffices (E, P, T, G, M, K, m) or their power-of-two equivalents (Ei, Pi, Ti, Gi, Mi, Ki).
    EOF
  }
}

variable "backup" {
  type = object({
    schedule        = string
    retries         = optional(number, 0)
    restic_password = optional(string)
    exclude_dirs    = optional(list(string), [])
    keep_last       = optional(number, 4)
    remote = object({
      gdrive = optional(object({
        path  = optional(string, "/")
        token = string
      }))
    })
  })
  description = <<-EOF
  Object that contains the configuration for the backup. It supports the following attributes:
  - schedule: Restic schedule for the backups
  - retries: (Optional) Number of retries for the backup job. Defaults to 0
  - restic_password: (Optional) Restic password used to encrypt the backups. If not provided, the `--insecure-no-password` flag will be used.
  - exclude_dirs: (Optional) List of directories to exclude from the backup. It supports patterns like "config/transcodes"
  - keep_last: (Optional) Number of backups to keep. Defaults to 4
  - remote: (Optional) Object that contains the remote storage configuration. You must provide at least one of the following:
    - gdrive: (Optional) Object that contains the Google Drive configuration. It supports the following attributes:
      - path: (Optional) Path in Google Drive where the backups will be stored. Defaults to `/`
      - token: Access token for the Google Drive API. See the [rclone configuration](https://rclone.org/drive/) for more information 
        about how to get one.
  EOF

  validation {
    condition     = var.backup.remote.gdrive != null
    error_message = "One of the remote storage is required."
  }
}

variable "restore" {
  type = object({
    enabled     = optional(bool, false)
    snapshot_id = optional(string)
  })
  description = <<-EOF
  (Optional) Object that contains the restore configuration. It supports the following attributes:
  - enabled: (Optional) If enabled, the backup will be restored from the snapshot. It only runs once. Defaults to false
  - snapshot_id: (Optional) ID of the snapshot to restore. If not provided, the latest snapshot will be used. Changing this
  value will force the recreation of the restore job.
  EOF

  default = {}
}
