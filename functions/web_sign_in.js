const { HttpsError } = require("firebase-functions/v2/https");

// The callable SDK verifies the Firebase ID token before populating
// request.auth. Never accept a uid from request.data here.
async function issueWebSignInToken(request, auth) {
  const uid = request.auth?.uid;
  if (typeof uid !== "string" || uid.length === 0) {
    throw new HttpsError("unauthenticated", "Sign in to the app first.");
  }
  return { customToken: await auth.createCustomToken(uid) };
}

module.exports = { issueWebSignInToken };
