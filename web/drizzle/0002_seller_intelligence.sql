CREATE TABLE IF NOT EXISTS `analysis_reports` (
	`key` text PRIMARY KEY NOT NULL,
	`report_kind` text NOT NULL,
	`market_date` text NOT NULL,
	`category_key` text,
	`generated_at` text NOT NULL,
	`generator_version` text NOT NULL,
	`content_sha256` text NOT NULL,
	`content_json` text NOT NULL,
	`imported_at` text NOT NULL
);
--> statement-breakpoint
CREATE INDEX IF NOT EXISTS `idx_analysis_reports_market_date` ON `analysis_reports` (`market_date`,`report_kind`,`category_key`);--> statement-breakpoint
CREATE TABLE IF NOT EXISTS `seller_intelligence_reports` (
	`key` text PRIMARY KEY NOT NULL,
	`report_kind` text NOT NULL,
	`profile` text NOT NULL,
	`market_date` text NOT NULL,
	`category_key` text,
	`generated_at` text NOT NULL,
	`generator_version` text NOT NULL,
	`content_sha256` text NOT NULL,
	`content_json` text NOT NULL,
	`imported_at` text NOT NULL
);
--> statement-breakpoint
CREATE INDEX IF NOT EXISTS `idx_seller_intelligence_reports_market_date` ON `seller_intelligence_reports` (`market_date`,`report_kind`,`profile`,`category_key`);
