[
  import_deps: [:ecto, :phoenix],
  plugins: [Phoenix.LiveView.HTMLFormatter],
  inputs: [
    "*.{ex,exs,heex}",
    "priv/*/seeds.exs",
    "{config,lib,test,rel,scripts}/**/*.{ex,exs,heex}"
  ],
  subdirectories: ["priv/*/migrations"]
]
