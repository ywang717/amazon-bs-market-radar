BEGIN;
SET search_path TO amazon_intelligence, public;

CREATE VIEW daily_ranking AS
SELECT
    ro.market_date AS date,
    c1.name AS category_level_1,
    c.name AS category_level_2,
    c.accessory_type,
    ro.rank,
    dpm.previous_rank,
    dpm.rank_change,
    b.canonical_name AS brand,
    COALESCE(ls.model, p.model) AS model,
    p.asin,
    ls.title,
    ls.canonical_url AS url,
    os.price,
    os.coupon_text AS coupon,
    ls.rating,
    ls.review_count,
    s.display_name AS seller,
    os.fba_status,
    ls.first_available_date,
    sd.source_type,
    sd.search_term,
    ro.run_id
FROM ranking_observation ro
JOIN product p ON p.product_id = ro.product_id
JOIN category c ON c.category_id = ro.category_id
LEFT JOIN category c1 ON c1.category_id = COALESCE(c.parent_category_id, c.category_id)
JOIN source_definition sd ON sd.source_id = ro.source_id
LEFT JOIN brand b ON b.brand_id = p.brand_id
LEFT JOIN daily_product_metric dpm
  ON dpm.market_date = ro.market_date
 AND dpm.product_id = ro.product_id
 AND dpm.category_id = ro.category_id
 AND dpm.source_id = ro.source_id
LEFT JOIN LATERAL (
    SELECT x.* FROM listing_snapshot x
    WHERE x.product_id = ro.product_id AND x.market_date = ro.market_date
    ORDER BY x.observed_at DESC LIMIT 1
) ls ON true
LEFT JOIN LATERAL (
    SELECT x.* FROM offer_snapshot x
    WHERE x.product_id = ro.product_id AND x.market_date = ro.market_date
    ORDER BY x.observed_at DESC LIMIT 1
) os ON true
LEFT JOIN seller s ON s.seller_id = os.seller_id;

CREATE VIEW new_product_entry AS
SELECT ds.*, p.asin, c.name AS category_name
FROM detection_signal ds
JOIN product p ON p.product_id = ds.product_id
JOIN category c ON c.category_id = ds.category_id
WHERE ds.signal_type = 'NEW_PRODUCT';

CREATE VIEW new_brand_tracker AS
SELECT ds.*, b.canonical_name, c.name AS category_name
FROM detection_signal ds
JOIN brand b ON b.brand_id = ds.brand_id
JOIN category c ON c.category_id = ds.category_id
WHERE ds.signal_type = 'NEW_BRAND';

CREATE VIEW rising_products AS
SELECT ds.*, p.asin, c.name AS category_name
FROM detection_signal ds
JOIN product p ON p.product_id = ds.product_id
JOIN category c ON c.category_id = ds.category_id
WHERE ds.signal_type IN ('RISING_PRODUCT', 'FAST_GROWING');

CREATE VIEW trend_analysis AS
SELECT
    dpm.market_date,
    p.asin,
    c.name AS category_name,
    dpm.current_rank,
    dpm.previous_rank,
    dpm.rank_change,
    dpm.review_velocity_7d,
    dpm.review_velocity_30d,
    dpm.coverage_days,
    dpm.calculation_version
FROM daily_product_metric dpm
JOIN product p ON p.product_id = dpm.product_id
JOIN category c ON c.category_id = dpm.category_id;

COMMIT;

