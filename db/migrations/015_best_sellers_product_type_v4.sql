BEGIN;
SET search_path TO amazon_intelligence, public;

ALTER TABLE best_sellers_product_metadata
    DROP CONSTRAINT IF EXISTS best_sellers_product_metadata_product_type_check;

ALTER TABLE best_sellers_product_metadata
    ADD CONSTRAINT best_sellers_product_metadata_product_type_check CHECK (product_type IN (
        'electric_pressure_washer',
        'gas_pressure_washer',
        'cordless_pressure_washer',
        'surface_cleaner',
        'pressure_washer_gun',
        'hose',
        'nozzle',
        'foam_cannon',
        'adapter_connector',
        'extension_wand',
        'sewer_jetter',
        'chemical_cleaner',
        'pump_protector',
        'other_accessory',
        'unknown'
    ));

COMMIT;
