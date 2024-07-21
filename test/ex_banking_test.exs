defmodule ExBankingTest do
  use ExUnit.Case
  alias ExBanking

  test "concurrent deposits" do
    ExBanking.create_user("user1")

    tasks =
      for _ <- 1..10 do
        Task.async(fn ->
          ExBanking.deposit("user1", 100, "USD")
        end)
      end

    Enum.each(tasks, &Task.await(&1))

    assert {:ok, 1000} == ExBanking.get_balance("user1", "USD")
  end

  test "exceeding max requests" do
    ExBanking.create_user("user2")

    tasks =
      for _ <- 1..12 do
        Task.async(fn ->
          ExBanking.deposit("user2", 100, "USD")
        end)
      end

    results = Enum.map(tasks, &Task.await(&1))
    too_many_requests_count = Enum.count(results, fn result -> result == {:error, :too_many_requests_to_user} end)

    assert too_many_requests_count == 2
    assert {:ok, 1000} == ExBanking.get_balance("user2", "USD")
  end
end
