defmodule MainTest do
  use ExUnit.Case, async: true

  test "denies when hour outside allowlist" do
    result =
      Main.pre_authorize(%{
        "request" => %{"timestamp_utc" => "2026-01-01T03:00:00Z"},
        "config" => %{"allowed_hours_utc" => [9, 10, 11]}
      })

    assert result["decision"] == "deny"
    assert result["reason"] == "outside_allowed_hours"
  end
end
