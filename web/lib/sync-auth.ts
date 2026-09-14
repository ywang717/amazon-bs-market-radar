import { timingSafeEqual } from "node:crypto";

export function authorizeSyncRequest(request: Request, secret: string | undefined) {
  if (!secret) return false;
  const supplied = request.headers.get("authorization") ?? "";
  const expected = `Bearer ${secret}`;
  const suppliedBytes = new TextEncoder().encode(supplied);
  const expectedBytes = new TextEncoder().encode(expected);
  return suppliedBytes.length === expectedBytes.length && timingSafeEqual(suppliedBytes, expectedBytes);
}
export function bundleId(bundle: { receiptSha256?: string }) {
  const value = bundle.receiptSha256?.toLowerCase() ?? "";
  if (!/^[a-f0-9]{64}$/.test(value)) throw new Error("回执哈希无效");
  return value;
}
