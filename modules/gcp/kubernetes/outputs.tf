output "cluster_name" { value = google_container_cluster.app.name }
output "cluster_endpoint" { value = "https://${google_container_cluster.app.endpoint}" }
output "cluster_certificate_authority_data" { value = google_container_cluster.app.master_auth[0].cluster_ca_certificate }
output "node_service_account_email" { value = google_service_account.nodes.email }
