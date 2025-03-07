output "pvc_name" {
  value       = kubernetes_persistent_volume_claim_v1.pvc.metadata[0].name
  description = <<EOF
  Name of the PVC created. If you are using the `WaitForFirstConsumer` storage class,
  don't use this output. Terraform adds an implicit dependency to the PVC resource
  so it will wait for the PVC to be created before creating the pod, resulting in a
  circular dependency.
  EOF
}
