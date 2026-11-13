output "bucket_url" {
  description = "Публичный URL картинки в бакете"
  value       = "https://storage.yandexcloud.net/${yandex_storage_bucket.bucket.bucket}/image.jpg"
}

output "nlb_public_ip" {
  description = "Публичный IP сетевого балансировщика"
  value       = tolist(tolist(yandex_lb_network_load_balancer.nlb.listener)[0].external_address_spec)[0].address
}

output "instance_group_id" {
  description = "ID Instance Group"
  value       = yandex_compute_instance_group.lamp_group.id
}

output "ig_service_account_id" {
  description = "ID сервисного аккаунта Instance Group"
  value       = yandex_iam_service_account.instance_group_sa.id
}