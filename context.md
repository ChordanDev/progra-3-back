# Code Context

## Files Retrieved
1. `/Users/luccagiordana/.pi/agent/skills/elixir/SKILL.md` (lines 1-57) - loaded required Elixir guidance.
2. `/Users/luccagiordana/.pi/agent/skills/phoenix/SKILL.md` (lines 1-68) - loaded required Phoenix guidance.
3. `lib/my_food_back_web/router.ex` (lines 1-22) - API auth routes and absence of Swoosh mailbox route.
4. `lib/my_food_back_web/controllers/auth_controller.ex` (lines 1-102) - request/verify endpoints, request options, error status mapping.
5. `lib/my_food_back_web/controllers/auth_json.ex` (lines 1-20) - response camel-casing for API clients.
6. `lib/my_food_back/auth.ex` (lines 1-220, 221-380, 500-511) - core request-code/verify-code flow, code generation, hashing, cooldown, email delivery call.
7. `lib/my_food_back/auth/email_code.ex` (lines 1-33) - `email_codes` schema and validations.
8. `lib/my_food_back/rate_limits.ex` (lines 1-122) - request-code rate-limit checks and recording.
9. `lib/my_food_back/email_delivery.ex` (lines 1-22) - current Swoosh email construction and delivery abstraction.
10. `lib/my_food_back/mailer.ex` (lines 1-3) - Swoosh mailer module.
11. `lib/my_food_back/application.ex` (lines 1-37) - supervision tree; no mailer worker is started.
12. `mix.exs` (lines 1-74) - dependencies include `:swoosh` and `:req`; precommit alias.
13. `config/config.exs` (lines 1-29) - default mailer config uses `Swoosh.Adapters.Local`.
14. `config/dev.exs` (lines 1-34) - dev disables Swoosh API client.
15. `config/test.exs` (lines 1-35) - test uses `Swoosh.Adapters.Test`.
16. `config/prod.exs` (lines 1-21) - prod sets `Swoosh.ApiClient.Req` and disables local mailbox storage.
17. `config/runtime.exs` (lines 90-119) - generated comments for configuring production mailer adapter, but no active adapter config.
18. `priv/repo/migrations/20260607232722_create_email_codes.exs` (lines 1-24) - persisted code table shape and indexes.
19. `test/my_food_back/auth/email_code_test.exs` (lines 1-260) - context-level tests assert Swoosh test delivery and extract code from email body.
20. `test/my_food_back_web/controllers/auth_controller_test.exs` (lines 1-130, 220-260) - controller/E2E API tests around request-code and verify-code.

## Key Code

### API entry points
`lib/my_food_back_web/router.ex` exposes JSON API routes only:

```elixir
scope "/api", MyFoodBackWeb do
  pipe_through(:api)

  post("/auth/signup/request-code", AuthController, :signup_request_code)
  post("/auth/signup/verify-code", AuthController, :signup_verify_code)
  post("/auth/login/request-code", AuthController, :login_request_code)
  post("/auth/login/verify-code", AuthController, :login_verify_code)
end
```

No `Swoosh.MailboxPreview` / mailbox route is mounted under `lib/my_food_back_web/router.ex`, and `grep` found no `Swoosh.Mailbox` references in `lib`.

### Controller flow
`lib/my_food_back_web/controllers/auth_controller.ex` routes request-code calls to the auth context:

```elixir
def signup_request_code(conn, params) do
  params
  |> Auth.request_signup_code(request_opts(conn))
  |> respond(conn, :code_sent)
end

def login_request_code(conn, params) do
  params
  |> Auth.request_login_code(request_opts(conn))
  |> respond(conn, :code_sent)
end
```

`request_opts/1` currently passes `ip` and `user_agent`; device id is only normalized for verify calls, so request-time device rate limiting is currently not populated from the controller.

### Auth request-code flow
`lib/my_food_back/auth.ex`:

```elixir
def request_signup_code(attrs, opts \\ []) do
  email = normalize_email(attrs)

  with :ok <- validate_email(email),
       :ok <- ensure_user_missing(email),
       :ok <- request_code(:signup, email, opts) do
    {:ok, code_sent_response()}
  end
end

def request_login_code(attrs, opts \\ []) do
  email = normalize_email(attrs)

  with :ok <- validate_email(email),
       :ok <- ensure_user_exists(email),
       :ok <- request_code(:login, email, opts) do
    {:ok, code_sent_response()}
  end
end
```

`request_code/3` does the important work:

1. Computes `now` and inserts it into opts.
2. Checks resend cooldown against latest `email_codes.last_sent_at`.
3. Checks rate limits via `RateLimits.check_request_code/3`.
4. Generates a random 6-digit code.
5. Hashes it with HMAC using endpoint `secret_key_base`.
6. Invalidates active prior codes for same email + flow.
7. Inserts a new `EmailCode` row.
8. Records rate-limit events.
9. Calls `EmailDelivery.deliver_code(email, code, flow)`.

Current transaction boundary: the DB insert/invalidations are committed before email delivery. If delivery fails, API returns `{:error, reason}` but the code row remains active and the rate-limit event has likely been recorded.

### Code storage and verification
`EmailCode` fields include `email`, `flow`, `code_hash`, `expires_at`, `attempt_count`, `consumed_at`, `invalidated_at`, `last_sent_at`, `request_ip_hash`, `device_id_hash`.

`verify_code/3` loads latest active code, checks format/expiry/attempts, compares against `hash_code(flow, email, code)`, and then consumes the code inside account/session creation. Signup creates an individual account; login requires an existing user.

### Current email delivery module
`lib/my_food_back/email_delivery.ex` already uses Swoosh:

```elixir
def deliver_code(email, code, flow) when flow in [:signup, :login] do
  subject = subject_for(flow)

  new()
  |> to(email)
  |> from({"Meal Planner", "no-reply@example.com"})
  |> subject(subject)
  |> text_body("Tu código de acceso es #{code}. Expira en 10 minutos.")
  |> Mailer.deliver()
  |> case do
    {:ok, _metadata} -> :ok
    {:error, reason} -> {:error, reason}
  end
end
```

This means the app already has a mailer abstraction; adding real email delivery is mostly config + sender identity + provider env handling, not a new auth flow.

## Architecture

Client posts to `/api/auth/signup/request-code` or `/api/auth/login/request-code` with an email. `AuthController` forwards params and request metadata to `MyFoodBack.Auth`. The auth context normalizes and validates the email, enforces signup/login existence rules, applies cooldown and DB-backed rate limiting, persists only a hashed code in `email_codes`, then calls `MyFoodBack.EmailDelivery`. `EmailDelivery` builds a Swoosh email and uses `MyFoodBack.Mailer`, whose adapter is controlled by config.

Current mail setup:

- Dependency: `{:swoosh, "~> 1.16"}` exists.
- Dependency: `{:req, "~> 0.5"}` exists and project guidelines prefer Req for HTTP.
- `MyFoodBack.Mailer` exists and uses `Swoosh.Mailer, otp_app: :my_food_back`.
- Default config: `config/config.exs` sets `adapter: Swoosh.Adapters.Local`.
- Dev: `config/dev.exs` disables Swoosh API client and does not mount mailbox UI.
- Test: `config/test.exs` sets `Swoosh.Adapters.Test`; tests assert sent emails via Swoosh test assertions / `assert_received {:email, email}`.
- Prod compile-time: `config/prod.exs` sets `config :swoosh, api_client: Swoosh.ApiClient.Req` and `config :swoosh, local: false`.
- Prod runtime: `config/runtime.exs` only has commented example Mailgun config. There is no active production provider adapter.

## Files/functions to edit for real delivery

1. `config/runtime.exs` - add active production/runtime mailer adapter configuration from env vars. This is the main missing piece.
2. `lib/my_food_back/email_delivery.ex` - replace hardcoded `from({"Meal Planner", "no-reply@example.com"})` with configured sender name/address, and likely make text copy/product sender final.
3. Optional: `config/dev.exs` / `lib/my_food_back_web/router.ex` - for local developer recovery, either configure a real dev adapter/env or mount Swoosh mailbox preview in dev-only routes. User context says mailbox is not mounted, but if next slice requires real email, mailbox mounting is optional.
4. Optional: `lib/my_food_back_web/controllers/auth_controller.ex` - include request-time `device_id` if clients send it during request-code and the existing device rate-limit is intended to apply before sending.
5. Optional tests in `test/my_food_back/auth/email_code_test.exs` - assert configured sender/from once sender config is added.

## Tests available

- `test/my_food_back/auth/email_code_test.exs` covers signup/login code request and verification primitives, including that a Swoosh email is sent and contains a six-digit code.
- `test/my_food_back_web/controllers/auth_controller_test.exs` covers API request-code/verify-code flows and extracts the delivered code from test mailbox messages.
- `mix precommit` alias exists and runs compile warnings-as-errors, unused deps check, format, and test.

## Recommended minimal implementation

1. Pick one Swoosh production adapter/provider. Since `Req` is already configured in prod and project guidelines prefer Req, a Swoosh HTTP API adapter such as Mailgun/Sendgrid/Resend-compatible setup is preferable over adding another HTTP client. Exact adapter depends on chosen provider and credentials.
2. In `config/runtime.exs`, configure `MyFoodBack.Mailer` for prod from env vars, failing fast if required env vars are missing. Keep `config/prod.exs` with `Swoosh.ApiClient.Req`.
3. Add app config for sender identity, for example `:mail_from_name` / `:mail_from_address`, sourced from env in runtime config.
4. Update `EmailDelivery.deliver_code/3` to read the sender config instead of hardcoding `no-reply@example.com`.
5. Keep `Swoosh.Adapters.Test` unchanged; add/adjust tests to assert sender config if implemented.
6. Run targeted tests first (`mix test test/my_food_back/auth/email_code_test.exs test/my_food_back_web/controllers/auth_controller_test.exs`), then `mix precommit` when implementation is done.

## Risks and open questions

- Provider choice is not encoded in the repo. Need a product/ops decision: Mailgun, SendGrid, Resend, SMTP, etc. This determines adapter/env variable names.
- Current request-code DB transaction commits before `Mailer.deliver/1`. If real delivery fails, an active code remains stored and rate limits may be consumed even though the user did not receive the code. Decide whether this is acceptable for first slice or whether to invalidate/delete on delivery failure.
- Hardcoded sender `no-reply@example.com` will fail/domain-spam with real providers. Needs verified sender/domain.
- Dev uses `Swoosh.Adapters.Local` but mailbox route is not mounted, so local manual recovery currently requires DB/dev workarounds unless real delivery is configured for dev too.
- The email text is Spanish (`Tu código...`) while technical artifacts are English. Confirm desired product copy/language before polishing.
- Rate limit has a device dimension, but controller request-code opts do not currently include `device_id`; only verify-code normalizes `deviceId`.
- No Engram memory tools were available in this subagent toolset, so discoveries could not be saved to Engram from here.
