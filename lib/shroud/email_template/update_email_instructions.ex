defmodule Shroud.EmailTemplate.UpdateEmailInstructions do
  @template_path Path.join([__DIR__, "update_email_instructions.mjml"])
  @external_resource @template_path

  require EEx
  alias Shroud.Mailer

  rendered_mjml = Mailer.generate_template(@template_path)
  EEx.function_from_string(:def, :render, rendered_mjml, [:assigns])
end