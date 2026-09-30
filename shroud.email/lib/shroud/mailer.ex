defmodule Shroud.Mailer do
  use Swoosh.Mailer, otp_app: :shroud

  def generate_template(file_path) do
    {:ok, template} =
      file_path
      |> File.read!()
      |> Mjml.to_html()

    # MJML doesn't like <%= EEx templates %>, so we use
    # {{ liquid templates }} in mjml and then regex-replace
    # that into the EEx format here.
    ~r/{{\s*([^}^\s]+)\s*}}/
    |> Regex.replace(template, fn _, variable_name ->
      "<%= @#{variable_name} %>"
    end)
  end
end
