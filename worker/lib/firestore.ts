import { googleAccessToken, logGoogleResponseFailure } from "./google.ts";
import { ApiError } from "./http.ts";
import type { Env } from "../types.ts";

const projectId = "twrxa-shop";
const database = "(default)";
const apiRoot = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/${database}`;
export const DELETE_FIELD = Symbol("delete-field");

export type FirestoreDocument = {
  id: string;
  fields: Record<string, unknown>;
  updateTime?: string;
};

type FirestoreValue = Record<string, unknown>;

export class FirestoreConflict extends Error {}

function encodeValue(value: unknown): FirestoreValue {
  if (value === null) return { nullValue: "NULL_VALUE" };
  if (value === DELETE_FIELD) return {};
  if (value instanceof Date) return { timestampValue: value.toISOString() };
  if (typeof value === "string") return { stringValue: value };
  if (typeof value === "boolean") return { booleanValue: value };
  if (typeof value === "number") {
    if (!Number.isFinite(value)) throw new TypeError("Firestore numbers must be finite.");
    return Number.isSafeInteger(value) ? { integerValue: String(value) } : { doubleValue: value };
  }
  if (Array.isArray(value)) {
    return { arrayValue: { values: value.map(encodeValue) } };
  }
  if (typeof value === "object") {
    return { mapValue: { fields: encodeFields(value as Record<string, unknown>) } };
  }
  throw new TypeError("Unsupported Firestore value.");
}

function encodeFields(values: Record<string, unknown>) {
  const fields: Record<string, FirestoreValue> = {};
  for (const [key, value] of Object.entries(values)) {
    if (value !== DELETE_FIELD) fields[key] = encodeValue(value);
  }
  return fields;
}

function decodeValue(value: FirestoreValue): unknown {
  if ("nullValue" in value) return null;
  if ("stringValue" in value) return value.stringValue;
  if ("booleanValue" in value) return value.booleanValue;
  if ("integerValue" in value) return Number(value.integerValue);
  if ("doubleValue" in value) return Number(value.doubleValue);
  if ("timestampValue" in value) return new Date(String(value.timestampValue));
  if ("mapValue" in value) {
    const fields = (value.mapValue as { fields?: Record<string, FirestoreValue> }).fields ?? {};
    return decodeFields(fields);
  }
  if ("arrayValue" in value) {
    const values = (value.arrayValue as { values?: FirestoreValue[] }).values ?? [];
    return values.map(decodeValue);
  }
  if ("referenceValue" in value) return value.referenceValue;
  throw new TypeError("Firestore returned an unsupported value type.");
}

function decodeFields(fields: Record<string, FirestoreValue> = {}) {
  return Object.fromEntries(
    Object.entries(fields).map(([key, value]) => [key, decodeValue(value)]),
  );
}

function documentPathSegments(path: string) {
  const segments = path.split("/");
  if (
    segments.length === 0 ||
    segments.some((segment) => !segment || segment === "." || segment === "..")
  ) {
    throw new TypeError("Invalid Firestore document path.");
  }
  return segments;
}

function pathUrl(path: string) {
  const segments = documentPathSegments(path);
  return `${apiRoot}/documents/${segments.map(encodeURIComponent).join("/")}`;
}

function documentResourceName(path: string) {
  return `projects/${projectId}/databases/${database}/documents/${documentPathSegments(path).join("/")}`;
}

async function authorizedFetch(env: Env, input: RequestInfo | URL, init: RequestInit = {}) {
  const token = await googleAccessToken(env);
  const headers = new Headers(init.headers);
  headers.set("Authorization", `Bearer ${token}`);
  headers.set("Accept", "application/json");
  if (init.body !== undefined) headers.set("Content-Type", "application/json");
  return fetch(input, { ...init, headers });
}

async function parseResponse(response: Response) {
  if (response.status === 404) return null;
  if (response.status === 409 || response.status === 412) throw new FirestoreConflict();
  if (!response.ok) {
    await logGoogleResponseFailure(response, "firestore");
    throw new ApiError(503, "Firestore request failed.", "backend_unavailable");
  }
  return (await response.json()) as Record<string, unknown>;
}

function decodeDocument(document: Record<string, unknown>): FirestoreDocument {
  const name = String(document.name ?? "");
  const id = decodeURIComponent(name.split("/").pop() ?? "");
  return {
    id,
    fields: decodeFields((document.fields as Record<string, FirestoreValue>) ?? {}),
    ...(typeof document.updateTime === "string" ? { updateTime: document.updateTime } : {}),
  };
}

export async function getDoc(env: Env, path: string) {
  const response = await authorizedFetch(env, pathUrl(path));
  const result = await parseResponse(response);
  return result ? decodeDocument(result) : null;
}

function appendUpdateMask(url: URL, fields: Record<string, unknown>) {
  for (const key of Object.keys(fields)) url.searchParams.append("updateMask.fieldPaths", key);
}

export async function setDoc(
  env: Env,
  path: string,
  fields: Record<string, unknown>,
  merge = true,
) {
  const url = new URL(pathUrl(path));
  if (merge) appendUpdateMask(url, fields);
  const response = await authorizedFetch(env, url, {
    method: "PATCH",
    body: JSON.stringify({ fields: encodeFields(fields) }),
  });
  const result = await parseResponse(response);
  if (!result) throw new ApiError(503, "Firestore write failed.", "backend_unavailable");
  return decodeDocument(result);
}

export async function updateDoc(
  env: Env,
  path: string,
  fields: Record<string, unknown>,
  updateTime?: string,
) {
  const url = new URL(pathUrl(path));
  appendUpdateMask(url, fields);
  if (updateTime) url.searchParams.set("currentDocument.updateTime", updateTime);
  const response = await authorizedFetch(env, url, {
    method: "PATCH",
    body: JSON.stringify({ fields: encodeFields(fields) }),
  });
  const result = await parseResponse(response);
  if (!result) throw new ApiError(404, "Firestore document was not found.", "not_found");
  return decodeDocument(result);
}

export async function createDoc(env: Env, path: string, fields: Record<string, unknown>) {
  const segments = path.split("/");
  const id = segments.pop();
  if (!id || segments.length % 2 !== 1) throw new TypeError("Invalid Firestore document path.");
  const collectionPath = segments.map(encodeURIComponent).join("/");
  const url = new URL(`${apiRoot}/documents/${collectionPath}`);
  url.searchParams.set("documentId", id);
  const response = await authorizedFetch(env, url, {
    method: "POST",
    body: JSON.stringify({ fields: encodeFields(fields) }),
  });
  const result = await parseResponse(response);
  if (!result) throw new ApiError(503, "Firestore write failed.", "backend_unavailable");
  return decodeDocument(result);
}

export async function addDoc(env: Env, collection: string, fields: Record<string, unknown>) {
  const url = new URL(
    `${apiRoot}/documents/${collection.split("/").map(encodeURIComponent).join("/")}`,
  );
  const response = await authorizedFetch(env, url, {
    method: "POST",
    body: JSON.stringify({ fields: encodeFields(fields) }),
  });
  const result = await parseResponse(response);
  if (!result) throw new ApiError(503, "Firestore write failed.", "backend_unavailable");
  return decodeDocument(result);
}

export async function queryEqual(
  env: Env,
  collection: string,
  field: string,
  value: unknown,
  limit = 1,
) {
  const parent = `projects/${projectId}/databases/${database}/documents`;
  const response = await authorizedFetch(env, `${apiRoot}/documents:runQuery`, {
    method: "POST",
    body: JSON.stringify({
      parent,
      structuredQuery: {
        from: [{ collectionId: collection }],
        where: {
          fieldFilter: {
            field: { fieldPath: field },
            op: "EQUAL",
            value: encodeValue(value),
          },
        },
        limit,
      },
    }),
  });
  if (!response.ok) {
    await logGoogleResponseFailure(response, "firestore-query");
    throw new ApiError(503, "Firestore query failed.", "backend_unavailable");
  }
  const results = (await response.json()) as Array<{ document?: Record<string, unknown> }>;
  return results.flatMap((result) => (result.document ? [decodeDocument(result.document)] : []));
}

export async function setDocsBatch(
  env: Env,
  entries: Array<{ path: string; fields: Record<string, unknown> }>,
) {
  if (entries.length === 0) return;
  const writes = entries.map(({ path, fields }) => ({
    update: {
      name: documentResourceName(path),
      fields: encodeFields(fields),
    },
    updateMask: { fieldPaths: Object.keys(fields) },
  }));
  const response = await authorizedFetch(env, `${apiRoot}/documents:commit`, {
    method: "POST",
    body: JSON.stringify({ writes }),
  });
  if (!response.ok) {
    await logGoogleResponseFailure(response, "firestore-batch-write");
    throw new ApiError(503, "Firestore batch write failed.", "backend_unavailable");
  }
}
