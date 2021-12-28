defmodule Shroud.AppsignalOban do
  alias Appsignal.Tracer
  alias Appsignal.Span

  require Logger

  @registry Appsignal.Registry

  def handle_event([:oban, :job, :start], _measurement, meta, _) do
    span =
      Tracer.create_span("background_job")
      |> Span.set_name("#{meta.worker}#perform")
      |> Span.set_sample_data("args", meta.args)

    Registry.register(@registry, {meta.id, meta.attempt}, span)
  end

  def handle_event([:oban, :job, :stop], _measurement, meta, _) do
    {meta.id, meta.attempt}
    |> get_span()
    |> Tracer.close_span()
  end

  def handle_event([:oban, :job, :exception], _measurement, meta, _) do
    error = meta.job.unsaved_error

    {meta.id, meta.attempt}
    |> get_span()
    |> Span.add_error(error.kind, error.reason, error.stacktrace)
    |> Tracer.close_span()
  end

  defp get_span(id) do
    [{_pid, span}] = Registry.lookup(@registry, id)

    :ok = Registry.unregister(@registry, id)

    span
  end
end
