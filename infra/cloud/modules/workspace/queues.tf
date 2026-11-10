# Queues for apps/worker, one dead-letter queue each. Names match the producer and consumer bindings in
# apps/worker/wrangler.jsonc; add those to every block when a queue is added here.
resource "cloudflare_queue" "job" {
  for_each   = var.queues
  account_id = var.account_id
  queue_name = "${var.project}-${each.key}-${var.environment}"
}

resource "cloudflare_queue" "dead_letter" {
  for_each   = var.queues
  account_id = var.account_id
  queue_name = "${var.project}-${each.key}-dlq-${var.environment}"
}
