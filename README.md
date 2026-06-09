# MyFoodBack

To start your Phoenix server:

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

## Verify email-code delivery locally

Development uses `Swoosh.Adapters.Local`, so no external email provider or paid sandbox is required.

1. Start the backend with `mix phx.server`.
2. Request a code:

   ```sh
   curl -X POST http://localhost:4000/api/auth/signup/request-code \
     -H 'content-type: application/json' \
     -d '{"email":"local-test@example.com"}'
   ```

3. Open [`localhost:4000/dev/mailbox`](http://localhost:4000/dev/mailbox) and read the latest email.

For SMTP-backed delivery, set these runtime environment variables before starting the app:

- `SMTP_RELAY`
- `SMTP_USERNAME`
- `SMTP_PASSWORD`
- `SMTP_FROM_ADDRESS`
- optional: `SMTP_FROM_NAME`, `SMTP_PORT`, `SMTP_TLS`, `SMTP_SSL`

Do not commit real SMTP credentials.

Ready to run in production? Please [check our deployment guides](https://hexdocs.pm/phoenix/deployment.html).

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://hexdocs.pm/phoenix/overview.html
* Docs: https://hexdocs.pm/phoenix
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix
