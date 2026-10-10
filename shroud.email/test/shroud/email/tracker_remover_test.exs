defmodule Shroud.Email.TrackerRemoverTest do
  use Shroud.DataCase, async: true
  alias Shroud.Repo
  alias Shroud.Email.{Enricher, ParsedEmail, TrackerDomain, TrackerRemover}

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
      assert email.removed_trackers == [%{name: "SpyOnU", domain: "spyonu.com"}]
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
      assert Enum.member?(email.removed_trackers, %{name: nil, domain: "unknowntracker.com"})
      assert Enum.member?(email.removed_trackers, %{name: nil, domain: "tracker2.com"})
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
      assert hd(email.removed_trackers) == %{name: nil, domain: "unknowntracker.com"}
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
      assert email.removed_trackers == [%{name: "SpyOnU", domain: "spyonu.com"}]
    end

    test "deduplicates repeated trackers" do
      html_body = """
      <html>
        <body>
          <h1>An email</h1>
          <img src="https://spyonu.com/track?q=123" />
          <img src="https://spyonu.com/track?q=456" />
          <img src="https://unknowntracker.com" width="1" height="1" />
          <img src="https://unknowntracker.com" width="1" height="1" />
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

      assert email.removed_trackers == [
               %{name: "SpyOnU", domain: "spyonu.com"},
               %{name: nil, domain: "unknowntracker.com"}
             ]
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

  test "removes tracker references without removing surrounding content or safe alternatives" do
    html = ~S"""
    <style>
      .hero { background: url(https://spyonu.com/track?css), url(https://gooddomain.com/bg); color: red; }
      .retina { background-image: image-set("https://spyonu.com/track?set" 1x, "https://gooddomain.com/retina" 2x); }
      .embedded { background: url('data:image/png;base64,abc'); }
    </style>
    <table background="https://spyonu.com/track?legacy"><tr><td style="background: url(https://spyonu.com/track?inline); color: blue">Keep me</td></tr></table>
    <picture><source srcset="https://spyonu.com/track?source 400w, https://gooddomain.com/wide 800w"><img src="https://spyonu.com/track?src" srcset="https://gooddomain.com/normal 1x, https://spyonu.com/track?srcset 2x"></picture>
    <svg><image href="https://spyonu.com/track?svg"/><image xlink:href="https://gooddomain.com/svg"/></svg>
    <!--[if mso]><v:rect><v:fill src="https://spyonu.com/track?vml"/></v:rect><img src="https://unknowntracker.com/pixel" width="1" height="2"><v:imagedata src="https://gooddomain.com/outlook"/><![endif]-->
    <img srcset="https://unknowntracker.com/a 1x, https://unknowntracker.com/b 2x" width="2" height="1">
    <img src="data:image/png;base64,abc" width="1" height="1">
    <a href="https://spyonu.com/track?link">Keep this link</a>
    """

    email = process_html(html)
    result = email.swoosh_email.html_body

    assert email.removed_trackers == [
             %{name: "SpyOnU", domain: "spyonu.com"},
             %{name: nil, domain: "unknowntracker.com"}
           ]

    assert Floki.attribute(email.parsed_html, "a", "href") == ["https://spyonu.com/track?link"]
    assert Floki.attribute(email.parsed_html, "table", "background") == []
    assert Floki.text(Floki.find(email.parsed_html, "td")) == "Keep me"
    assert Floki.attribute(email.parsed_html, "img", "src") == ["data:image/png;base64,abc"]

    assert Floki.attribute(email.parsed_html, "img", "srcset") == [
             proxy("https://gooddomain.com/normal") <> " 1x"
           ]

    assert Floki.attribute(email.parsed_html, "source", "srcset") == [
             proxy("https://gooddomain.com/wide") <> " 800w"
           ]

    assert result =~ "<!--[if mso]>"
    assert result =~ "<![endif]-->"
    refute result =~ "unknowntracker.com"

    for suffix <- ["css", "set", "legacy", "inline", "source", "src", "srcset", "svg", "vml"] do
      refute result =~ "track?#{suffix}"
    end

    for suffix <- ["bg", "retina", "svg", "outlook"] do
      assert result =~ proxy("https://gooddomain.com/#{suffix}")
    end

    assert Floki.attribute(email.parsed_html, "td", "style") == ["background: none; color: blue"]
    assert result =~ "background: url('data:image/png;base64,abc')"
  end

  test "handles escaped CSS tracker URLs and punctuation inside quoted URLs" do
    email =
      process_html(~S"""
      <div id="blocked" style='back\67round-image: u\72l("https://spy\6fnu.com/track?x=1"); color: red'>Keep</div>
      <div id="safe" style='background-image: url("https://gooddomain.com/a)b?x=1&amp;y=2")'>Keep</div>
      """)

    assert email.removed_trackers == [%{name: "SpyOnU", domain: "spyonu.com"}]

    assert Floki.attribute(email.parsed_html, "#blocked", "style") == [
             ~S(back\67round-image: none; color: red)
           ]

    assert Floki.attribute(email.parsed_html, "#safe", "style") == [
             "background-image: url(\"#{proxy("https://gooddomain.com/a)b?x=1&y=2")}\")"
           ]
  end

  defp proxy(source),
    do: "http://localhost:4002/proxy?url=" <> URI.encode_www_form(URI.encode(source))

  test "discards all privacy edits and branding if any CSS input fails to parse" do
    for broken <- [
          ~s|<div style="background: url(https://spyonu.com/track">Keep</div>|,
          ~s|<style>.hero { background: url("https://spyonu.com/track");</style>|,
          ~s|<!--[if mso]><div style="background: url(">Keep</div><![endif]-->|,
          ~s(<style>/* unterminated comment</style>),
          ~S|<div style='background: url(https://gooddomain.com/a b)'>Keep</div>|,
          ~S|<div style='background: url("https://gooddomain.com/a\")'>Keep</div>|,
          ~S|<style>.hero { background: url(https://gooddomain.com/a\)</style>|
        ] do
      html =
        ~s(<img src="https://spyonu.com/track"><img src="https://gooddomain.com/photo">) <> broken

      original =
        html_email("sender@example.com", ["recipient@example.com"], "Subject", html)
        |> :mimemail.decode()
        |> ParsedEmail.parse("sender@example.com", "recipient@example.com")

      processed = original |> TrackerRemover.process() |> Enricher.process()

      assert processed.privacy_processing_failed
      assert processed.swoosh_email == original.swoosh_email
      assert processed.parsed_html == original.parsed_html
      assert processed.removed_trackers == []
      assert processed.image_urls == []
    end
  end

  test "rewrites only image spans in nested CSS with UTF-8, BOM, CRLF and escaped tokens" do
    css =
      "\uFEFF/* café */\r\n@media screen {\r\n.hero { " <>
        ~S|back\67round: image-set("https://gooddomain.com/caf\e9.png" 1x type("image/png"), url("https://spyonu.com/track") 2x); | <>
        ~S|content: "url(https://spyonu.com/track)"; color: red; } | <>
        ~S|.embedded { background: url('data:image/svg+xml,<svg>(é)</svg>'); } | <>
        ~S|@font-face { src: url(https://gooddomain.com/font); }| <> "\r\n}"

    original = %ParsedEmail{
      parsed_html: [{"style", [], [css]}],
      swoosh_email: Swoosh.Email.new() |> Swoosh.Email.html_body("<style>#{css}</style>")
    }

    processed = TrackerRemover.process(original)

    expected =
      css
      |> String.replace(
        ~S("https://gooddomain.com/caf\e9.png"),
        ~s|url("#{proxy("https://gooddomain.com/café.png")}")|
      )
      |> String.replace(~s|url("https://spyonu.com/track")|, ~s|url("data:,")|)

    refute processed.privacy_processing_failed
    assert processed.parsed_html == [{"style", [], [expected]}]
    assert processed.removed_trackers == [%{name: "SpyOnU", domain: "spyonu.com"}]
  end

  test "fails open for decoding errors, excessive nesting and oversized input" do
    for css <- [
          <<255>>,
          "width: " <> String.duplicate("calc(", 130) <> "1" <> String.duplicate(")", 130),
          String.duplicate(" ", 1_048_577)
        ] do
      original = %ParsedEmail{
        parsed_html: [{"div", [{"style", css}], []}],
        swoosh_email: Swoosh.Email.new() |> Swoosh.Email.html_body("<div style='#{css}'></div>")
      }

      processed = TrackerRemover.process(original)
      assert processed.privacy_processing_failed
      assert processed.swoosh_email == original.swoosh_email
      assert processed.parsed_html == original.parsed_html
    end
  end

  test "preserves long flat expressions without treating them as excessive nesting" do
    expression = "calc(" <> String.duplicate("1px + ", 15_000) <> "1px)"
    css = "width: #{expression}; background: url(https://gooddomain.com/photo)"

    original = %ParsedEmail{
      parsed_html: [{"div", [{"style", css}], []}],
      swoosh_email: Swoosh.Email.new() |> Swoosh.Email.html_body("<div></div>")
    }

    processed = TrackerRemover.process(original)
    refute processed.privacy_processing_failed

    assert Floki.attribute(processed.parsed_html, "div", "style") == [
             "width: #{expression}; background: url(\"#{proxy("https://gooddomain.com/photo")}\")"
           ]

    assert processed.image_urls == ["https://gooddomain.com/photo"]
  end

  test "blocks browser-loadable tracker URLs and preserves the destination of safe encoded URLs" do
    html = ~S"""
    <img src="https://spyonu.com/track?name=hello world">
    <img src="https://spyonu.com/track?name=é">
    <div style='background-image: url("https://spyonu.com/track?items[]=1")'>Keep</div>
    <img id="safe" src="https://gooddomain.com/a%20b?name=é&amp;items[]=hello world">
    """

    email =
      TrackerRemover.process(%ParsedEmail{
        parsed_html: Floki.parse_document!(html),
        swoosh_email: Swoosh.Email.new()
      })

    assert email.removed_trackers == [%{name: "SpyOnU", domain: "spyonu.com"}]
    assert length(Floki.find(email.parsed_html, "img")) == 1
    assert Floki.attribute(email.parsed_html, "div", "style") == ["background-image: none"]
    [source] = Floki.attribute(email.parsed_html, "#safe", "src")

    assert URI.decode_query(URI.parse(source).query)["url"] ==
             "https://gooddomain.com/a%20b?name=%C3%A9&items%5B%5D=hello%20world"
  end

  test "retains the rendering img when a picture has a safe source and a blocked fallback" do
    email =
      process_html("""
      <picture><source srcset="https://gooddomain.com/wide.jpg 800w">
      <img src="https://spyonu.com/track" alt="Product" width="320" height="180"></picture>
      """)

    assert Floki.attribute(email.parsed_html, "picture source", "srcset") == [
             proxy("https://gooddomain.com/wide.jpg") <> " 800w"
           ]

    assert [{"img", attrs, []}] = Floki.find(email.parsed_html, "picture img")
    assert attrs == [{"alt", "Product"}, {"width", "320"}, {"height", "180"}]
    assert email.removed_trackers == [%{name: "SpyOnU", domain: "spyonu.com"}]
  end

  test "preserves split Outlook table and VML wrappers while rewriting only image references" do
    open = ~S([if mso]><TABLE role='presentation'><tr><td width="600"><![endif])

    vml =
      ~S([if gte mso 9]><v:rect style='width:600px;height:200px' fill="true"><v:fill src='https://gooddomain.com/outlook?x=1&amp;y=2' type="tile" /><v:textbox inset="0,0,0,0"><![endif])

    close = ~S([if gte mso 9]></v:textbox></v:rect><![endif])
    table_close = ~S([if mso]></td></tr></TABLE><![endif])
    html = "<!--#{open}--><!--#{vml}--><p>Keep me</p><!--#{close}--><!--#{table_close}-->"
    email = process_html(html)
    comments = for {:comment, text} <- email.parsed_html, do: text

    expected_vml =
      String.replace(
        vml,
        "https://gooddomain.com/outlook?x=1&amp;y=2",
        proxy("https://gooddomain.com/outlook?x=1&y=2")
      )

    assert comments == [open, expected_vml, close, table_close]
    assert Floki.text(Floki.find(email.parsed_html, "p")) == "Keep me"
    assert email.removed_trackers == []
  end

  test "blocks poster and mask trackers while preserving video content and safe images" do
    email =
      process_html("""
      <video id="safe" width="1" height="1" src="https://spyonu.com/track?movie" poster="https://gooddomain.com/poster">Fallback</video>
      <video id="blocked" poster="https://spyonu.com/track?poster">Keep</video>
      <video id="embedded" poster="data:image/png;base64,abc"></video>
      """)

    assert Floki.attribute(email.parsed_html, "#safe", "poster") == [
             proxy("https://gooddomain.com/poster")
           ]

    assert Floki.attribute(email.parsed_html, "#safe", "src") == [
             "https://spyonu.com/track?movie"
           ]

    assert Floki.attribute(email.parsed_html, "#blocked", "poster") == []
    assert Floki.text(Floki.find(email.parsed_html, "#blocked")) == "Keep"

    assert Floki.attribute(email.parsed_html, "#embedded", "poster") == [
             "data:image/png;base64,abc"
           ]

    assert email.removed_trackers == [%{name: "SpyOnU", domain: "spyonu.com"}]

    for property <- [
          "mask-border",
          "mask-border-source",
          "-webkit-mask-box-image",
          "-webkit-mask-box-image-source"
        ] do
      email =
        process_html("""
        <style>.blocked { #{property}: url(https://spyonu.com/track); color: red; }</style>
        <div style="#{property}: url(https://gooddomain.com/mask); color: blue">Keep</div>
        """)

      assert Floki.text(Floki.find(email.parsed_html, "style")) ==
               ".blocked { #{property}: none; color: red; }"

      assert Floki.attribute(email.parsed_html, "div", "style") == [
               "#{property}: url(\"#{proxy("https://gooddomain.com/mask")}\"); color: blue"
             ]

      assert Floki.text(Floki.find(email.parsed_html, "div")) == "Keep"
      assert email.removed_trackers == [%{name: "SpyOnU", domain: "spyonu.com"}]
    end
  end

  test "keeps url candidates valid inside image-set and leaves surrounding CSS unchanged" do
    email =
      process_html(~S"""
      <div style='background-image: image-set(url("https://spyonu.com/track") 1x, url("https://gooddomain.com/retina") 2x); color: red'></div>
      """)

    assert Floki.attribute(email.parsed_html, "div", "style") == [
             ~s|background-image: image-set(url("data:,") 1x, url("#{proxy("https://gooddomain.com/retina")}") 2x); color: red|
           ]

    assert email.removed_trackers == [%{name: "SpyOnU", domain: "spyonu.com"}]
  end

  test "preserves conditional text, quoting, office markup and styles outside image references" do
    comment = ~S"""
    [if mso]><o:OfficeDocumentSettings><o:PixelsPerInch>96</o:PixelsPerInch></o:OfficeDocumentSettings>
    <TABLE role='presentation' title="A > B" cellpadding=0><tr><td>
    <style>.hero { background: url('https://spyonu.com/track'); color: red; } .text::after { content: "<img src='https://spyonu.com/track'>"; }</style>
    <v:fill SRC = https://gooddomain.com/photo TYPE='tile' />
    <div style="color: blue; background: url(https://spyonu.com/track)">Keep <b>formatting</b></div>
    <a href='https://spyonu.com/track' title='a src="https://spyonu.com/track"'>Keep this link</a>
    <textarea><img src='https://spyonu.com/track'></textarea>
    <picture><source srcset='https://gooddomain.com/wide.jpg 800w'><img src='cid:photo'></picture>
    <video><source srcset='https://spyonu.com/track 1x'></video>
    </td></tr></TABLE><![endif]
    """

    comment = String.trim(comment)
    email = process_html("<!--#{comment}-->")

    expected =
      comment
      |> Shroud.Util.lf_to_crlf()
      |> String.replace("background: url('https://spyonu.com/track')", "background: none")
      |> String.replace("background: url(https://spyonu.com/track)", "background: none")
      |> String.replace(
        "SRC = https://gooddomain.com/photo",
        "SRC = \"#{proxy("https://gooddomain.com/photo")}\""
      )
      |> String.replace(
        "srcset='https://gooddomain.com/wide.jpg 800w'",
        "srcset='#{proxy("https://gooddomain.com/wide.jpg")} 800w'"
      )

    assert email.parsed_html == [{:comment, expected}]
    assert email.removed_trackers == [%{name: "SpyOnU", domain: "spyonu.com"}]
  end

  describe "blocked domain tracking" do
    test "carries both the friendly name and the real domain for known trackers" do
      html_body = """
      <html><body>
        <img src="https://spyonu.com/track?q=123" />
      </body></html>
      """

      email = process_html(html_body)

      # A single entry holds the friendly name (for the report) and the real
      # host (for persistence).
      assert email.removed_trackers == [%{name: "SpyOnU", domain: "spyonu.com"}]
    end

    test "records hosts for unknown tracking pixels" do
      html_body = """
      <html><body>
        <img src="https://unknowntracker.com" width="1" height="1" />
        <img src="https://tracker2.com" width="2" height="2" />
      </body></html>
      """

      email = process_html(html_body)

      assert Enum.sort(domains(email)) == ["tracker2.com", "unknowntracker.com"]
    end

    test "deduplicates domains within a single email" do
      html_body = """
      <html><body>
        <img src="https://spyonu.com/track?q=123" />
        <img src="https://spyonu.com/track?q=456" />
        <img src="https://unknowntracker.com" width="1" height="1" />
        <img src="https://unknowntracker.com" width="1" height="1" />
      </body></html>
      """

      email = process_html(html_body)

      assert Enum.sort(domains(email)) == ["spyonu.com", "unknowntracker.com"]
    end

    test "is empty when no trackers are found" do
      html_body = """
      <html><body>
        <img src="https://gooddomain.com/abc.jpg" alt="an image" />
      </body></html>
      """

      email = process_html(html_body)

      assert email.removed_trackers == []
    end

    test "does not persist counts itself (recording is the caller's job, post-delivery)" do
      # process/1 is a pure transform. Persistence happens only once the email is
      # successfully forwarded, so that re-running the pipeline on an Oban retry
      # can't inflate the counts.
      html_body = """
      <html><body>
        <img src="https://spyonu.com/track?q=123" />
        <img src="https://unknowntracker.com" width="1" height="1" />
      </body></html>
      """

      process_html(html_body)

      assert Repo.aggregate(TrackerDomain, :count) == 0
    end
  end

  defp process_html(html_body) do
    html_email("sender@example.com", ["recipient@example.com"], "Subject", html_body)
    |> :mimemail.decode()
    |> ParsedEmail.parse("sender@example.com", "recipient@example.com")
    |> TrackerRemover.process()
  end

  defp domains(email) do
    email.removed_trackers
    |> Enum.map(& &1.domain)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp remove_whitespace(text), do: String.replace(text, ~r/\s/, "")
end
