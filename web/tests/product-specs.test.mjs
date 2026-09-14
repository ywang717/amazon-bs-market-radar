import assert from "node:assert/strict";
import test from "node:test";
import { readExplicitSpecificationsForProduct } from "../lib/product-specs.ts";

test("uses pressure semantics only for pressure-washer machines", () => {
  assert.deepEqual(
    readExplicitSpecificationsForProduct("pressure_washers", "electric_pressure_washer", "Westinghouse 2300 PSI 1.76 GPM Electric Pressure Washer"),
    [
      { label: "工作压力", value: "2300 PSI" },
      { label: "流量", value: "1.76 GPM" },
      { label: "动力类型", value: "电动" },
    ],
  );
  assert.equal(
    readExplicitSpecificationsForProduct("pressure_washer_accessories", "hose", "Pressure Washer Hose rated 4000 PSI 50 FT")
      .some(({ label }) => label === "工作压力"),
    false,
  );
});
