import { execFileSync } from "node:child_process";
import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const apply = process.argv.includes("--apply");
const unknownArgs = process.argv
  .slice(2)
  .filter((arg) => arg !== "--apply" && arg !== "--dry-run");
if (unknownArgs.length > 0) {
  throw new Error(`Unknown argument: ${unknownArgs[0]}`);
}

const firebaseConfig = JSON.parse(
  await readFile(resolve(root, ".firebaserc"), "utf8"),
);
const projectId = firebaseConfig.projects?.default;
if (
  typeof projectId !== "string" ||
  !/^[a-z][a-z0-9-]{4,28}[a-z0-9]$/.test(projectId)
) {
  throw new Error("A valid default Firebase project is required in .firebaserc.");
}

const accessToken = execFileSync(
  "gcloud",
  ["auth", "application-default", "print-access-token"],
  { encoding: "utf8", stdio: ["ignore", "pipe", "inherit"] },
).trim();
if (!accessToken) {
  throw new Error("Google Application Default Credentials returned an empty access token.");
}

const collectionUrl = new URL(
  `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/products`,
);
collectionUrl.searchParams.set("pageSize", "300");
const candidates = [];
let pageToken;

do {
  if (pageToken) collectionUrl.searchParams.set("pageToken", pageToken);
  else collectionUrl.searchParams.delete("pageToken");
  const response = await fetch(collectionUrl, {
    headers: { Authorization: `Bearer ${accessToken}` },
  });
  if (!response.ok) {
    throw new Error(
      `Firestore list failed with HTTP ${response.status}: ${await response.text()}`,
    );
  }
  const page = await response.json();
  for (const document of page.documents ?? []) {
    const id = document.name.split("/").at(-1);
    const name = document.fields?.name?.stringValue;
    if (id === "Auto-generated" || name === "Auto-generated") {
      candidates.push({ id, name, documentName: document.name });
    }
  }
  pageToken = page.nextPageToken;
} while (pageToken);

console.log(`Firebase project: ${projectId}`);
console.log(`Matching products: ${candidates.length}`);
for (const candidate of candidates) {
  console.log(`- id=${candidate.id}; name=${candidate.name ?? "(missing)"}`);
}

if (!apply) {
  console.log("Dry run only. Re-run with --apply to delete these exact matches.");
} else {
  for (const candidate of candidates) {
    const response = await fetch(
      `https://firestore.googleapis.com/v1/${candidate.documentName}`,
      {
        method: "DELETE",
        headers: { Authorization: `Bearer ${accessToken}` },
      },
    );
    if (!response.ok) {
      throw new Error(
        `Firestore delete failed for ${candidate.id} with HTTP ${response.status}: ` +
          (await response.text()),
      );
    }
    console.log(`Deleted product ${candidate.id}.`);
  }
}
