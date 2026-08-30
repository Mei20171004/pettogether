<p align="center">
  <img src="copaw/Resources/Assets.xcassets/AppIcon.appiconset/copaw-app-icon.png" alt="copaw logo" width="160" />
</p>

<h1 align="center">copaw</h1>

<p align="center">
  Shared pet care, without the guesswork.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Swift-5.0-F05138?logo=swift&logoColor=white" alt="Swift 5.0" />
  <img src="https://img.shields.io/badge/iOS-17%2B-000000?logo=apple&logoColor=white" alt="iOS 17+" />
  <img src="https://img.shields.io/badge/UI-SwiftUI-0D96F6?logo=swift&logoColor=white" alt="SwiftUI" />
  <img src="https://img.shields.io/badge/Backend-Firebase-FFCA28?logo=firebase&logoColor=black" alt="Firebase" />
</p>

## About

**copaw** is a real-time pet-care coordination app for households. It gives
families and shared caregivers one place to organize recurring routines and
one-time needs, decide who is responsible, and see what has already been done.

The project was built for **Shipaton Builders Weekend** to explore a simple
idea: caring for a pet should feel collaborative, clear, and dependable—even
when several people share the responsibility.

## Features

- Create a household or join one with an invite code
- Sync caregivers, routines, and tasks across devices in real time
- Add daily, selected-weekday, one-time, and urgent care tasks
- Claim tasks yourself, open them to the household, or request a specific
  caregiver
- Accept, decline, or cancel assignment requests with protected state
  transitions
- Track unclaimed, claimed, and completed work with server-authored timestamps
- Browse care plans in Today, Calendar, and Activity views
- Switch the core care experience between English and Japanese
- Keep household data private with member-scoped Firestore Security Rules

## Tech Stack

| Area | Technology |
| --- | --- |
| App | Swift 5, SwiftUI, iOS 17+ |
| Architecture | Observable state store with protocol-based service and model layers |
| Backend | Firebase Apple SDK 12.17.0 |
| Authentication | Firebase Authentication with anonymous sign-in |
| Database | Cloud Firestore with snapshot listeners and transactions |
| Dependency management | Swift Package Manager, npm |
| Security testing | Firebase Emulator Suite, `@firebase/rules-unit-testing`, Node.js test runner |

## How It Works

Caregivers share data inside a household. Firestore snapshot listeners keep the
member list, routine templates, and task occurrences current on every device.
Transactions and document revisions protect collaborative actions from stale or
conflicting updates.

```text
households/{householdID}
  members/{caregiverID}
  routines/{routineID}
  tasks/{taskOccurrenceID}

inviteCodes/{inviteCode}
```

Routine templates are expanded locally for the calendar. A Firestore task
occurrence is created only when someone first claims the routine or requests an
assignment, which avoids writing an unlimited number of future documents.

## Project Structure

```text
copaw/
├── App/          # Application entry point and Firebase configuration
├── Models/       # Household, caregiver, routine, and task models
├── Services/     # Firebase and mock care-service implementations
├── Store/        # Shared application state and actions
├── Views/        # SwiftUI screens and reusable UI components
└── Resources/    # App icon, artwork, and Firebase configuration location

tests/            # Firestore Security Rules tests
docs/             # Demo documentation
firestore.rules   # Firestore authorization and data-integrity rules
```

## Getting Started

### Prerequisites

- macOS with Xcode 15 or later
- An iPhone or iPhone Simulator running iOS 17+
- A Firebase project with Authentication and Firestore enabled
- Node.js 20+ and npm for Security Rules development

### 1. Clone the repository

```sh
git clone https://github.com/katewu1994/co-paw.git
cd co-paw
```

### 2. Configure Firebase

1. Register an iOS app in your Firebase project using the bundle identifier
   `com.copaw.demo`, or update the bundle identifier in Xcode to your own value.
2. Enable **Anonymous** as a sign-in provider in Firebase Authentication.
3. Create a Cloud Firestore database.
4. Download `GoogleService-Info.plist` and place it at:

   ```text
   copaw/Resources/GoogleService-Info.plist
   ```

The plist is intentionally ignored by Git and must never be committed.

Deploy the included Security Rules to your Firebase project:

```sh
npx firebase-tools login
npx firebase-tools deploy --only firestore:rules --project <your-project-id>
```

### 3. Run the app

1. Open `copaw.xcodeproj` in Xcode.
2. Wait for Swift Package Manager to resolve the Firebase dependencies.
3. Select an iPhone simulator or a signed physical iPhone.
4. Build and run the `copaw` scheme.

To try the real-time collaboration flow, create a household on one device and
join it from another device with the generated invite code.

## Testing

Install the JavaScript development dependencies and run the Firestore Security
Rules suite against the local emulator:

```sh
npm ci
npm run test:rules
```

The tests cover household membership, profile permissions, task creation,
assignment requests, claims, completion, and invalid state transitions.

## Contributing

Contributions are welcome. To propose a change:

1. Fork the repository and create a focused feature branch.
2. Make your changes and add or update tests where relevant.
3. Confirm that the app builds and `npm run test:rules` passes.
4. Open a pull request describing the problem, approach, and user impact.

Please keep Firebase configuration files, credentials, and other secrets out of
commits and pull requests.

## License

This repository does not currently include an open-source license. Until one is
added, the code remains protected by its authors under applicable copyright
law. If you would like to reuse the project, please contact the maintainers
first.

## Acknowledgements

Built with care during **Shipaton Builders Weekend** for pets and the people who
look after them together.
