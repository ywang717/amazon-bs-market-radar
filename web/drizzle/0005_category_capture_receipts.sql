CREATE TABLE `category_capture_receipts` (
	`market_date` text NOT NULL,
	`category_key` text NOT NULL,
	`receipt_sha256` text NOT NULL,
	`observed_at` text NOT NULL,
	PRIMARY KEY(`market_date`, `category_key`)
);
--> statement-breakpoint
CREATE TABLE `market_sync_guard` (
	`guard_key` text PRIMARY KEY NOT NULL,
	`conflict` integer NOT NULL,
	CONSTRAINT "market_sync_guard_check" CHECK("market_sync_guard"."conflict" = 0)
);
