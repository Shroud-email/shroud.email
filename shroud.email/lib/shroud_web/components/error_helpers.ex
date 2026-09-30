defmodule ShroudWeb.ErrorHelpers do
  @moduledoc """
  Conveniences for translating and building error messages.
  """

  use PhoenixHTMLHelpers

  @doc """
  Generates tag for inlined form input errors.
  """
  def error_tag(form, field) do
    Enum.map(Keyword.get_values(form.errors, field), fn error ->
      content_tag(:span, translate_error(error), class: "invalid-feedback")
    end)
  end

  @doc """
  Translates an error message using gettext.
  """
  def translate_error({msg, opts}) do
    if count = opts[:count] do
      Gettext.dngettext(ShroudWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(ShroudWeb.Gettext, "errors", msg, opts)
    end
  end
end
