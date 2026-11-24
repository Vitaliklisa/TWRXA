import type { IncomingMessage, ServerResponse } from "node:http";

export type ApiRequest = IncomingMessage & {
  body?: unknown;
  query?: Record<string, string | string[] | undefined>;
};

export type ApiResponse = ServerResponse;
export type JsonObject = Record<string, unknown>;

export class ApiError extends Error {
  readonly status: number;
  readonly code: string;

  constructor(status: number, message: string, code = "request_failed") {
    super(message);
    this.status = status;
    this.code = code;
  }
}

export function sendJson(response: ApiResponse, status: number, body: JsonObject) {
  response.statusCode = status;
  response.setHeader("Content-Type", "application/json; charset=utf-8");
  response.setHeader("Cache-Control", "no-store");
  response.end(JSON.stringify(body));
}

export function methodNotAllowed(response: ApiResponse, allowed: string) {
  response.setHeader("Allow", allowed);
  sendJson(response, 405, {
    error: "method_not_allowed",
    message: "Method not allowed.",
  });
}

export async function readRawBody(request: ApiRequest, maximumBytes = 1_000_000): Promise<Buffer> {
  const chunks: Buffer[] = [];
  let length = 0;
  for await (const chunk of request) {
    const bytes = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
    length += bytes.length;
    if (length > maximumBytes) {
      throw new ApiError(413, "Request body is too large.", "payload_too_large");
    }
    chunks.push(bytes);
  }
  return Buffer.concat(chunks);
}

export async function readJsonBody(
  request: ApiRequest,
  maximumBytes = 1_000_000,
): Promise<JsonObject> {
  if (request.body !== undefined) {
    if (
      request.body &&
      typeof request.body === "object" &&
      !Buffer.isBuffer(request.body) &&
      !Array.isArray(request.body)
    ) {
      return request.body as JsonObject;
    }
    if (typeof request.body === "string" || Buffer.isBuffer(request.body)) {
      return parseJsonObject(Buffer.from(request.body).toString("utf8"));
    }
    throw new ApiError(400, "A JSON request body is required.", "invalid_body");
  }
  return parseJsonObject((await readRawBody(request, maximumBytes)).toString("utf8"));
}

export function parseJsonObject(value: string): JsonObject {
  let parsed: unknown;
  try {
    parsed = JSON.parse(value);
  } catch {
    throw new ApiError(400, "A valid JSON request body is required.", "invalid_json");
  }
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    throw new ApiError(400, "A JSON object is required.", "invalid_body");
  }
  return parsed as JsonObject;
}

export function handleApiError(response: ApiResponse, error: unknown, context: string) {
  if (error instanceof ApiError) {
    console.warn(`[${context}] request rejected`, {
      status: error.status,
      code: error.code,
    });
    sendJson(response, error.status, {
      error: error.code,
      message: error.message,
    });
    return;
  }
  console.error(`[${context}] request failed`, {
    error: error instanceof Error ? error.name : "UnknownError",
  });
  sendJson(response, 500, {
    error: "internal_error",
    message: "The request could not be completed. Please try again.",
  });
}
