defmodule ExBanking do
  use GenServer

  @moduledoc """
  Documentation for `ExBanking`.
  https://coingaming.github.io/elixir-test/
  """
  @spec start_link(any()) :: :ignore | {:error, any()} | {:ok, pid()}
  def start_link(initial_state \\ %{}) do
    GenServer.start_link(__MODULE__, initial_state, name: __MODULE__)
  end

  @spec init(any()) :: {:ok, any()}
  def init(initial_state) do
    {:ok, initial_state}
  end

  # working functions

  @spec create_user(any()) :: :ignore | :ok | {:error, any()} | {:ok, pid()}
  def create_user(username) do
    start_genserver_if_its_not_running()
    GenServer.cast(__MODULE__, {:add_new_user, username})
  end

  def deposit(username, amount, currency) do
    start_genserver_if_its_not_running()
    parameters = %{username: username, amount: amount, currency: currency}
    GenServer.call(__MODULE__, {:deposit, parameters})
  end

  def withdraw(username, amount, currency) do
    start_genserver_if_its_not_running()
    parameters = %{username: username, amount: amount, currency: currency}
    GenServer.call(__MODULE__, {:withdraw, parameters})
  end

  def get_balance(username, currency) do
    start_genserver_if_its_not_running()
    parameters = %{username: username, currency: currency}
    GenServer.call(__MODULE__, {:get_balance, parameters})
  end

  @spec send(
          from_user :: String.t(),
          to_user :: String.t(),
          amount :: number,
          currency :: String.t()
        ) :: {:ok, from_user_balance :: number, to_user_balance :: number}
  def send(from_username, to_username, amount, currency) do
    parameters = %{
      from_username: from_username,
      to_username: to_username,
      amount: amount,
      currency: currency
    }

    GenServer.call(__MODULE__, {:send, parameters})
  end

  # handler
  def handle_cast({:add_new_user, username}, state) do
    {:noreply, Map.put(state, username, %User{name: username, balance: %{}})}
  end

  def handle_cast({:add_amount_requests_for_user, parameters}, state) do
    {:noreply, update_amount_of_requests_for_user(state, parameters, true)}
  end

  def handle_call({:deposit, parameters}, _from, state) do
    with {:error, error} <- check_pending_requests(state, parameters.username) do
      {:reply, error, state}
    else
      :ok ->
        GenServer.cast(__MODULE__, {:add_amount_requests_for_user, parameters})

        {:ok, updated_state} =
          deposit(parameters.username, parameters.amount, parameters.currency, state)

        {:reply,
         {:ok,
          updated_state
          |> Map.get(parameters.username)
          |> extract_balance_from_user(parameters.currency)},
         updated_state |> update_amount_of_requests_for_user(parameters, false)}
    end
  end

  def handle_call({:withdraw, parameters}, _from, state) do
    case withdraw(parameters.username, parameters.amount, parameters.currency, state) do
      {:ok, new_state} ->
        {:reply,
         {:ok,
          Map.get(new_state, parameters.username)
          |> extract_balance_from_user(parameters.currency)}, new_state}

      {:error, msg} ->
        {:reply, msg, state}
    end
  end

  def handle_call({:send, parameters}, _from, state) do
    with {:ok, updated_state_from_sender} <-
           withdraw(parameters.from_username, parameters.amount, parameters.currency, state),
         {:ok, updated_state_from_receiver} <-
           deposit(
             parameters.to_username,
             parameters.amount,
             parameters.currency,
             updated_state_from_sender
           ) do
      sender_balance =
        Map.get(updated_state_from_receiver, parameters.from_username)
        |> extract_balance_from_user(parameters.currency)

      receiver_balance =
        Map.get(updated_state_from_receiver, parameters.to_username)
        |> extract_balance_from_user(parameters.currency)

      {:reply, {:ok, sender_balance, receiver_balance}, updated_state_from_receiver}
    else
      error -> {:reply, error, state}
    end
  end

  def handle_call({:get_balance, parameters}, _from, state) do
    user = state |> Map.get(parameters.username)
    {:reply, {:ok, Map.get(user.balance, parameters.currency)}, state}
  end

  # private functions

  defp update_amount_of_requests_for_user(state, parameters, is_add) when is_add do
    user = state |> Map.get(parameters.username)
    state
    |> Map.put(
      parameters.username,
      update_user(user.balance, user.name, user.pending_requests + 1)
    )
  end

  defp update_amount_of_requests_for_user(state, parameters, _is_add) do
    user = state |> Map.get(parameters.username)

    state
    |> Map.put(
      parameters.username,
      update_user(user.balance, user.name, user.pending_requests - 1)
    )
  end

  defp check_pending_requests(state, username) do
    if (abs(extract_pending_requests_from_state(state, username)) + 1 <= 10) do
      :ok
    else
      {:error, {:error, :too_many_requests_to_user}}
    end
  end

  defp deposit(username, amount, currency, state) do
    updated_state =
      Map.get(state, username)
      |> deposit_balance(currency, amount)
      |> update_user(username, extract_pending_requests_from_state(state, username))
      |> update_state(username, state)

    {:ok, updated_state}
  end

  defp withdraw(username, amount, currency, state) do
    with {:ok, balance} <-
           Map.get(state, username)
           |> withdraw_balance(currency, amount) do
      updated_state =
        update_user(balance, username, extract_pending_requests_from_state(state, username))
        |> update_state(username, state)

      {:ok, updated_state}
    else
      result -> {:error, result}
    end
  end

  defp extract_pending_requests_from_state(state, username) do
    user = state |> Map.get(username)
    user.pending_requests
  end

  defp extract_balance_from_user(user, currency) do
    Map.get(user.balance, currency, 0)
  end

  defp deposit_balance(user, currency, amount) do
    Map.put(user.balance, currency, extract_balance_from_user(user, currency) + amount)
  end

  defp withdraw_balance(user, currency, amount) do
    current_balance = extract_balance_from_user(user, currency)

    cond do
      current_balance >= amount ->
        {:ok, Map.put(user.balance, currency, current_balance - amount)}

      true ->
        {:error, :not_enough_money}
    end
  end

  defp update_user(balance, username, pending_requests) do
    %User{name: username, balance: balance, pending_requests: pending_requests}
  end

  defp update_state(updated_user, key, current_state) do
    Map.put(current_state, key, updated_user)
  end

  defp start_genserver_if_its_not_running() do
    if !Process.whereis(__MODULE__) do
      start_link()
    end
  end
end
