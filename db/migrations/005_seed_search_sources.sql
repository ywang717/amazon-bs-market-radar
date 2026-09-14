BEGIN;
SET search_path TO amazon_intelligence, public;

INSERT INTO source_definition (
    source_id, marketplace_id, category_id, source_type, search_term,
    target_limit, config_json, active
)
SELECT
    seed.source_id::uuid,
    m.marketplace_id,
    c.category_id,
    'SEARCH'::source_type,
    seed.search_term,
    50,
    jsonb_build_object(
        'provider', 'CREATORS_API',
        'search_index', seed.search_index,
        'max_requests_per_second', 1,
        'max_attempts', 3,
        'review_status', 'APPROVED_SEARCH_ONLY'
    ),
    true
FROM marketplace m
CROSS JOIN (VALUES
    ('71cc7af1-35b1-4d19-8306-ff971db318ee', 'pressure-washer', 'pressure washer', 'GardenAndOutdoor'),
    ('34246971-247c-47ed-99a6-0f75d9e4ffb6', 'sump-pump', 'sump pump', 'ToolsAndHomeImprovement'),
    ('021052f6-47df-48a3-a066-da1469e773dc', 'pressure-washer-accessories', 'pressure washer accessories', 'GardenAndOutdoor')
) AS seed(source_id, category_slug, search_term, search_index)
JOIN category c ON c.slug = seed.category_slug
WHERE m.code = 'AMAZON_US'
ON CONFLICT (source_id) DO UPDATE SET
    marketplace_id = EXCLUDED.marketplace_id,
    category_id = EXCLUDED.category_id,
    source_type = EXCLUDED.source_type,
    search_term = EXCLUDED.search_term,
    target_limit = EXCLUDED.target_limit,
    config_json = EXCLUDED.config_json,
    active = EXCLUDED.active;

COMMIT;

