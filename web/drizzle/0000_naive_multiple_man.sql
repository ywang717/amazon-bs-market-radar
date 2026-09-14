CREATE TABLE `category_days` (
	`market_date` text NOT NULL,
	`category_key` text NOT NULL,
	`source_url` text NOT NULL,
	`observation_count` integer NOT NULL,
	`complete` integer NOT NULL,
	`missing_ranks_json` text NOT NULL,
	PRIMARY KEY(`market_date`, `category_key`)
);
--> statement-breakpoint
CREATE TABLE `observations` (
	`market_date` text NOT NULL,
	`category_key` text NOT NULL,
	`rank` integer NOT NULL,
	`asin` text NOT NULL,
	`title` text NOT NULL,
	`url` text NOT NULL,
	`price` real,
	`rating` real,
	`reviews` integer,
	PRIMARY KEY(`market_date`, `category_key`, `rank`)
);
--> statement-breakpoint
CREATE TABLE `reports` (
	`key` text PRIMARY KEY NOT NULL,
	`market_date` text NOT NULL,
	`category_key` text,
	`kind` text NOT NULL,
	`title` text NOT NULL,
	`byte_count` integer NOT NULL,
	`uploaded_at` text NOT NULL
);
--> statement-breakpoint
CREATE TABLE `snapshots` (
	`market_date` text PRIMARY KEY NOT NULL,
	`observed_at` text NOT NULL,
	`receipt_sha256` text NOT NULL,
	`public_status` text NOT NULL,
	`complete_category_count` integer NOT NULL,
	`imported_at` text NOT NULL
);
--> statement-breakpoint
CREATE UNIQUE INDEX `snapshots_receipt_sha256_unique` ON `snapshots` (`receipt_sha256`);
