# 🥸 Alias

Alias is an email privacy service.

# To do

- [ ] Handle emails with multiple recipients
- [ ] Handle attachments
- [ ] Limit number of aliases (5?)
- [ ] Custom aliases (pro)
- [ ] Simple spam checks before forwarding?
- [ ] Remove trackers

## Contributing

To start your Phoenix server:

  * Install dependencies with `mix deps.get`
  * Create and migrate your database with `mix ecto.setup`
  * Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

To send test emails, use e.g. [Swaks](https://www.jetmore.org/john/code/swaks/):
```
swaks --to test@example.com --server 127.0.0.1 --port 2525
```

## Useful links

- http://reganmian.net/blog/2015/09/03/sending-and-receiving-email-with-elixir/
