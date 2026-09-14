interface D1PreparedStatement {
  bind(...values: unknown[]): D1PreparedStatement;
  all<T = Record<string, unknown>>(): Promise<{ results: T[]; meta?: Record<string, unknown> }>;
  first<T = Record<string, unknown>>(): Promise<T | null>;
  run(): Promise<{ meta: { changes?: number; [key: string]: unknown } }>;
}

interface D1Database {
  prepare(sql: string): D1PreparedStatement;
  batch(statements: D1PreparedStatement[]): Promise<Array<{ meta?: { changes?: number; [key: string]: unknown } }>>;
}

interface R2Bucket {
  get(key: string): Promise<{ body: ReadableStream<Uint8Array> } | null>;
  put(key: string, value: ArrayBuffer, options?: Record<string, unknown>): Promise<void>;
}

interface Fetcher {
  fetch(input: RequestInfo | URL, init?: RequestInit): Promise<Response>;
}

declare module "cloudflare:workers" {
  export const env: {
    DB?: D1Database;
    REPORTS?: R2Bucket;
    ASSETS: Fetcher;
    IMAGES: {
      input(stream: ReadableStream): {
        transform(options: Record<string, unknown>): {
          output(options: { format: string; quality: number }): Promise<{ response(): Response }>;
        };
      };
    };
    SYNC_SECRET?: string;
  };
}
