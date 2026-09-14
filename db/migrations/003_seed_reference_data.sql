BEGIN;
SET search_path TO amazon_intelligence, public;

INSERT INTO marketplace (code, country_code, currency, timezone)
VALUES ('AMAZON_US', 'US', 'USD', 'America/Los_Angeles')
ON CONFLICT (code) DO NOTHING;

INSERT INTO category (name, slug, category_level, accessory_type)
VALUES
    ('Pressure Washer', 'pressure-washer', 1, NULL),
    ('Sump Pump', 'sump-pump', 1, NULL),
    ('Pressure Washer Accessories', 'pressure-washer-accessories', 1, NULL)
ON CONFLICT (slug) DO NOTHING;

INSERT INTO category (parent_category_id, name, slug, category_level, accessory_type)
SELECT parent.category_id, child.name, child.slug, 2, child.accessory_type
FROM category parent
CROSS JOIN (VALUES
    ('Spray Nozzle', 'spray-nozzle', 'SPRAY_NOZZLE'),
    ('Surface Cleaner', 'surface-cleaner', 'SURFACE_CLEANER'),
    ('Foam Cannon', 'foam-cannon', 'FOAM_CANNON'),
    ('Pressure Washer Hose', 'pressure-washer-hose', 'PRESSURE_WASHER_HOSE'),
    ('Spray Gun / Wand', 'spray-gun-wand', 'SPRAY_GUN_WAND'),
    ('Adapter / Connector', 'adapter-connector', 'ADAPTER_CONNECTOR'),
    ('Replacement Parts', 'replacement-parts', 'REPLACEMENT_PARTS')
) AS child(name, slug, accessory_type)
WHERE parent.slug = 'pressure-washer-accessories'
ON CONFLICT (slug) DO NOTHING;

INSERT INTO score_model_version (
    model_version, effective_from, weights_json, thresholds_json, missing_policy_json, status
)
VALUES (
    'opportunity-v0-draft',
    '2026-08-03T00:00:00Z',
    '{"rank_growth":0.30,"review_velocity":0.20,"rating":0.15,"new_product":0.15,"brand_growth":0.20}',
    '{}',
    '{"policy":"not_yet_calibrated"}',
    'DRAFT'
)
ON CONFLICT (model_version) DO NOTHING;

COMMIT;

