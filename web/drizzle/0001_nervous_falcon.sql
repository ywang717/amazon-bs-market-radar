CREATE TABLE `observation_discounts` (
	`market_date` text NOT NULL,
	`category_key` text NOT NULL,
	`rank` integer NOT NULL,
	`has_discount` integer,
	`discounts_json` text NOT NULL,
	PRIMARY KEY(`market_date`, `category_key`, `rank`)
);
