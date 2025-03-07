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
