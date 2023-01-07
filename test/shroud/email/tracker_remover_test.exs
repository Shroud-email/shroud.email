defmodule Shroud.Email.TrackerRemoverTest do
  use Shroud.DataCase, async: true
  alias Shroud.Email.{ParsedEmail, TrackerRemover}

  import Shroud.{EmailFixtures, TrackerFixtures}

  setup do
    tracker =
      tracker_fixture(%{
        name: "SpyOnU",
        pattern: "spyonu\.com\/track"
      })

    {:ok, tracker: tracker}
  end

  describe "perform/1" do
    test "removes tracking images" do
      html_body = """
      <html>
        <body>
          <h1>An email</h1>
          <img src="https://spyonu.com/track?q=123" />
          <p>Content</p>
        </body>
      </html>
      """

      expected_result = """
      <html>
        <body>
          <h1>An email</h1>
          <p>Content</p>
        </body>
      </html>
      """

      email =
        html_email("sender@example.com", ["recipient@example.com"], "Subject", html_body)
        |> :mimemail.decode()
        |> ParsedEmail.parse("sender@example.com", "recipient@example.com")
        |> TrackerRemover.process()

      assert remove_whitespace(email.swoosh_email.html_body) == remove_whitespace(expected_result)
      assert Enum.empty?(Floki.find(email.parsed_html, "img"))
      assert email.removed_trackers == ["SpyOnU"]
    end

    test "removes 1x1 (and 2x2) images" do
      html_body = """
      <html>
        <body>
          <h1>An email</h1>
          <img src="https://unknowntracker.com" width="1" height="1" />
          <img src="https://tracker2.com" width="2" height="2" />
          <img src="https://gooddomain.com" width="500" height="1" />
          <p>Content</p>
        </body>
      </html>
      """

      expected_result = """
      <html>
        <body>
          <h1>An email</h1>
          <img src="http://localhost:4002/proxy?url=https%3A%2F%2Fgooddomain.com" width="500" height="1" />
          <p>Content</p>
        </body>
      </html>
      """

      email =
        html_email("sender@example.com", ["recipient@example.com"], "Subject", html_body)
        |> :mimemail.decode()
        |> ParsedEmail.parse("sender@example.com", "recipient@example.com")
        |> TrackerRemover.process()

      assert remove_whitespace(email.swoosh_email.html_body) == remove_whitespace(expected_result)
      assert length(Floki.find(email.parsed_html, "img")) == 1
      assert length(email.removed_trackers) == 2
      assert Enum.member?(email.removed_trackers, "unknowntracker.com")
      assert Enum.member?(email.removed_trackers, "tracker2.com")
    end

    test "removes 1x1 images with 'px' in height" do
      html_body = """
      <html>
        <body>
          <h1>An email</h1>
          <img src="https://unknowntracker.com" width="1px" height="1px" />
          <img src="https://gooddomain.com" width="500" height="1" />
          <p>Content</p>
        </body>
      </html>
      """

      expected_result = """
      <html>
        <body>
          <h1>An email</h1>
          <img src="http://localhost:4002/proxy?url=https%3A%2F%2Fgooddomain.com" width="500" height="1" />
          <p>Content</p>
        </body>
      </html>
      """

      email =
        html_email("sender@example.com", ["recipient@example.com"], "Subject", html_body)
        |> :mimemail.decode()
        |> ParsedEmail.parse("sender@example.com", "recipient@example.com")
        |> TrackerRemover.process()

      assert remove_whitespace(email.swoosh_email.html_body) == remove_whitespace(expected_result)
      assert length(Floki.find(email.parsed_html, "img")) == 1
      assert length(email.removed_trackers) == 1
      assert hd(email.removed_trackers) == "unknowntracker.com"
    end

    test "doesn't double-count 1x1 images from known trackers" do
      html_body = """
      <html>
        <body>
          <h1>An email</h1>
          <img src="https://spyonu.com/track?q=123" width="1" height="1" />
          <p>Content</p>
        </body>
      </html>
      """

      expected_result = """
      <html>
        <body>
          <h1>An email</h1>
          <p>Content</p>
        </body>
      </html>
      """

      email =
        html_email("sender@example.com", ["recipient@example.com"], "Subject", html_body)
        |> :mimemail.decode()
        |> ParsedEmail.parse("sender@example.com", "recipient@example.com")
        |> TrackerRemover.process()

      assert remove_whitespace(email.swoosh_email.html_body) == remove_whitespace(expected_result)
      assert Floki.find(email.parsed_html, "img") |> Enum.empty?()
      assert email.removed_trackers == ["SpyOnU"]
    end

    test "proxies non-tracker images" do
      html_body = """
      <html>
        <body>
          <h1>An email</h1>
          <img src="https://gooddomain.com/abc.jpg" alt="an image" />
          <p>Content</p>
        </body>
      </html>
      """

      expected_result = """
      <html>
        <body>
          <h1>An email</h1>
          <img src="http://localhost:4002/proxy?url=https%3A%2F%2Fgooddomain.com%2Fabc.jpg" alt="an image" />
          <p>Content</p>
        </body>
      </html>
      """

      email =
        html_email("sender@example.com", ["recipient@example.com"], "Subject", html_body)
        |> :mimemail.decode()
        |> ParsedEmail.parse("sender@example.com", "recipient@example.com")
        |> TrackerRemover.process()

      assert remove_whitespace(email.swoosh_email.html_body) == remove_whitespace(expected_result)
      assert length(Floki.find(email.parsed_html, "img")) == 1
      assert Enum.empty?(email.removed_trackers)
    end

    test "does not proxy non-image links" do
      html_body = """
      <html>
        <body>
          <h1>An email</h1>
          <p>Content</p>
          <a href="https://example.com/myfile.pdf">Download</a>
        </body>
      </html>
      """

      email =
        html_email("sender@example.com", ["recipient@example.com"], "Subject", html_body)
        |> :mimemail.decode()
        |> ParsedEmail.parse("sender@example.com", "recipient@example.com")
        |> TrackerRemover.process()

      assert remove_whitespace(email.swoosh_email.html_body) == remove_whitespace(html_body)
      assert Enum.empty?(email.removed_trackers)
    end

    test "does not proxy inline attachments" do
      html_body = """
      <html>
        <body>
          <h1>An email</h1>
          <p>Content</p>
          <img src="cid:8dcb16bc583c913c3d5ee7cab14e400c" alt="an image" />
        </body>
      </html>
      """

      email =
        html_email("sender@example.com", ["recipient@example.com"], "Subject", html_body)
        |> :mimemail.decode()
        |> ParsedEmail.parse("sender@example.com", "recipient@example.com")
        |> TrackerRemover.process()

      assert remove_whitespace(email.swoosh_email.html_body) == remove_whitespace(html_body)
      assert Enum.empty?(email.removed_trackers)
    end

    test "does not proxy inline images" do
      html_body = """
      <html>
        <body>
          <h1>An email</h1>
          <p>Content</p>
          <img src="data:image/png;base64, deadbeef" alt="an image" />
        </body>
      </html>
      """

      email =
        html_email("sender@example.com", ["recipient@example.com"], "Subject", html_body)
        |> :mimemail.decode()
        |> ParsedEmail.parse("sender@example.com", "recipient@example.com")
        |> TrackerRemover.process()

      assert remove_whitespace(email.swoosh_email.html_body) == remove_whitespace(html_body)
      assert Enum.empty?(email.removed_trackers)
    end
  end

  defp remove_whitespace(text), do: String.replace(text, ~r/\s/, "")
end
