import { canonical, validateJob } from "./core.ts";
function assert(value: boolean, message = "Assertion failed") {
  if (!value) throw Error(message);
}
Deno.test("job payload comparison is independent of key order", () => {
  assert(canonical({ a: 1, b: { c: 2 } }) === canonical({ b: { c: 2 }, a: 1 }));
  assert(canonical({ a: 1 }) !== canonical({ a: 2 }));
});
for (
  const field of [
    "password",
    "authorization",
    "access_token",
    "refresh_token",
    "service_role_key",
    "secret",
  ]
) {
  Deno.test("jobs never persist " + field, () => {
    let rejected = false;
    try {
      validateJob("import-ringmaster-records", {
        action: "lookup",
        nested: { [field]: "sensitive" },
      });
    } catch (_) {
      rejected = true;
    }
    assert(rejected);
  });
}
Deno.test("permission changes and unknown endpoints cannot become jobs", () => {
  for (
    const [target, body] of [["show-reports", { action: "enable" }], [
      "delete-account",
      {},
    ], ["global-pedigree", { username: "fixture" }]] as const
  ) {
    let rejected = false;
    try {
      validateJob(target, body);
    } catch (_) {
      rejected = true;
    }
    assert(rejected);
  }
});
Deno.test("supported jobs require their immutable approved inputs", () => {
  validateJob("email-buyer-pedigree", {
    action: "send",
    request_id: "fixture",
    recipient: "buyer@example.invalid",
    pdf: "fixture",
  });
  validateJob("global-pedigree", {
    username: "fixture",
    requires_sign_in: true,
  });
  validateJob("global-pedigree-import", { p_commit: true });
  validateJob("show-calendar", { ring_id: "fixture" });
});
