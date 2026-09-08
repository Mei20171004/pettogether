# PetTogether Survey

Static questionnaire hosted on Firebase Hosting. Respondents sign in anonymously
with Firebase Authentication. Firebase App Check uses a domain-restricted
reCAPTCHA Enterprise score key, and the callable function rejects requests
without a valid App Check token. Valid responses are submitted through the callable
`submitSurveyResponse` function. The function validates all answers and writes
them to:

`pettogether-analysis.surveydummy.survey_responses_v3`

## Local preview

```bash
cd survey
firebase emulators:start --only hosting
```

## Deploy

Run from this directory so the project alias cannot fall back to the main app's
Firebase project:

```bash
firebase deploy --only hosting,functions:submitSurveyResponse
```

Firebase Functions deployment requires the `pettogether-analysis` project to
use the Blaze billing plan. BigQuery Sandbox tables also expire after 60 days;
upgrade billing and remove the dataset's default table expiration before using
the survey for long-running production research.
