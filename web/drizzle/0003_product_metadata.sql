CREATE TABLE IF NOT EXISTS `product_metadata` (
	`marketplace` text NOT NULL,
	`asin` text NOT NULL,
	`product_type` text NOT NULL,
	`classification_confidence` text NOT NULL,
	`classification_rule_id` text,
	`classification_rule_version` text NOT NULL,
	`classification_evidence_json` text NOT NULL,
	`raw_brand` text,
	`normalized_brand` text,
	`normalized_brand_key` text,
	`brand_alias_rule_id` text,
	`brand_source` text NOT NULL,
	`first_seen_market_date` text NOT NULL,
	`last_seen_market_date` text NOT NULL,
	PRIMARY KEY(`marketplace`, `asin`)
);
--> statement-breakpoint
CREATE INDEX IF NOT EXISTS `idx_product_metadata_type` ON `product_metadata` (`product_type`);--> statement-breakpoint
CREATE INDEX IF NOT EXISTS `idx_product_metadata_brand` ON `product_metadata` (`normalized_brand_key`);
