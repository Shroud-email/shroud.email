defmodule Shroud.Email.CSSParser do
  @moduledoc false

  def references(css, _inline) when byte_size(css) > 1_048_576,
    do: {:error, "css_too_large"}

  def references(css, inline) do
    caller = self()

    {pid, ref} =
      spawn_monitor(fn ->
        Process.flag(:trap_exit, true)
        caller_ref = Process.monitor(caller)

        result =
          try do
            run_helper(css, inline, caller_ref)
          rescue
            _ -> {:error, "helper_failed"}
          catch
            _, _ -> {:error, "helper_failed"}
          end

        exit({:css_reply, result})
      end)

    receive do
      {:DOWN, ^ref, :process, ^pid, {:css_reply, result}} -> result
      {:DOWN, ^ref, :process, ^pid, _} -> {:error, "helper_failed"}
    after
      3_200 ->
        Process.exit(pid, :kill)
        Process.demonitor(ref, [:flush])
        {:error, "helper_timeout"}
    end
  end

  defp run_helper(css, inline, caller_ref) do
    executable = Application.app_dir(:shroud, "priv/bin/css_image_parser")

    port =
      Port.open({:spawn_executable, String.to_charlist(executable)}, [
        :binary,
        :exit_status,
        :use_stdio,
        :hide,
        :stderr_to_stdout,
        args: [if(inline, do: "inline", else: "stylesheet")]
      ])

    try do
      # Length framing avoids waiting for EOF, which Erlang ports cannot send.
      deadline = System.monotonic_time(:millisecond) + 3_000
      Port.command(port, <<byte_size(css)::unsigned-big-32, css::binary>>)
      receive_reply(port, [], 0, deadline, byte_size(css), caller_ref)
    after
      if Port.info(port), do: Port.close(port)
    end
  end

  defp receive_reply(port, parts, size, deadline, css_size, caller_ref) do
    timeout = deadline - System.monotonic_time(:millisecond)

    if timeout <= 0 do
      {:error, "helper_timeout"}
    else
      receive do
        {^port, {:data, data}} when size + byte_size(data) <= 4_194_304 ->
          receive_reply(
            port,
            [data | parts],
            size + byte_size(data),
            deadline,
            css_size,
            caller_ref
          )

        {^port, {:data, _data}} ->
          {:error, "helper_output_too_large"}

        {^port, {:exit_status, 0}} ->
          parts |> Enum.reverse() |> IO.iodata_to_binary() |> decode_reply(css_size)

        {^port, {:exit_status, _status}} ->
          {:error, "helper_failed"}

        {:EXIT, ^port, _reason} ->
          {:error, "helper_failed"}

        {:DOWN, ^caller_ref, :process, _pid, _reason} ->
          {:error, "caller_stopped"}
      after
        timeout -> {:error, "helper_timeout"}
      end
    end
  end

  defp decode_reply(reply, css_size) do
    case Jason.decode(reply) do
      {:ok, %{"Ok" => references}} when is_list(references) ->
        if valid_references?(references, css_size),
          do: {:ok, references},
          else: {:error, "invalid_helper_reply"}

      {:ok, %{"Err" => reason}} ->
        {:error, reason}

      _ ->
        {:error, "invalid_helper_reply"}
    end
  end

  defp valid_references?(references, css_size) do
    Enum.reduce_while(references, 0, fn
      [start, stop, url, nested], last
      when is_integer(start) and is_integer(stop) and
             start >= last and stop > start and stop <= css_size and is_binary(url) and
             nested in [true, false] ->
        {:cont, stop}

      _, _ ->
        {:halt, :invalid}
    end) != :invalid
  end
end
