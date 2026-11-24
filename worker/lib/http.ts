export class ApiError extends Error {
  constructor(
    readonly status: number,
    message: string,
    readonly code = "request_failed",
  ) {
    super(message);
  }
}

export function jsonResponse(status: number, body: Record<string, unknown>, headers?: HeadersInit) {
  const responseHeaders = new Headers(headers);
  responseHeaders.set("Content-Type", "application/json; charset=utf-8");
  responseHeaders.set("Cache-Control", "no-store");
  return new Response(JSON.stringify(body), { status, headers: responseHeaders });
}

export function methodNotAllowed(allowed: string) {
  return jsonResponse(
    405,
    { error: "method_not_allowed", message: "Method not allowed." },
    { Allow: allowed },
  );
}

export async function readRawBody(request: Request, maximumBytes = 1_000_000) {
  const contentLength = Number(request.headers.get("content-length") ?? 0);
  if (contentLength > maximumBytes) {
    throw new ApiError(413, "Request body is too large.", "payload_too_large");
  }
  if (!request.body) return new Uint8Array();

  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let length = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    length += value.byteLength;
    if (length > maximumBytes) {
      await reader.cancel();
      throw new ApiError(413, "Request body is too large.", "payload_too_large");
    }
    chunks.push(value);
  }
  const output = new Uint8Array(length);
  let offset = 0;
  for (const chunk of chunks) {
    output.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return output;
}

export function parseJsonObject(raw: Uint8Array | string): Record<string, unknown> {
  let value: unknown;
  try {
    value = JSON.parse(typeof raw === "string" ? raw : new TextDecoder().decode(raw));
  } catch {
    throw new ApiError(400, "A valid JSON request body is required.", "invalid_json");
  }
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new ApiError(400, "A JSON object is required.", "invalid_body");
  }
  return value as Record<string, unknown>;
}

export async function readJsonBody(request: Request): Promise<Record<string, unknown>> {
  return parseJsonObject(await readRawBody(request));
}

export function errorResponse(error: unknown, context: string) {
  if (error instanceof ApiError) {
    console.warn(`[${context}] request rejected`, {
      status: error.status,
      code: error.code,
    });
    return jsonResponse(error.status, { error: error.code, message: error.message });
  }
  console.error(`[${context}] request failed`, {
    error: error instanceof Error ? error.name : "UnknownError",
  });
  return jsonResponse(500, {
    error: "internal_error",
    message: "The request could not be completed. Please try again.",
  });
}
