# Navigo Firebase Cloud Functions

## createRouteManager

`createRouteManager` is a callable HTTPS Cloud Function used by the admin panel
to create route manager accounts securely.

### Security

- The caller must be signed in with Firebase Authentication.
- The caller must have a Firestore profile at `users/{uid}`.
- `users/{uid}.role` must be exactly `admin`.
- The client never writes route-manager Auth accounts directly.

### Writes

For a new route manager, the function creates:

- Firebase Authentication user with generated `uid`
- `users/{uid}`
- `routeManagers/{uid}`
- Compatibility mirrors for existing app code:
  - `route_manger/{uid}`
  - `route_manager/{uid}`

### Deploy

From the project root:

```sh
cd functions
npm install
cd ..
firebase login
firebase use navigo-c89a0
firebase deploy --only functions:createRouteManager
```

To deploy every function:

```sh
firebase deploy --only functions
```

### Google Maps secret

`fetchRoutePolyline` reads the Google Maps key from a Firebase Functions secret.
Configure it before deploying or calling that function:

```sh
firebase functions:secrets:set GOOGLE_MAPS_API_KEY
firebase deploy --only functions:fetchRoutePolyline
```

Do not put the key in source code, logs, API responses, or committed config
files.

## Driver approval callables

`approveDriverAccount` and `rejectDriverAccount` are callable HTTPS Cloud
Functions used by the admin panel.

### Security

- The caller must be signed in with Firebase Authentication.
- The caller must have a Firestore profile at `users/{uid}`.
- `users/{uid}.role` must be exactly `admin`.
- Non-admin callers receive `permission-denied`.

To view function logs:

```sh
firebase functions:log --only createRouteManager
```

### Required admin profile

The signed-in admin must have a Firestore document like:

```json
{
  "userId": "ADMIN_AUTH_UID",
  "email": "admin@example.com",
  "role": "admin",
  "isVerified": true
}
```
