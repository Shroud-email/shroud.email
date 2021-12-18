# 🥷 Shroud

Shroud is an email privacy service. Protect your email address from spammers and creepy marketers
by creating unlimited aliases that remove trackers and forward messages to your regular inbox.

## Contributing

Shroud is built with Elixir and [Phoenix](https://www.phoenixframework.org/). Make sure you
have Elixir and mix installed.

To start the server:

  * Install dependencies with `mix deps.get`
  * Create and migrate your database with `mix ecto.setup`
  * Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

To send test emails, use e.g. [Swaks](https://www.jetmore.org/john/code/swaks/):
```
swaks --to test@example.com --server 127.0.0.1 --port 2525
```

## Libraries

- [DaisyUI](https://daisyui.com/) for basic styles
- [gen_smtp](https://github.com/gen-smtp/gen_smtp) for receiving emails
- [Swoosh](https://hexdocs.pm/swoosh/Swoosh.html) for sending emails

# Deploying

Set the following environment variables:
- `SECRET_KEY_BASE` (generate using `mix phx.gen.secret`)
- `DATABASE_URL`
- `OH_MY_SMTP_API_KEY`
- `STRIPE_SECRET`
- `STRIPE_PRICE` (the ID of the Stripe price you're using; it starts with `price_`)
- `STRIPE_WEBHOOK_SECRET`
