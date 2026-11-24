import { cert, getApps, initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { FieldValue, Timestamp, getFirestore } from "firebase-admin/firestore";
import type { ApiRequest } from "./http.ts";
import { ApiError } from "./http.ts";

const expectedProjectId = "twrxa-shop";

export function getFirebaseAdmin() {
  if (process.env.FIRESTORE_EMULATOR_HOST) {
    throw new ApiError(
      503,
      "The Firestore emulator must not be configured on the deployed API.",
      "backend_misconfigured",
    );
  }

  const projectId = process.env.FIREBASE_ADMIN_PROJECT_ID;
  const clientEmail = process.env.FIREBASE_ADMIN_CLIENT_EMAIL;
  const privateKey = process.env.FIREBASE_ADMIN_PRIVATE_KEY?.replace(/\\n/g, "\n");
  if (projectId !== expectedProjectId || !clientEmail || !privateKey) {
    throw new ApiError(
      503,
      "Firebase Admin is not configured for the TWRXA project.",
      "backend_misconfigured",
    );
  }

  const app =
    getApps()[0] ??
    initializeApp({
      credential: cert({ projectId, clientEmail, privateKey }),
      projectId,
    });

  return {
    auth: getAuth(app),
    db: getFirestore(app),
    fieldValue: FieldValue,
    timestamp: Timestamp,
  };
}

export async function requireFirebaseUser(request: ApiRequest) {
  const authorization = request.headers.authorization;
  const token =
    typeof authorization === "string" && authorization.startsWith("Bearer ")
      ? authorization.slice("Bearer ".length).trim()
      : "";
  if (!token) {
    throw new ApiError(401, "Sign in to continue.", "unauthenticated");
  }

  const { auth } = getFirebaseAdmin();
  try {
    return await auth.verifyIdToken(token, true);
  } catch {
    throw new ApiError(401, "Your sign-in has expired. Please sign in again.", "unauthenticated");
  }
}
