import { applicationDefault, initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";

function optionValue(name) {
  const index = process.argv.indexOf(name);
  return index < 0 ? null : (process.argv[index + 1] ?? null);
}

const id = optionValue("--id");
const name = optionValue("--name");
const confirmed = process.argv.includes("--confirm");
if (Boolean(id) === Boolean(name) || id?.startsWith("--") || name?.startsWith("--")) {
  throw new Error("Choose exactly one target: --id <document-id> or --name <exact-product-name>.");
}

const projectId =
  process.env.GOOGLE_CLOUD_PROJECT ?? process.env.GCLOUD_PROJECT ?? process.env.FIREBASE_PROJECT_ID;
const app = initializeApp({
  credential: applicationDefault(),
  ...(projectId ? { projectId } : {}),
});

try {
  const products = getFirestore(app).collection("products");
  const matches = id
    ? [await products.doc(id).get()].filter((document) => document.exists)
    : (await products.where("name", "==", name).get()).docs;

  if (matches.length === 0) {
    console.log("No matching product document was found.");
  } else if (matches.length > 1) {
    console.error(
      "Multiple documents match. No data was changed; inspect these exact IDs and retry with --id:",
      matches.map((document) => document.id),
    );
    process.exitCode = 1;
  } else {
    const document = matches[0];
    console.log("Matching product:", {
      id: document.id,
      name: document.get("name") ?? null,
    });
    if (!confirmed) {
      console.log("Dry run only. Add --confirm to permanently delete this document.");
    } else {
      await document.ref.delete();
      console.log("Deleted the product document.");
    }
  }
} finally {
  await app.delete();
}
