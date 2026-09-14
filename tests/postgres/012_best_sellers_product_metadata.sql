\set ON_ERROR_STOP on
BEGIN;
SET LOCAL search_path TO amazon_intelligence, public;

INSERT INTO best_sellers_product_metadata (
    marketplace_code, asin, product_type, classification_confidence,
    classification_rule_id, classification_rule_version, classification_evidence,
    raw_brand, normalized_brand, normalized_brand_key, brand_alias_rule_id, brand_source,
    first_seen_market_date, last_seen_market_date
) VALUES (
    'AMAZON_US', 'B000000000', 'electric_pressure_washer', 'medium',
    'machine-electric', 'product-rules-v1', '["TITLE_RULE:machine-electric"]'::jsonb,
    null, null, null, null, 'unknown', '2026-08-20', '2026-08-20'
);

DO $constraint_test$
BEGIN
    BEGIN
        INSERT INTO best_sellers_product_metadata (
            marketplace_code, asin, product_type, classification_confidence,
            classification_rule_id, classification_rule_version, classification_evidence,
            brand_source, first_seen_market_date, last_seen_market_date
        ) VALUES (
            'AMAZON_US', 'B000000001', 'electric_pressure_washer', 'low',
            'machine-electric', 'product-rules-v1', '["TITLE_RULE:machine-electric"]'::jsonb,
            'unknown', '2026-08-20', '2026-08-20'
        );
        RAISE EXCEPTION 'known product type with low confidence was accepted';
    EXCEPTION WHEN check_violation THEN
        NULL;
    END;

    BEGIN
        INSERT INTO best_sellers_product_metadata (
            marketplace_code, asin, product_type, classification_confidence,
            classification_rule_id, classification_rule_version, classification_evidence,
            brand_source, first_seen_market_date, last_seen_market_date
        ) VALUES (
            'AMAZON_US', 'B000000002', 'not_in_the_spec', 'medium',
            'invalid-rule', 'product-rules-v1', '["INVALID"]'::jsonb,
            'unknown', '2026-08-20', '2026-08-20'
        );
        RAISE EXCEPTION 'unsupported product type was accepted';
    EXCEPTION WHEN check_violation THEN
        NULL;
    END;

    BEGIN
        INSERT INTO best_sellers_product_metadata (
            marketplace_code, asin, product_type, classification_confidence,
            classification_rule_id, classification_rule_version, classification_evidence,
            brand_source, first_seen_market_date, last_seen_market_date
        ) VALUES (
            'AMAZON_US', 'B000000003', 'unknown', 'low',
            null, 'product-rules-v1', '[]'::jsonb,
            'unknown', '2026-08-20', '2026-08-20'
        );
        RAISE EXCEPTION 'empty classification evidence was accepted';
    EXCEPTION WHEN check_violation THEN
        NULL;
    END;
END
$constraint_test$;

DO $brand_merge_test$
DECLARE
    v_row best_sellers_product_metadata%ROWTYPE;
BEGIN
    INSERT INTO best_sellers_product_metadata (
        marketplace_code, asin, product_type, classification_confidence,
        classification_rule_id, classification_rule_version, classification_evidence,
        raw_brand, normalized_brand, normalized_brand_key, brand_alias_rule_id, brand_source,
        first_seen_market_date, last_seen_market_date
    ) VALUES (
        'AMAZON_US', 'B000000010', 'electric_pressure_washer', 'medium',
        'machine-electric', 'product-rules-v1', '["TITLE_RULE:machine-electric"]'::jsonb,
        null, null, null, null, 'unknown', '2026-08-20', '2026-08-20'
    );

    PERFORM upsert_best_sellers_product_metadata('[{
        "marketplace_code":"AMAZON_US",
        "asin":"B000000010",
        "product_type":"electric_pressure_washer",
        "classification_confidence":"medium",
        "classification_rule_id":"machine-electric",
        "classification_rule_version":"product-rules-v1",
        "classification_evidence":["TITLE_RULE:machine-electric"],
        "raw_brand":"Westinghouse",
        "normalized_brand":"Westinghouse",
        "normalized_brand_key":"westinghouse",
        "brand_alias_rule_id":"brand-westinghouse",
        "brand_source":"verified_metadata",
        "first_seen_market_date":"2026-08-15",
        "last_seen_market_date":"2026-08-25"
    }]'::jsonb);

    SELECT * INTO STRICT v_row
    FROM best_sellers_product_metadata
    WHERE marketplace_code = 'AMAZON_US' AND asin = 'B000000010';
    IF v_row.brand_source <> 'verified_metadata'
       OR v_row.normalized_brand_key <> 'westinghouse'
       OR v_row.first_seen_market_date <> DATE '2026-08-15'
       OR v_row.last_seen_market_date <> DATE '2026-08-25' THEN
        RAISE EXCEPTION 'unknown to verified merge or date union failed';
    END IF;

    PERFORM upsert_best_sellers_product_metadata('[{
        "marketplace_code":"AMAZON_US",
        "asin":"B000000010",
        "product_type":"electric_pressure_washer",
        "classification_confidence":"medium",
        "classification_rule_id":"machine-electric",
        "classification_rule_version":"product-rules-v1",
        "classification_evidence":["TITLE_RULE:machine-electric"],
        "raw_brand":"WESTINGHOUSE",
        "normalized_brand":"Westinghouse",
        "normalized_brand_key":"westinghouse",
        "brand_alias_rule_id":"brand-westinghouse",
        "brand_source":"verified_metadata",
        "first_seen_market_date":"2026-08-10",
        "last_seen_market_date":"2026-08-28"
    }]'::jsonb);

    SELECT * INTO STRICT v_row
    FROM best_sellers_product_metadata
    WHERE marketplace_code = 'AMAZON_US' AND asin = 'B000000010';
    IF v_row.raw_brand <> 'WESTINGHOUSE'
       OR v_row.normalized_brand_key <> 'westinghouse'
       OR v_row.first_seen_market_date <> DATE '2026-08-10'
       OR v_row.last_seen_market_date <> DATE '2026-08-28' THEN
        RAISE EXCEPTION 'same-key trusted replay or date union failed';
    END IF;

    BEGIN
        PERFORM upsert_best_sellers_product_metadata('[{
            "marketplace_code":"AMAZON_US",
            "asin":"B000000010",
            "product_type":"electric_pressure_washer",
            "classification_confidence":"medium",
            "classification_rule_id":"machine-electric",
            "classification_rule_version":"product-rules-v1",
            "classification_evidence":["TITLE_RULE:machine-electric"],
            "raw_brand":"Different Brand",
            "normalized_brand":"Different Brand",
            "normalized_brand_key":"different brand",
            "brand_alias_rule_id":null,
            "brand_source":"verified_metadata",
            "first_seen_market_date":"2026-08-01",
            "last_seen_market_date":"2026-08-29"
        }]'::jsonb);
        RAISE EXCEPTION 'trusted brand conflict was silently accepted';
    EXCEPTION WHEN raise_exception THEN
        IF SQLERRM <> 'Best Sellers product metadata trusted brand conflict for AMAZON_US/B000000010' THEN
            RAISE;
        END IF;
    END;

    SELECT * INTO STRICT v_row
    FROM best_sellers_product_metadata
    WHERE marketplace_code = 'AMAZON_US' AND asin = 'B000000010';
    IF v_row.raw_brand <> 'WESTINGHOUSE'
       OR v_row.normalized_brand_key <> 'westinghouse'
       OR v_row.first_seen_market_date <> DATE '2026-08-10'
       OR v_row.last_seen_market_date <> DATE '2026-08-28' THEN
        RAISE EXCEPTION 'trusted brand conflict changed the existing row';
    END IF;

    BEGIN
        PERFORM upsert_best_sellers_product_metadata('[
            {
                "marketplace_code":"AMAZON_US","asin":"B000000020","product_type":"unknown","classification_confidence":"low","classification_rule_id":null,"classification_rule_version":"product-rules-v1","classification_evidence":["NO_SAFE_RULE_MATCH"],"raw_brand":null,"normalized_brand":null,"normalized_brand_key":null,"brand_alias_rule_id":null,"brand_source":"unknown","first_seen_market_date":"2026-08-20","last_seen_market_date":"2026-08-20"
            },
            {
                "marketplace_code":"AMAZON_US","asin":"B000000020","product_type":"unknown","classification_confidence":"low","classification_rule_id":null,"classification_rule_version":"product-rules-v1","classification_evidence":["NO_SAFE_RULE_MATCH"],"raw_brand":null,"normalized_brand":null,"normalized_brand_key":null,"brand_alias_rule_id":null,"brand_source":"unknown","first_seen_market_date":"2026-08-20","last_seen_market_date":"2026-08-20"
            }
        ]'::jsonb);
        RAISE EXCEPTION 'duplicate unknown metadata rows were accepted';
    EXCEPTION WHEN raise_exception THEN
        IF SQLERRM <> 'Best Sellers product metadata contains duplicate marketplace/ASIN rows' THEN
            RAISE;
        END IF;
    END;

    BEGIN
        PERFORM upsert_best_sellers_product_metadata('[
            {
                "marketplace_code":"AMAZON_US","asin":"B000000021","product_type":"unknown","classification_confidence":"low","classification_rule_id":null,"classification_rule_version":"product-rules-v1","classification_evidence":["NO_SAFE_RULE_MATCH"],"raw_brand":"Brand A","normalized_brand":"Brand A","normalized_brand_key":"brand a","brand_alias_rule_id":null,"brand_source":"verified_metadata","first_seen_market_date":"2026-08-20","last_seen_market_date":"2026-08-20"
            },
            {
                "marketplace_code":"AMAZON_US","asin":"B000000021","product_type":"unknown","classification_confidence":"low","classification_rule_id":null,"classification_rule_version":"product-rules-v1","classification_evidence":["NO_SAFE_RULE_MATCH"],"raw_brand":"Brand A","normalized_brand":"Brand A","normalized_brand_key":"brand a","brand_alias_rule_id":null,"brand_source":"verified_metadata","first_seen_market_date":"2026-08-20","last_seen_market_date":"2026-08-20"
            }
        ]'::jsonb);
        RAISE EXCEPTION 'duplicate same-key trusted metadata rows were accepted';
    EXCEPTION WHEN raise_exception THEN
        IF SQLERRM <> 'Best Sellers product metadata contains duplicate marketplace/ASIN rows' THEN
            RAISE;
        END IF;
    END;
END
$brand_merge_test$;

DO $classification_version_test$
DECLARE
    v_row best_sellers_product_metadata%ROWTYPE;
BEGIN
    INSERT INTO best_sellers_product_metadata (
        marketplace_code, asin, product_type, classification_confidence,
        classification_rule_id, classification_rule_version, classification_evidence,
        raw_brand, normalized_brand, normalized_brand_key, brand_alias_rule_id, brand_source,
        first_seen_market_date, last_seen_market_date
    ) VALUES
      ('AMAZON_US', 'B000000030', 'surface_cleaner', 'high', 'old-high', 'product-rules-v1', '["OLD_HIGH"]'::jsonb, null, null, null, null, 'unknown', '2026-08-20', '2026-08-20'),
      ('AMAZON_US', 'B000000031', 'other_accessory', 'medium', 'old-medium', 'product-rules-v1', '["OLD_MEDIUM"]'::jsonb, null, null, null, null, 'unknown', '2026-08-20', '2026-08-20');

    PERFORM upsert_best_sellers_product_metadata('[
      {"marketplace_code":"AMAZON_US","asin":"B000000030","product_type":"electric_pressure_washer","classification_confidence":"high","classification_rule_id":"new-high","classification_rule_version":"product-rules-v2","classification_evidence":["NEW_HIGH"],"raw_brand":null,"normalized_brand":null,"normalized_brand_key":null,"brand_alias_rule_id":null,"brand_source":"unknown","first_seen_market_date":"2026-08-20","last_seen_market_date":"2026-08-29"},
      {"marketplace_code":"AMAZON_US","asin":"B000000031","product_type":"hose","classification_confidence":"medium","classification_rule_id":"new-medium","classification_rule_version":"product-rules-v2","classification_evidence":["NEW_MEDIUM"],"raw_brand":null,"normalized_brand":null,"normalized_brand_key":null,"brand_alias_rule_id":null,"brand_source":"unknown","first_seen_market_date":"2026-08-20","last_seen_market_date":"2026-08-29"}
    ]'::jsonb);

    SELECT * INTO STRICT v_row FROM best_sellers_product_metadata WHERE asin = 'B000000030';
    IF v_row.product_type <> 'electric_pressure_washer' OR v_row.classification_rule_version <> 'product-rules-v2' THEN
        RAISE EXCEPTION 'newer same-confidence high classification did not replace the old rule';
    END IF;
    SELECT * INTO STRICT v_row FROM best_sellers_product_metadata WHERE asin = 'B000000031';
    IF v_row.product_type <> 'hose' OR v_row.classification_rule_version <> 'product-rules-v2' THEN
        RAISE EXCEPTION 'newer same-confidence medium classification did not replace the old rule';
    END IF;

    PERFORM upsert_best_sellers_product_metadata('[{
      "marketplace_code":"AMAZON_US","asin":"B000000030","product_type":"gas_pressure_washer","classification_confidence":"high","classification_rule_id":"rollback","classification_rule_version":"product-rules-v1","classification_evidence":["ROLLBACK"],"raw_brand":null,"normalized_brand":null,"normalized_brand_key":null,"brand_alias_rule_id":null,"brand_source":"unknown","first_seen_market_date":"2026-08-20","last_seen_market_date":"2026-08-30"
    }]'::jsonb);
    SELECT * INTO STRICT v_row FROM best_sellers_product_metadata WHERE asin = 'B000000030';
    IF v_row.product_type <> 'electric_pressure_washer' OR v_row.classification_rule_version <> 'product-rules-v2' THEN
        RAISE EXCEPTION 'older high classification rolled back a newer rule';
    END IF;
END
$classification_version_test$;

ROLLBACK;
