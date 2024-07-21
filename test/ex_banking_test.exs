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

  test "exceeding deposit max requests" do
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

  test "exceeding withdraw max requests" do
    ExBanking.create_user("user3")
    ExBanking.deposit("user3", 10000, "USD")
    tasks =
      for _ <- 1..12 do
        Task.async(fn ->
          ExBanking.withdraw("user3", 100, "USD")
        end)
      end

    results = Enum.map(tasks, &Task.await(&1))
    too_many_requests_count = Enum.count(results, fn result -> result == {:error, :too_many_requests_to_user} end)

    assert too_many_requests_count == 2
    assert {:ok, 9000} == ExBanking.get_balance("user3", "USD")
  end

  test "exceeding get_balance max requests" do
    ExBanking.create_user("user4")
    ExBanking.deposit("user4", 10000, "USD")
    tasks =
      for _ <- 1..12 do
        Task.async(fn ->
          ExBanking.get_balance("user4", "USD")
        end)
      end

    results = Enum.map(tasks, &Task.await(&1))
    too_many_requests_count = Enum.count(results, fn result -> result == {:error, :too_many_requests_to_user} end)

    assert too_many_requests_count == 2
    assert {:ok, 10000} == ExBanking.get_balance("user4", "USD")
  end

  test "exceeding send max requests" do
    ExBanking.create_user("user5")
    ExBanking.create_user("user6")
    ExBanking.deposit("user5", 10000, "USD")
    ExBanking.deposit("user6", 1000, "USD")

    tasks =
      for _ <- 1..12 do
        Task.async(fn ->
          ExBanking.send("user5", "user6", 100, "USD")
        end)
      end

    results = Enum.map(tasks, &Task.await(&1))
    too_many_requests_count = Enum.count(results, fn result -> result == {:error, :too_many_requests_to_user} end)

    assert too_many_requests_count == 2
    assert {:ok, 9000} == ExBanking.get_balance("user5", "USD")
    assert {:ok, 2000} == ExBanking.get_balance("user6", "USD")
  end

  test "exceeding max requests by different operations for a single user" do
    ExBanking.create_user("user1")
    ExBanking.create_user("user2")
    ExBanking.deposit("user1", 10000, "USD")
    ExBanking.deposit("user2", 1000, "USD")

    tasks =
      for _ <- 1..12 do
        [
          Task.async(fn -> ExBanking.deposit("user1", 100, "USD") end),
          Task.async(fn -> ExBanking.withdraw("user1", 50, "USD") end),
          Task.async(fn -> ExBanking.get_balance("user1", "USD") end),
          Task.async(fn -> ExBanking.send("user1", "user2", 100, "USD") end)
        ]
      end
      |> List.flatten()

    results = Enum.map(tasks, &Task.await(&1))
    too_many_requests_count = Enum.count(results, fn result -> result == {:error, :too_many_requests_to_user} end)

    # Checking that there are more than 2 requests that exceeded the limit (since we expect 10 successful ones)
    assert too_many_requests_count >= 2

    # Checking the final balance
    assert {:ok, _balance} = ExBanking.get_balance("user1", "USD")
  end


end
