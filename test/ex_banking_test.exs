defmodule ExBankingTest do
  use ExUnit.Case
  alias ExBanking

  # max requests test
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

    too_many_requests_count =
      Enum.count(results, fn result -> result == {:error, :too_many_requests_to_user} end)

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

    too_many_requests_count =
      Enum.count(results, fn result -> result == {:error, :too_many_requests_to_user} end)

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

    too_many_requests_count =
      Enum.count(results, fn result -> result == {:error, :too_many_requests_to_user} end)

    assert too_many_requests_count == 2
    assert {:ok, 10000} == ExBanking.get_balance("user4", "USD")
  end

  test "exceeding send max requests to sender" do
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

    too_many_requests_count =
      Enum.count(results, fn result -> result == {:error, :too_many_requests_to_sender} end)

    assert too_many_requests_count == 2
    assert {:ok, 9000} == ExBanking.get_balance("user5", "USD")
    assert {:ok, 2000} == ExBanking.get_balance("user6", "USD")
  end

  test "exceeding send max requests to receiver" do
    ExBanking.create_user("user7")
    ExBanking.create_user("user8")
    ExBanking.deposit("user7", 10000, "USD")
    ExBanking.deposit("user8", 1000, "USD")

    tasks =
      for _ <- 1..12 do
        [
          Task.async(fn -> ExBanking.deposit("user8", 500, "USD") end),
          Task.async(fn ->
            ExBanking.send("user7", "user8", 100, "USD")
          end)
        ]
      end
      |> List.flatten()

    results = Enum.map(tasks, &Task.await(&1))

    too_many_requests_count =
      Enum.count(results, fn result -> result == {:error, :too_many_requests_to_receiver} end)

    assert too_many_requests_count == 7
    assert {:ok, 9500} == ExBanking.get_balance("user7", "USD")
    assert {:ok, 4000} == ExBanking.get_balance("user8", "USD")
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

    too_many_requests_count =
      Enum.count(results, fn result -> result == {:error, :too_many_requests_to_sender} end)

    # Checking that there are more than 2 requests that exceeded the limit (since we expect 10 successful ones)
    assert too_many_requests_count >= 2

    # Checking the final balance
    assert {:ok, _} = ExBanking.get_balance("user1", "USD")
  end

  #creation tests
  test "create bank_user successfully" do
    assert :ok == ExBanking.create_user("bank_user1")
  end

  test "create bank_user with existing username" do
    ExBanking.create_user("bank_user1")
    assert {:error, :user_already_exists} == ExBanking.create_user("bank_user1")
  end

  test "create bank_user with invalid argument" do
    assert {:error, :wrong_arguments} == ExBanking.create_user(123)
  end

  #deposit  tests
  test "deposit successfully" do
    ExBanking.create_user("bank_user2")
    assert {:ok, 100.0} == ExBanking.deposit("bank_user2", 100, "USD")
  end

  test "deposit to non-existing bank_user" do
    assert {:error, :user_does_not_exist} == ExBanking.deposit("non_user", 100, "USD")
  end

  test "deposit with invalid arguments" do
    ExBanking.create_user("bank_user2")
    assert {:error, :wrong_arguments} == ExBanking.deposit("bank_user2", "100", "USD")
    assert {:error, :wrong_arguments} == ExBanking.deposit("bank_user2", 100, 123)
    assert {:error, :wrong_arguments} == ExBanking.deposit(123, 100, "USD")
  end

  #withdraw tests

  test "withdraw successfully" do
    ExBanking.create_user("bank_user3")
    ExBanking.deposit("bank_user3", 200, "USD")
    assert {:ok, 100.0} == ExBanking.withdraw("bank_user3", 100, "USD")
  end

  test "withdraw from non-existing bank_user" do
    assert {:error, :user_does_not_exist} == ExBanking.withdraw("non_user", 100, "USD")
  end

  test "withdraw with insufficient funds" do
    ExBanking.create_user("bank_user3")
    ExBanking.deposit("bank_user3", 50, "USD")
    assert {:error, :not_enough_money} == ExBanking.withdraw("bank_user3", 100, "USD")
  end

  test "withdraw with invalid arguments" do
    ExBanking.create_user("bank_user3")
    assert {:error, :wrong_arguments} == ExBanking.withdraw("bank_user3", "100", "USD")
    assert {:error, :wrong_arguments} == ExBanking.withdraw("bank_user3", 100, 123)
    assert {:error, :wrong_arguments} == ExBanking.withdraw(123, 100, "USD")
  end

  #get balance test

  test "get balance successfully" do
    ExBanking.create_user("bank_user1")
    ExBanking.deposit("bank_user1", 100, "USD")
    assert {:ok, 100.0} == ExBanking.get_balance("bank_user1", "USD")
  end

  test "get balance of non-existing bank_user" do
    assert {:error, :user_does_not_exist} == ExBanking.get_balance("non_user", "USD")
  end

  test "get balance with invalid arguments" do
    ExBanking.create_user("bank_user1")
    assert {:error, :wrong_arguments} == ExBanking.get_balance("bank_user1", 123)
    assert {:error, :wrong_arguments} == ExBanking.get_balance(123, "USD")
  end

  #send tests

  test "send money successfully" do
    ExBanking.create_user("bank_user1")
    ExBanking.create_user("bank_user2")
    ExBanking.deposit("bank_user1", 1000, "USD")
    assert {:ok, 900.0, 100.0} == ExBanking.send("bank_user1", "bank_user2", 100, "USD")
  end

  test "send money with insufficient funds" do
    ExBanking.create_user("bank_user1")
    ExBanking.create_user("bank_user2")
    ExBanking.deposit("bank_user1", 50, "USD")
    assert {:error, :not_enough_money} == ExBanking.send("bank_user1", "bank_user2", 100, "USD")
  end

  test "send money from non-existing bank_user" do
    ExBanking.create_user("bank_user2")
    assert {:error, :sender_does_not_exist} == ExBanking.send("non_user", "bank_user2", 100, "USD")
  end

  test "send money to non-existing bank_user" do
    ExBanking.create_user("bank_user1")
    ExBanking.deposit("bank_user1", 100, "USD")
    assert {:error, :receiver_does_not_exist} == ExBanking.send("bank_user1", "non_user", 100, "USD")
  end

  test "send money with invalid arguments" do
    ExBanking.create_user("bank_user1")
    ExBanking.create_user("bank_user2")
    assert {:error, :wrong_arguments} == ExBanking.send("bank_user1", "bank_user2", "100", "USD")
    assert {:error, :wrong_arguments} == ExBanking.send("bank_user1", "bank_user2", 100, 123)
    assert {:error, :wrong_arguments} == ExBanking.send(123, "bank_user2", 100, "USD")
    assert {:error, :wrong_arguments} == ExBanking.send("bank_user1", 123, 100, "USD")
  end

  #float testing

  test "deposit successfully with float" do
    ExBanking.create_user("bank_user2")
    assert {:ok, 123.52} == ExBanking.deposit("bank_user2", 123.52, "USD")
  end

  test "deposit to non-existing bank_user with float" do
    assert {:error, :user_does_not_exist} == ExBanking.deposit("non_user", 45.99, "USD")
  end

  test "deposit with invalid arguments with float" do
    ExBanking.create_user("bank_user2")
    assert {:error, :wrong_arguments} == ExBanking.deposit("bank_user2", "45.99", "USD")
    assert {:error, :wrong_arguments} == ExBanking.deposit("bank_user2", 45.99, 123)
    assert {:error, :wrong_arguments} == ExBanking.deposit(123, 45.99, "USD")
    assert {:error, :wrong_arguments} == ExBanking.deposit("bank_user2", 45.999, "USD")
  end

  test "withdraw successfully with float" do
    ExBanking.create_user("bank_user3")
    ExBanking.deposit("bank_user3", 200.75, "USD")
    assert {:ok, 150.50} == ExBanking.withdraw("bank_user3", 50.25, "USD")
  end

  test "withdraw from non-existing bank_user with float" do
    assert {:error, :user_does_not_exist} == ExBanking.withdraw("non_user", 89.75, "USD")
  end

  test "withdraw with insufficient funds with float" do
    ExBanking.create_user("bank_user3")
    ExBanking.deposit("bank_user3", 30.20, "USD")
    assert {:error, :not_enough_money} == ExBanking.withdraw("bank_user3", 50.50, "USD")
  end

  test "withdraw with invalid arguments with float" do
    ExBanking.create_user("bank_user3")
    assert {:error, :wrong_arguments} == ExBanking.withdraw("bank_user3", "50.50", "USD")
    assert {:error, :wrong_arguments} == ExBanking.withdraw("bank_user3", 50.50, 123)
    assert {:error, :wrong_arguments} == ExBanking.withdraw(123, 50.50, "USD")
    assert {:error, :wrong_arguments} == ExBanking.withdraw("bank_user3", 50.505, "USD")
  end

  test "get balance successfully with float" do
    ExBanking.create_user("bank_user1")
    ExBanking.deposit("bank_user1", 78.47, "USD")
    assert {:ok, 78.47} == ExBanking.get_balance("bank_user1", "USD")
  end

  test "get balance of non-existing bank_user with float" do
    assert {:error, :user_does_not_exist} == ExBanking.get_balance("non_user", "USD")
  end

  test "get balance with invalid arguments with float" do
    ExBanking.create_user("bank_user1")
    assert {:error, :wrong_arguments} == ExBanking.get_balance("bank_user1", 123)
    assert {:error, :wrong_arguments} == ExBanking.get_balance(123, "USD")
  end

  test "send money successfully with float" do
    ExBanking.create_user("bank_user1")
    ExBanking.create_user("bank_user2")
    ExBanking.deposit("bank_user1", 500.99, "USD")
    assert {:ok, 400.49, 100.5} == ExBanking.send("bank_user1", "bank_user2", 100.50, "USD")
  end

  test "send money with insufficient funds with float" do
    ExBanking.create_user("bank_user1")
    ExBanking.create_user("bank_user2")
    ExBanking.deposit("bank_user1", 25.99, "USD")
    assert {:error, :not_enough_money} == ExBanking.send("bank_user1", "bank_user2", 50.50, "USD")
  end

  test "send money from non-existing bank_user with float" do
    ExBanking.create_user("bank_user2")
    assert {:error, :sender_does_not_exist} == ExBanking.send("non_user", "bank_user2", 10.25, "USD")
  end

  test "send money to non-existing bank_user with float" do
    ExBanking.create_user("bank_user1")
    ExBanking.deposit("bank_user1", 30.30, "USD")
    assert {:error, :receiver_does_not_exist} == ExBanking.send("bank_user1", "non_user", 30.30, "USD")
  end

  test "send money with invalid arguments with float" do
    ExBanking.create_user("bank_user1")
    ExBanking.create_user("bank_user2")
    assert {:error, :wrong_arguments} == ExBanking.send("bank_user1", "bank_user2", "30.30", "USD")
    assert {:error, :wrong_arguments} == ExBanking.send("bank_user1", "bank_user2", 30.30, 123)
    assert {:error, :wrong_arguments} == ExBanking.send(123, "bank_user2", 30.30, "USD")
    assert {:error, :wrong_arguments} == ExBanking.send("bank_user1", 123, 30.30, "USD")
  end
end
