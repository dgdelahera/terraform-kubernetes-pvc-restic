locals {
  restic_image     = "tofran/restic-rclone:0.17.3_1.68.2" # Restic image doesn't have rclone
  pvc_volume_mount = "/mnt/${var.pvc.name}-data"
  drive_path       = "/${trim(var.backup.remote.gdrive.path, "/")}" # Ensure the path starts with a slash and remove trailing slash

  backup_script      = "backup.sh"
  backup_script_path = "/etc/backup"
  backup_labels = {
    "app.kubernetes.io/name"      = "backup-pvc-${var.pvc.name}"
    "app.kubernetes.io/component" = "backup"
    "app.kubernetes.io/part-of"   = var.pvc.name
  }

  restore_script      = "restore.sh"
  restore_script_path = "/etc/restore"
  restore_snapshot_id = var.restore.snapshot_id != null ? var.restore.snapshot_id : "latest"
  restore_enabled     = var.restore.enabled
  restore_labels = {
    "app.kubernetes.io/name"      = "restore-pvc-${var.pvc.name}"
    "app.kubernetes.io/component" = "backup"
    "app.kubernetes.io/part-of"   = var.pvc.name
  }
}

# Create the PVC
resource "kubernetes_persistent_volume_claim_v1" "pvc" {
  metadata {
    name      = var.pvc.name
    namespace = var.pvc.namespace
    annotations = {
      "volume.kubernetes.io/selected-node" = var.pvc.node
    }
  }

  spec {
    access_modes = var.pvc.access_modes

    resources {
      requests = {
        storage = var.pvc.storage
      }
    }
    storage_class_name = var.pvc.storage_class
  }
}

resource "kubernetes_secret_v1" "backup_config" {
  metadata {
    name      = "${var.pvc.name}-backup-config"
    namespace = var.pvc.namespace
  }
  data = {
    RESTIC_PASSWORD = var.backup.restic_password
    "rclone.conf"   = <<EOF
    [gdrive]
      type = drive
      scope = drive
      token = ${var.backup.remote.gdrive.token}
    EOF
  }
}

resource "kubernetes_config_map_v1" "backup_script" {
  metadata {
    name      = "backup-pvc-${var.pvc.name}"
    namespace = var.pvc.namespace
  }
  data = {
    "${local.backup_script}" = templatefile("${path.module}/${local.backup_script}.tftpl", {
      pvc_name         = var.pvc.name
      exclude_dirs     = var.backup.exclude_dirs
      keep_last        = var.backup.keep_last
      drive_path       = local.drive_path
      pvc_volume_mount = local.pvc_volume_mount
      password_defined = var.backup.restic_password != ""
    })
  }
}

resource "kubernetes_cron_job_v1" "pvc_backup" {
  metadata {
    name      = "backup-pvc-${var.pvc.name}"
    namespace = var.pvc.namespace
    labels    = local.backup_labels
  }

  spec {
    schedule                      = var.backup.schedule
    successful_jobs_history_limit = 1
    job_template {
      metadata {
        name   = "backup-pvc-${var.pvc.name}"
        labels = local.backup_labels
      }
      spec {
        backoff_limit = var.backup.retries
        template {
          metadata {
            name = "backup-pvc-${var.pvc.name}"
          }
          spec {
            node_selector = var.pvc.node != null ? {
              "kubernetes.io/hostname" = var.pvc.node
            } : {}
            container {
              name    = "restic"
              image   = local.restic_image
              command = ["/bin/sh", "-c"]
              args = [
                "${local.backup_script_path}/${local.backup_script}"
              ]
              env {
                name = "RESTIC_PASSWORD"
                value_from {
                  secret_key_ref {
                    name = kubernetes_secret_v1.backup_config.metadata[0].name
                    key  = "RESTIC_PASSWORD"
                  }
                }
              }
              volume_mount {
                mount_path = local.pvc_volume_mount
                name       = "${var.pvc.name}-data"
              }
              volume_mount {
                mount_path = "/root/.config/rclone"
                name       = "rclone-config"
              }
              volume_mount {
                mount_path = local.backup_script_path
                name       = "backup-script"
              }
            }
            volume {
              name = "${var.pvc.name}-data"
              persistent_volume_claim {
                claim_name = kubernetes_persistent_volume_claim_v1.pvc.metadata[0].name
                read_only  = false
              }
            }
            volume {
              name = "rclone-config"
              secret {
                secret_name = kubernetes_secret_v1.backup_config.metadata[0].name
                items {
                  key  = "rclone.conf"
                  path = "rclone.conf"
                }
              }
            }
            volume {
              name = "backup-script"
              config_map {
                name         = kubernetes_config_map_v1.backup_script.metadata[0].name
                default_mode = "0755"
                items {
                  key  = local.backup_script
                  path = local.backup_script
                }
              }
            }
          }
        }
      }
    }
  }
}

resource "kubernetes_config_map_v1" "restore_script" {
  count = var.restore.enabled ? 1 : 0

  metadata {
    name      = "restore-pvc-${var.pvc.name}"
    namespace = var.pvc.namespace
  }
  data = {
    "${local.restore_script}" = templatefile("${path.module}/${local.restore_script}.tftpl", {
      pvc_name         = var.pvc.name
      snapshot_id      = local.restore_snapshot_id
      drive_path       = local.drive_path
      pvc_volume_mount = local.pvc_volume_mount
      password_defined = var.backup.restic_password != ""
    })
  }
}

resource "null_resource" "snapshot_id" {
  triggers = {
    snapshot_id = local.restore_snapshot_id
  }
}

resource "kubernetes_job_v1" "pvc_restore_backup" {
  count = local.restore_enabled ? 1 : 0

  metadata {
    name      = "restore-pvc-${var.pvc.name}"
    namespace = var.pvc.namespace
    labels    = local.restore_labels
    annotations = {
      "snapshot-id" = local.restore_snapshot_id
    }
  }

  wait_for_completion = true
  spec {
    template {
      metadata {
        name   = "restore-pvc-${var.pvc.name}"
        labels = local.restore_labels
      }
      spec {
        node_selector = var.pvc.node != null ? {
          "kubernetes.io/hostname" = var.pvc.node
        } : {}

        restart_policy = "Never"

        container {
          name    = "restic"
          image   = local.restic_image
          command = ["/bin/sh", "-c"]
          args = [
            "${local.restore_script_path}/${local.restore_script}"
          ]
          env {
            name = "RESTIC_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.backup_config.metadata[0].name
                key  = "RESTIC_PASSWORD"
              }
            }
          }
          volume_mount {
            mount_path = local.pvc_volume_mount
            name       = "${var.pvc.name}-data"
          }
          volume_mount {
            mount_path = "/root/.config/rclone"
            name       = "rclone-conf"
          }
          volume_mount {
            mount_path = local.restore_script_path
            name       = "restore-script"
          }
        }
        volume {
          name = "${var.pvc.name}-data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.pvc.metadata[0].name
            read_only  = false
          }
        }
        volume {
          name = "rclone-conf"
          secret {
            secret_name = kubernetes_secret_v1.backup_config.metadata[0].name
            items {
              key  = "rclone.conf"
              path = "rclone.conf"
            }
          }
        }
        volume {
          name = "restore-script"
          config_map {
            name         = kubernetes_config_map_v1.restore_script[0].metadata[0].name
            default_mode = "0755"
            items {
              key  = local.restore_script
              path = local.restore_script
            }
          }
        }
      }
    }
  }

  lifecycle {
    replace_triggered_by = [
      null_resource.snapshot_id # This will force recreation when snapshot_id changes
    ]
  }
}
