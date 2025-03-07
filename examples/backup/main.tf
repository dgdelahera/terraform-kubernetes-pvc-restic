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
