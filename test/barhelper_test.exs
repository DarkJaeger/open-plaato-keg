defmodule OpenPlaatoKeg.BarHelperTest do
  use ExUnit.Case, async: true

  alias OpenPlaatoKeg.BarHelper

  # An actual BarHelper success body, including its unusual spacing.
  @success_body ~s({"volume: 15.89" "prevKegAmount": 15.87, "newKegAmount": 15.89, "success": true, "message": "Keg Monitor updated successfully"})

  describe "parse_volume/1" do
    test "parses the stringified volumes that pin 51 produces" do
      assert BarHelper.parse_volume("15.890") == {:ok, 15.89}
      assert BarHelper.parse_volume("7.900") == {:ok, 7.9}
    end

    test "parses a negative reading from an uncalibrated scale" do
      assert BarHelper.parse_volume("-4.540") == {:ok, -4.54}
    end

    test "parses a value with no decimal point" do
      assert BarHelper.parse_volume("15") == {:ok, 15.0}
    end

    test "passes numbers through as floats" do
      assert BarHelper.parse_volume(15.89) == {:ok, 15.89}
      assert BarHelper.parse_volume(15) == {:ok, 15.0}
    end

    test "rejects missing and non-numeric values" do
      assert BarHelper.parse_volume(nil) == :error
      assert BarHelper.parse_volume("") == :error
      assert BarHelper.parse_volume("abc") == :error
      assert BarHelper.parse_volume(%{}) == :error
    end
  end

  describe "classify_response/2" do
    test "recognises a successful update" do
      assert BarHelper.classify_response(200, @success_body) == :success
    end

    test "tolerates whitespace variation around the success flag" do
      assert BarHelper.classify_response(200, ~s({"success":true})) == :success
    end

    test "flags a 2xx that does not report success" do
      assert BarHelper.classify_response(200, ~s({"success": false})) == :no_success_flag
    end

    test "flags rate limiting" do
      assert BarHelper.classify_response(429, "Too many requests, max 2 per minute.") ==
               :rate_limited
    end

    test "flags an auth failure regardless of status" do
      assert BarHelper.classify_response(200, "Wrong auth token") == :auth_error
    end

    # The regression this module was fixed for: a stringified volume is answered
    # with a 500 whose body carries neither an auth hint nor a success flag.
    test "flags the 500 returned for a stringified volume" do
      assert BarHelper.classify_response(500, "Internal Server Error") == :unexpected
    end

    test "handles a body Req has decoded into a map" do
      assert BarHelper.classify_response(500, %{"error" => "boom"}) == :unexpected
      assert BarHelper.classify_response(200, %{"success" => true}) == :success
      assert BarHelper.classify_response(200, %{"success" => false}) == :no_success_flag
    end
  end
end
