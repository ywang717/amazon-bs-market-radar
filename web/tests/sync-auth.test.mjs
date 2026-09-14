import assert from "node:assert/strict";
import test from "node:test";
import { authorizeSyncRequest, bundleId } from "../lib/sync-auth.ts";

test("accepts only the exact bearer sync secret", () => {
  const valid = new Request("https://example.test/api/sync/v1/bundles", { headers: { authorization: "Bearer local-secret" } });
  const invalid = new Request("https://example.test/api/sync/v1/bundles", { headers: { authorization: "Bearer local-secret-extra" } });

  assert.equal(authorizeSyncRequest(valid, "local-secret"), true);
  assert.equal(authorizeSyncRequest(invalid, "local-secret"), false);
  assert.equal(authorizeSyncRequest(new Request("https://example.test"), "local-secret"), false);
});
test("derives a stable idempotency key from the verified receipt hash", () => {
  assert.equal(bundleId({ receiptSha256: "A".repeat(64) }), "a".repeat(64));
  assert.throws(() => bundleId({ receiptSha256: "not-a-hash" }), /哈希/);
});
