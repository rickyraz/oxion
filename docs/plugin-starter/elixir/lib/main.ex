defmodule Main do
  @moduledoc false

  # Elixir starter plugin untuk hook pre_authorize.
  # Mengizinkan auth hanya pada jam UTC yang ada di config.
  def pre_authorize(input) do
    allowed_hours = get_in(input, ["config", "allowed_hours_utc"]) || []
    timestamp = get_in(input, ["request", "timestamp_utc"]) || DateTime.utc_now() |> DateTime.to_iso8601()

    case DateTime.from_iso8601(timestamp) do
      {:ok, dt, _offset} ->
        hour = dt.hour

        if hour in allowed_hours do
          %{"decision" => "allow", "reason" => "within_allowed_hours"}
        else
          %{"decision" => "deny", "reason" => "outside_allowed_hours"}
        end

      {:error, _reason} ->
        %{"decision" => "deny", "reason" => "invalid_timestamp"}
    end
  end
end
