defmodule ExBanking do
  use GenServer

  @moduledoc """
  Documentation for `ExBanking`.
  https://coingaming.github.io/elixir-test/
  """
  def start_link(initial_state \\ %{}) do
    GenServer.start_link(__MODULE__, initial_state, name: __MODULE__)
  end

  def init(initial_state) do
    {:ok, initial_state}
  end

  #working functions

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

  #handler
  def handle_cast({:add_new_user, username}, state) do
    {:noreply, Map.put(state, username, %User{name: username, balance: %{}})}
  end

  def handle_call({:deposit, parameters}, _from, state) do
    updated_state = Map.get(state, parameters.username)
    |> deposit_balance(parameters.currency, parameters.amount)
    |> update_user(parameters.username)
    |> update_state(parameters.username, state)
    {:reply, {:ok, updated_state |> Map.get(parameters.username) |> extract_balance_from_user(parameters.currency)}, updated_state}
  end



  def handle_call({:withdraw, parameters}, _from, state) do
    with {:ok,  balance} <- Map.get(state, parameters.username)
    |> withdraw_balance(parameters.currency, parameters.amount) do
      updated_state = update_user(balance, parameters.username)
      |> update_state(parameters.username, state)
      {:reply, {:ok, updated_state |> Map.get(parameters.username) |> extract_balance_from_user(parameters.currency)}, updated_state}
    else
      result -> {:reply, result, state}
    end

  end

  def handle_call({:get_balance, parameters}, _from, state) do
    user = state |> Map.get(parameters.username)
    {:reply, {:ok, Map.get(user.balance, parameters.currency)}, state}
  end

  #private functions

  defp extract_balance_from_user(user, currency) do
    Map.get(user.balance, currency, 0)
  end

  defp deposit_balance(user, currency, amount) do
    Map.put(user.balance, currency, extract_balance_from_user(user, currency) + amount)
  end

  defp withdraw_balance(user, currency, amount) do
    current_balance = extract_balance_from_user(user, currency)
    cond do
      current_balance >= amount -> {:ok, Map.put(user.balance, currency, current_balance - amount)}
      true -> {:error, :not_enough_money}
    end
  end

  defp update_user(balance, username) do
    %User{name: username, balance: balance}
  end

  defp update_state(updated_user, key, current_state) do
    Map.put(current_state, key, updated_user)
  end

  defp start_genserver_if_its_not_running() do
    if Process.whereis(__MODULE__) do
      IO.puts("GenServer is running")
    else
      start_link()
      IO.puts("Started GenServer")
    end
  end
end
