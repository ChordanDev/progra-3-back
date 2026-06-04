# Code Context

## Files Retrieved
1. `mix.exs` (lines 1-78) - dependencies, compilers, and current Mix aliases, including asset aliases and test/precommit.
2. `config/config.exs` (lines 1-57) - endpoint formats, error renderers, LiveView signing salt, esbuild/tailwind config.
3. `config/dev.exs` (lines 1-83) - dev PostgreSQL credentials, asset watchers, live reload, dev routes.
4. `config/test.exs` (lines 1-39) - test PostgreSQL credentials and sandbox settings.
5. `config/prod.exs` (lines 1-28) - static cache manifest, SSL, Swoosh API config.
6. `config/runtime.exs` (lines 1-112) - runtime server, port, `DATABASE_URL`, `SECRET_KEY_BASE`, prod endpoint URL.
7. `lib/my_food_back_web/router.ex` (lines 1-39) - browser/api pipelines, root PageController route, dev dashboard/mailbox routes.
8. `lib/my_food_back_web.ex` (lines 1-86) - web macro entrypoints, `static_paths/0`, controller/html imports and formats.
9. `lib/my_food_back_web/endpoint.ex` (lines 1-55) - LiveView socket, static plug, parsers, session plug, router plug.
10. `lib/my_food_back_web/controllers/page_controller.ex` (lines 1-7) - default HTML page controller.
11. `lib/my_food_back_web/controllers/page_html.ex` (lines 1-9) - embeds default page templates.
12. `lib/my_food_back_web/controllers/page_html/home.html.heex` (lines 1-120+) - generated Phoenix landing page template.
13. `lib/my_food_back_web/controllers/error_html.ex` (lines 1-19) - HTML error renderer.
14. `lib/my_food_back_web/controllers/error_json.ex` (lines 1-16) - JSON error renderer.
15. `lib/my_food_back_web/components/layouts.ex` (lines 1-130+) - layout, flash group, theme toggle, CoreComponents dependency.
16. `lib/my_food_back_web/components/layouts/root.html.heex` (lines 1-31) - HTML root layout, asset tags, inline theme script.
17. `assets/css/app.css` (lines 1-102) - Tailwind v4 imports and daisyUI/heroicons plugin usage.
18. `assets/js/app.js` (lines 1-72) - LiveView JS setup, topbar, colocated hooks, phoenix_html.
19. `lib/my_food_back/application.ex` (lines 1-35) - app supervision tree: Telemetry, Repo, PubSub, Endpoint.
20. `test/support/conn_case.ex` (lines 1-34) - ConnCase imports verified routes and uses sandbox.
21. `test/support/data_case.ex` (lines 1-57) - DataCase sandbox setup and changeset error helper.
22. `test/my_food_back_web/controllers/page_controller_test.exs` (lines 1-8) - default landing page test.
23. `test/my_food_back_web/controllers/error_html_test.exs` (lines 1-13) - HTML error renderer tests.
24. `test/my_food_back_web/controllers/error_json_test.exs` (lines 1-12) - JSON error renderer tests.

## Key Code

### Current Mix aliases (`mix.exs` lines 68-78)
```elixir
setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
"ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
"ecto.reset": ["ecto.drop", "ecto.setup"],
test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
"assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
"assets.build": ["compile", "tailwind my_food_back", "esbuild my_food_back"],
"assets.deploy": ["tailwind my_food_back --minify", "esbuild my_food_back --minify", "phx.digest"],
precommit: ["compile --warnings-as-errors", "deps.unlock --unused", "format", "test"]
```
For API-only, remove or simplify `assets.*` aliases if all HTML/assets are deleted. `setup` should stop invoking asset setup/build.

### Current dependencies and frontend coupling (`mix.exs` lines 33-57)
Frontend/HTML/LiveView-specific deps currently include:
- `:phoenix_html`
- `:phoenix_live_reload` dev-only
- `:phoenix_live_view`
- `:lazy_html` test-only
- `:phoenix_live_dashboard`
- `:esbuild`
- `:tailwind`
- `:heroicons`

API/backend deps to keep likely include Phoenix, Phoenix Ecto, Ecto SQL, Postgrex, Swoosh/Req if mail remains, telemetry, gettext if still needed, Jason, dns_cluster, Bandit.

### Router and pipelines (`lib/my_food_back_web/router.ex` lines 4-39)
```elixir
pipeline :browser do
  plug :accepts, ["html"]
  plug :fetch_session
  plug :fetch_live_flash
  plug :put_root_layout, html: {MyFoodBackWeb.Layouts, :root}
  plug :protect_from_forgery
  plug :put_secure_browser_headers
end

pipeline :api do
  plug :accepts, ["json"]
end

scope "/", MyFoodBackWeb do
  pipe_through :browser
  get "/", PageController, :home
end
```
API-only should remove the browser scope and default root page. Keep/add JSON routes under `pipeline :api`, usually scoped under `/api`. Dev dashboard/mailbox currently uses browser pipeline; if keeping it, browser/session/layout deps remain.

### Endpoint frontend/session/static hooks (`lib/my_food_back_web/endpoint.ex` lines 7-55)
Current API-only cleanup candidates:
- `@session_options` and `Plug.Session` if no browser session/auth cookies are used.
- `socket "/live", Phoenix.LiveView.Socket` if no LiveView.
- `Plug.Static` if no local static assets are served.
- `Phoenix.LiveReloader` socket/plug if no frontend live reload.
- `Phoenix.LiveDashboard.RequestLogger` if dashboard removed.
- Keep `Plug.RequestId`, `Plug.Telemetry`, `Plug.Parsers`, `Plug.MethodOverride`, `Plug.Head`, router.

### Web macro coupling (`lib/my_food_back_web.ex` lines 16-75)
- `static_paths/0` currently returns `~w(assets fonts images favicon.ico robots.txt)`.
- `router/0` imports `Phoenix.LiveView.Router`.
- `controller/0` uses `Phoenix.Controller, formats: [:html, :json]`.
- `live_view/0`, `live_component/0`, `html/0`, and `html_helpers/0` exist only for HTML/LiveView/UI.
For clean API-only, reduce controller formats to JSON if no HTML controllers remain, remove LiveView/html macros if unused, and remove `static_paths/0`/VerifiedRoutes statics if no static serving.

### Test DB credentials (`config/test.exs` lines 8-15)
```elixir
config :my_food_back, MyFoodBack.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "my_food_back_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2
```
Dev DB differs (`config/dev.exs` lines 4-11): username `luccagiordana`, password `""`, database `my_food_back_dev`. If local PostgreSQL uses the macOS user with trust/no password, test config likely needs matching local credentials or environment-driven config.

### Error renderers
- `config/config.exs` lines 17-20 currently declares both HTML and JSON error renderers.
- `ErrorHTML` is only needed for HTML requests; `ErrorJSON` is appropriate for API.
API-only should change `render_errors` to JSON-only unless intentionally supporting HTML error pages.

## Architecture

This is a freshly generated Phoenix 1.8 web app, not yet a domain API. The runtime path is:

`MyFoodBack.Application` starts `MyFoodBackWeb.Endpoint` -> endpoint runs parsers/session/static/live reload hooks -> `MyFoodBackWeb.Router` routes `/` through `:browser` -> `PageController.home/2` renders embedded HEEx template through `PageHTML` and `Layouts`.

There are currently no domain contexts, schemas, API controllers, JSON views, or migrations beyond the base Repo setup visible in the inspected files. The project is heavily coupled to generated HTML/LiveView/assets defaults.

## Files likely to delete for clean API-only

Delete only after confirming no HTML/dev-dashboard requirement:

- `assets/` entirely (`assets/css/app.css`, `assets/js/app.js`, `assets/vendor/*`) if no frontend bundle is served.
- `lib/my_food_back_web/controllers/page_controller.ex`
- `lib/my_food_back_web/controllers/page_html.ex`
- `lib/my_food_back_web/controllers/page_html/home.html.heex`
- `lib/my_food_back_web/components/core_components.ex`
- `lib/my_food_back_web/components/layouts.ex`
- `lib/my_food_back_web/components/layouts/root.html.heex`
- `lib/my_food_back_web/controllers/error_html.ex`
- `priv/static/assets` generated assets if present; current `priv/static` contains only `favicon.ico`, `images/logo.svg`, `robots.txt`.
- `priv/static/images/logo.svg`, `priv/static/favicon.ico`, `priv/static/robots.txt` if no static serving is needed.
- `test/my_food_back_web/controllers/page_controller_test.exs`
- `test/my_food_back_web/controllers/error_html_test.exs`

## Files likely to modify

- `mix.exs`: remove frontend deps, `compilers: [:phoenix_live_view] ++ Mix.compilers()`, asset aliases, maybe `listeners: [Phoenix.CodeReloader]` if no live reload; keep `precommit` but update if assets aliases are removed.
- `config/config.exs`: remove esbuild/tailwind config; change endpoint `render_errors` formats to JSON-only; remove `live_view` config if LiveView removed.
- `config/dev.exs`: remove watchers and live_reload config; consider removing `dev_routes` if dashboard/mailbox removed; align DB credentials with local PostgreSQL.
- `config/test.exs`: fix username/password for local PostgreSQL; consider environment variables for credentials.
- `config/prod.exs`: remove `cache_static_manifest` if no static assets/digest; reassess `assets.deploy` alias dependency.
- `lib/my_food_back_web/router.ex`: remove `:browser` pipeline and root page route; keep `:api`; add API routes.
- `lib/my_food_back_web/endpoint.ex`: remove LiveView socket, static plug, session plug, live reload, request logger/dashboard coupling as appropriate.
- `lib/my_food_back_web.ex`: remove HTML/LiveView helpers/macros and reduce controller formats to JSON only.
- `test/support/conn_case.ex`: still useful for API controller tests; no HTML-specific assertions needed.
- `test/my_food_back_web/controllers/error_json_test.exs`: keep/update for JSON error shape.

## Router/pipelines/controllers/templates/assets summary

- Router currently has both `:browser` and `:api` pipelines, but only `/` browser route is active. API scope is commented out.
- Controllers currently active: `PageController` (HTML) and error renderers (`ErrorHTML`, `ErrorJSON`).
- Templates/layouts: generated home HEEx, root layout HEEx, component layout module, core components.
- Assets: full generated Phoenix asset stack with Tailwind v4, daisyUI vendor plugins, heroicons, LiveView JS, topbar.
- Dev-only UI routes: LiveDashboard and Swoosh mailbox under `/dev`, behind `:browser` pipeline and `Application.compile_env(:my_food_back, :dev_routes)`.

## Phoenix 1.8 gotchas

- Phoenix 1.8 generated HTML uses `Layouts` and `<Layouts.flash_group>`; if deleting HTML, remove both layout modules and config references together.
- Do not leave `put_root_layout`, `fetch_live_flash`, or `Phoenix.LiveView.Router` imports if browser/LiveView is gone.
- If LiveView is removed, remove `compilers: [:phoenix_live_view] ++ Mix.compilers()` and LiveView socket/config; otherwise compilation may reference removed deps/modules.
- If assets are removed, update `setup`, `assets.build`, `assets.deploy`, `prod.exs cache_static_manifest`, and endpoint `Plug.Static` consistently.
- If dev dashboard/mailbox are kept, browser pipeline/session/layout support remains necessary. A truly API-only backend should remove those routes or replace with minimal non-HTML health/debug endpoints.
- `mix precommit` currently runs `test`, and `test` alias creates/migrates the test DB. Bad test DB credentials will fail before tests run.
- Tailwind v4 import syntax in `assets/css/app.css` is correct for Phoenix 1.8; only relevant if assets are retained.

## Start Here

Open `lib/my_food_back_web/router.ex` first. It shows that the app currently serves only the generated HTML home page and has no active API routes. From there, update `endpoint.ex`, `my_food_back_web.ex`, and `mix.exs` together so deleted frontend pieces do not leave dangling references.

## Supervisor coordination

No supervisor decision was needed. Engram save was requested, but no callable Engram/memory tool is available in this subagent toolset, so no memory write could be performed.
