export const targets = new Set([
  "email-buyer-pedigree",
  "global-pedigree",
  "global-pedigree-import",
  "import-ringmaster-records",
  "show-reports",
  "show-calendar",
  "show-connection",
  "sync-breed-catalog",
]);
export function canonical(value: unknown): string {
  if (Array.isArray(value)) return "[" + value.map(canonical).join(",") + "]";
  if (value && typeof value === "object") {
    return "{" + Object.entries(value).sort(([a], [b]) =>
      a.localeCompare(b)
    ).map(([k, v]) =>
      JSON.stringify(k) + ":" + canonical(v)
    ).join(",") + "}";
  }
  return JSON.stringify(value);
}
export function validateJob(
  target: string,
  payload: Record<string, unknown>,
): void {
  if (!targets.has(target) || !payload || Array.isArray(payload)) {
    throw Error("Unsupported queued service");
  }
  const unsafe = (value: unknown): boolean =>
    !!value && typeof value === "object" &&
    Object.entries(value).some(([k, v]) =>
      /^(password|authorization|access_token|refresh_token|service_role_key|secret)$/i
        .test(k) || unsafe(v)
    );
  if (unsafe(payload)) {
    throw Error("Credentials cannot be stored in a queued request");
  }
  if (
    target === "email-buyer-pedigree" &&
    (payload.action !== "send" || typeof payload.request_id !== "string" ||
      typeof payload.pdf !== "string" || typeof payload.recipient !== "string")
  ) throw Error("Queue an approved pedigree email with its PDF and recipient");
  if (
    target === "show-reports" &&
    !["refresh", "download"].includes(String(payload.action))
  ) throw Error("Changing report permissions requires a connection");
  if (target === "show-connection" && payload.action !== "sync") {
    throw Error("Changing herd sharing requires a connection");
  }
  if (
    target === "import-ringmaster-records" &&
    !["lookup", "import"].includes(String(payload.action))
  ) throw Error("Unsupported import action");
  if (target === "global-pedigree" && payload.requires_sign_in !== true) {
    throw Error("Sign in to retrieve Global Pedigree records");
  }
  if (target === "global-pedigree-import" && payload.p_commit !== true) {
    throw Error("Review an import before queueing it");
  }
}
