# Control-plane API contract (v1)

The iOS client talks to a separately deployed control-plane service. This repository does not yet contain that service or provision cloud machines.

All endpoints are relative to the configured backend URL. Responses use JSON and UTF-8.

## Health

`GET /health`

Returns HTTP 200 when the API is ready. The iOS Settings screen uses this endpoint for its connection test.

## List workspaces

`GET /api/v1/workspaces`

Returns an array:

```json
[
  {
    "id": "ws_01",
    "name": "My Windows PC",
    "operating_system": "windows",
    "status": "provisioning"
  }
]
```

Supported `operating_system` values: `windows`, `linux`.

## Create workspace

`POST /api/v1/workspaces`

Request:

```json
{
  "name": "My Windows PC",
  "operating_system": "windows"
}
```

Returns the created workspace using the same object shape as the list endpoint. The API should return promptly with a `provisioning` status; provisioning continues asynchronously.

## Stop workspace

`DELETE /api/v1/workspaces/{id}`

Returns any successful 2xx response after accepting the stop request.

## Required service behavior before production

- Authenticate every workspace endpoint; bind each workspace to the authenticated owner.
- Validate names and OS values server-side.
- Enforce per-user quotas and provider budget limits before provisioning.
- Provision isolated Windows/Linux workers and encrypted persistent storage.
- Never return provider credentials, host management ports, or long-lived secrets to the app.
- Return short-lived connection tickets only after a separate session-connect authorization step.
- Make create/stop operations idempotent and audit all lifecycle transitions.
- Apply rate limits and strict request-size limits.

## Current implementation boundary

The iOS app now has typed list/create/stop calls and workspace UI. Until a backend implementing this contract is deployed and its URL is entered in Settings, these actions will return a connection error. This contract is not itself a running cloud service.
