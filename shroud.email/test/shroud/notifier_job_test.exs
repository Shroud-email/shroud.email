defmodule Shroud.NotifierJobTest do
  use Shroud.DataCase, async: false
  use Oban.Testing, repo: Shroud.Repo
  import Mox
  alias Shroud.NotifierJob

  setup :verify_on_exit!

  setup do
    url = Application.fetch_env!(:shroud, :notifier_webhook_url)
    on_exit(fn -> Application.put_env(:shroud, :notifier_webhook_url, url) end)
  end

  describe "perform/1" do
    test "completes queued jobs without HTTP requests when the webhook is disabled" do
      expect(Shroud.MockHTTPoison, :post, 0, fn _, _, _ -> :ok end)

      for url <- [nil, ""] do
        Application.put_env(:shroud, :notifier_webhook_url, url)
        assert :ok = perform_job(NotifierJob, %{payload: %{content: "Lorem ipsum!"}})
      end

      Application.delete_env(:shroud, :notifier_webhook_url)
      assert :ok = perform_job(NotifierJob, %{payload: %{content: "Lorem ipsum!"}})
    end

    test "sends a webhook with the content field" do
      Shroud.MockHTTPoison
      |> expect(:post, fn url, payload, headers ->
        assert url == "webhook.com/webhook"
        assert payload == "{\"content\":\"Lorem ipsum!\"}"
        assert headers == ["Content-Type": "application/json"]
        {:ok, %HTTPoison.Response{status_code: 200}}
      end)

      perform_job(NotifierJob, %{payload: %{content: "Lorem ipsum!"}})
    end

    test "preserves HTTP errors so Oban can retry configured webhooks" do
      error = %HTTPoison.Error{reason: :timeout}
      expect(Shroud.MockHTTPoison, :post, fn _, _, _ -> {:error, error} end)

      assert {:error, ^error} =
               perform_job(NotifierJob, %{payload: %{content: "Lorem ipsum!"}})
    end
  end
end
