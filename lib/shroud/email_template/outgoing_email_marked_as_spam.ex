defmodule Shroud.EmailTemplate.OutgoingEmailMarkedAsSpam do
  @template_path Path.join([__DIR__, "outgoing_email_marked_as_spam.mjml"])
  @external_resource @template_path

  require EEx
  alias Shroud.Mailer

  rendered_mjml = Mailer.generate_template(@template_path)
  EEx.function_from_string(:def, :render, rendered_mjml, [:assigns])
end
