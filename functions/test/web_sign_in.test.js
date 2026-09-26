const test = require("node:test");
const assert = require("node:assert/strict");
const { issueWebSignInToken } = require("../web_sign_in");

test("rejects a request without verified Firebase Auth", async () => {
  await assert.rejects(
    issueWebSignInToken({ data: { uid: "forged" } }, {
      createCustomToken: () => assert.fail("must not sign a forged uid"),
    }),
    { code: "unauthenticated" },
  );
});

test("signs only the UID supplied by verified callable auth", async () => {
  const signed = [];
  const result = await issueWebSignInToken(
    { auth: { uid: "verified-user" }, data: { uid: "forged" } },
    {
      createCustomToken: async (uid) => {
        signed.push(uid);
        return "custom-token";
      },
    },
  );
  assert.deepEqual(signed, ["verified-user"]);
  assert.deepEqual(result, { customToken: "custom-token" });
});
