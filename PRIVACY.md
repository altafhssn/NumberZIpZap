# Privacy Policy for ZipPath

**Effective date:** July 8, 2026  
**App:** ZipPath (Android package: `com.littletag.zipzap`)  
**Publisher:** Little Tag Art Studios

This Privacy Policy explains how ZipPath, a mobile number-path puzzle game,
accesses, collects, uses, stores, and shares information when you play the app.

## Summary of the service

ZipPath is a single-player puzzle game where players connect numbered stones,
complete levels, play a daily challenge, earn petals and Drops, use hints,
unlock color themes, and view optional online leaderboards.

The Android app uses these services:

- Google AdMob, including Google's User Messaging Platform, for banner,
  interstitial, and rewarded ads and advertising consent choices.
- Google Play Games Services for player sign-in and leaderboards.
- Firebase Authentication with Google Sign-In and Cloud Firestore for the
  optional in-game account profile used by the Settings screen.
- Google Play and the device operating system for app distribution, security,
  crash reports, and diagnostics.

The current release does not process payment-card information. The "Calm
Forever" purchase surface is marked as coming soon in the app and is not active
in this release. If paid purchases are enabled later, this policy will be
updated before that feature is made available.

## Information processed and why

### 1. Game progress stored on your device

ZipPath stores gameplay progress in the app's private storage on your device.
This local save data includes:

- Levels unlocked and completed
- Petals earned and completion times
- Selected and unlocked color themes
- In-game Drops balance
- Daily Pond streak and last-completion date
- Hint balance and last-refill time
- Sound and haptic settings
- Whether ads have been removed if a future purchase feature is enabled

This local save file is used to restore your progress and settings in the app.
Little Tag Art Studios does not upload the full save file to its own servers.
Some values derived from your progress, such as petals and completion time, may
be submitted to Google Play Games leaderboards when you are signed in to Play
Games.

### 2. Firebase Authentication and Cloud Firestore

ZipPath includes an optional Google Sign-In button in Settings. If you choose
to sign in, Firebase Authentication and Google handle the sign-in flow. ZipPath
receives account profile information from Firebase and stores a small profile
document in Cloud Firestore under your Firebase user ID.

The Firestore profile may include:

- Firebase user ID
- Google account display name
- Google account email address
- Google account profile photo URL
- Email verification status processed in the app
- Last profile update time

This information is used to keep your in-game account profile current and to
support account-related features. The Firestore security rules are designed so
that each signed-in user can read, update, and delete only their own profile
document. Little Tag Art Studios does not use this Firebase profile to sell
personal information.

Signing out of the app stops the current signed-in session on that device, but
does not automatically delete the existing Firebase profile document. To request
deletion of that profile data, contact us using the email address below.

### 3. Google Play Games Services and leaderboards

On Android, ZipPath initializes Google Play Games Services and may attempt
Play Games sign-in so that leaderboard features can work. If you authorize or
have previously authorized Play Games for ZipPath, Google manages the sign-in
flow and account choices.

When Play Games leaderboards are used, ZipPath processes:

- Your Play Games public display name
- Your Play Games avatar image URL
- Your leaderboard rank
- Your leaderboard scores, which encode petals earned and completion time
- Public display names, avatar image URLs, ranks, and scores of other players
  shown on the leaderboard screen

This data is shared with and processed by Google to authenticate players,
submit scores, and display leaderboards. Little Tag Art Studios does not
receive your Google account password or payment-card information through Play
Games. You can manage Play Games profile, privacy, and game-data settings
through your Google account and Play Games settings.

### 4. Google AdMob advertising

ZipPath uses the Google Mobile Ads SDK to display banner, interstitial, and
rewarded ads. Google's advertising services may collect and share data with
Google for ad delivery, ad measurement, analytics, fraud prevention, security,
and consent management. This may include:

- IP address, which may be used to estimate general location
- User interactions, such as app launches, taps, ad views, and video views
- Diagnostic information, such as app or SDK performance, launch time, hangs,
  crashes, and energy usage
- Device and account identifiers, such as the Android Advertising ID, App Set
  ID, and other applicable device or account identifiers
- Basic device information, such as device type, operating system, language,
  and locale
- Advertising consent choices where Google's User Messaging Platform is shown

Google may use this information to provide, personalize, measure, and protect
advertising, depending on your region, your consent choices, and your Google or
Android ad settings. Little Tag Art Studios receives aggregated advertising
reports, such as impressions and revenue, rather than your Google account
password or payment-card information.

You can manage your Advertising ID and ad-personalization choices in Android
or Google settings.

### 5. Store crash reports and diagnostics

Google Play, the device operating system, and related platform services may
collect crash reports, security signals, and technical diagnostics according to
your device, account, and store settings. Little Tag Art Studios may receive
aggregated or pseudonymous reports through developer consoles to find and fix
errors. ZipPath does not include a separate third-party analytics or attribution
SDK.

## Permissions

ZipPath requests only the permissions needed for the app features it provides:

- **Internet:** used for Google Play Games sign-in and leaderboards, Firebase
  Authentication and Firestore profile sync, AdMob advertising, consent
  management, and related diagnostics.
- **Vibrate:** used for optional haptic feedback during gameplay. Haptics can
  be disabled in the game's settings.

ZipPath does not request access to precise device location, contacts, photos,
calendar, microphone, or camera.

## How information is shared

Little Tag Art Studios does not sell personal information. Information is
shared only as needed with:

- **Google Firebase Authentication and Cloud Firestore**, for optional Google
  Sign-In and the signed-in user's profile document.
- **Google Play Games Services**, for player authentication, leaderboard score
  submission, and leaderboard display.
- **Google AdMob and the Google Mobile Ads SDK**, for advertising, ad
  measurement, analytics, consent management, security, and fraud prevention.
- **Google Play and platform providers**, for app distribution, billing if
  enabled in a future release, security, crash reporting, and diagnostics.

These providers process information under their own privacy policies and may
process it in countries other than your own.

## Security

Local progress is kept in the app's private storage. Data sent to Google
services, including Firebase, Google Play Games Services, and Google AdMob, is
transmitted using encrypted connections such as HTTPS/TLS. Firestore profile
access is limited by Firebase Authentication and Firestore security rules. No
method of electronic storage or transmission is completely secure, but we and
our service providers use reasonable safeguards appropriate to the information
processed.

## Data retention and deletion

- **Local progress:** remains on your device until you reset progress in the
  app, clear ZipPath's app data, or uninstall the app.
- **Firebase profile data:** remains in Cloud Firestore while your ZipPath
  Firebase account profile exists. You may request deletion by contacting us.
  We will delete the active profile data after verifying the request unless we
  need to retain information for legal, security, or abuse-prevention reasons.
- **Play Games data:** is retained by Google according to your Play Games
  settings and Google's policies. You can manage or request deletion of Play
  Games data through your Google account or Play Games settings.
- **Advertising, consent, and diagnostic data:** is retained by Google, the
  app store, or the relevant platform provider according to that provider's
  policies. You can manage ad privacy choices and reset or delete your
  Advertising ID in Android or Google settings.

## Children's privacy

ZipPath is a general-audience game and is not directed to children under 13 or
the minimum digital-consent age in their country. We do not knowingly collect
personal information directly from children. Google Play Games, Firebase,
AdMob, Google Play, and the device platform process information under their own
policies and account, age, consent, and regional settings. If you believe a
child has provided personal information in connection with ZipPath, contact us
so we can review the request and assist with the appropriate provider controls.

## Your privacy rights

Depending on where you live, you may have rights to access, correct, delete,
or restrict certain processing of personal information, or to object to or
withdraw consent for certain processing. To make a request, contact us below.
We may need enough information to verify and respond to your request.

## Third-party privacy information

- [Google Privacy Policy](https://policies.google.com/privacy)
- [Google advertising and cookies](https://policies.google.com/technologies/ads)
- [Google Mobile Ads SDK data disclosure](https://developers.google.com/admob/android/privacy/play-data-disclosure)
- [Google Play Games privacy information](https://support.google.com/googleplay/answer/3129346)
- [Firebase privacy and security information](https://firebase.google.com/support/privacy)

## Changes to this policy

We may update this policy when the app, its service providers, or legal
requirements change. We will post the revised policy at the privacy-policy URL
listed for ZipPath and update the effective date above.

## Contact

**Little Tag Art Studios**  
Email: **info@littletagartstudios.com**

For privacy questions or requests, email us at the address above.
