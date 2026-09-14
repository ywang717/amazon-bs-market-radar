CREATE TABLE IF NOT EXISTS `product_metadata_brand_conflict_guard` (
	`guard_key` text PRIMARY KEY NOT NULL,
	`conflict` integer NOT NULL,
	CONSTRAINT "product_metadata_brand_conflict_guard_check" CHECK("product_metadata_brand_conflict_guard"."conflict" = 0)
);
