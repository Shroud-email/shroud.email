defmodule Shroud.Email.SpamEmailScrubberTest do
  use ExUnit.Case, async: true

  alias Shroud.Email.SpamEmailScrubber

  describe "scrub/1" do
    test "strips XML processing instructions without crashing" do
      # Real-world spam email containing an `<?xml:namespace ...?>` processing
      # instruction. Previously this raised FunctionClauseError because the
      # generated catch-all only matched binary tag names, not the `:pi` atom.
      html =
        ~S(<html><body><p>hi</p><?xml:namespace prefix="o" ns="urn:schemas-microsoft-com:office:office"?></body></html>)

      assert HtmlSanitizeEx.Scrubber.scrub(html, SpamEmailScrubber) == "<p>hi</p>"
    end

    test "preserves allowed tags" do
      assert HtmlSanitizeEx.Scrubber.scrub(~S(<p>hello <b>world</b></p>), SpamEmailScrubber) ==
               "<p>hello <b>world</b></p>"
    end
  end
end
