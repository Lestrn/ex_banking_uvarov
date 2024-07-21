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

  @spec create_user(username :: String.t()) ::
          :ok | {:error, :wrong_arguments | :user_already_exists}
  def create_user(username) when is_binary(username) do
    start_genserver_if_its_not_running()
    GenServer.call(__MODULE__, {:add_new_user, username})
  end

  def create_user(_username) do
    {:error, :wrong_arguments}
  end

  @spec deposit(user :: String.t(), amount :: number, currency :: String.t()) ::
          {:ok, new_balance :: number}
          | {:error, :wrong_arguments | :user_does_not_exist | :too_many_requests_to_user}
  def deposit(username, amount, currency)
      when is_binary(username) and is_integer(amount) and is_binary(currency) do
    start_genserver_if_its_not_running()
    parameters = %{username: username, amount: amount, currency: currency}
    GenServer.call(__MODULE__, {:deposit, parameters})
  end

  def deposit(_username, _amount, _currency) do
    {:error, :wrong_arguments}
  end

  @spec withdraw(user :: String.t(), amount :: number, currency :: String.t()) ::
          {:ok, new_balance :: number}
          | {:error,
             :wrong_arguments
             | :user_does_not_exist
             | :not_enough_money
             | :too_many_requests_to_user}
  def withdraw(username, amount, currency)
      when is_binary(username) and is_integer(amount) and is_binary(currency) do
    start_genserver_if_its_not_running()
    parameters = %{username: username, amount: amount, currency: currency}
    GenServer.call(__MODULE__, {:withdraw, parameters})
  end

  def withdraw(_username, _amount, _currency) do
    {:error, :wrong_arguments}
  end

  @spec get_balance(user :: String.t(), currency :: String.t()) ::
          {:ok, balance :: number}
          | {:error, :wrong_arguments | :user_does_not_exist | :too_many_requests_to_user}
  def get_balance(username, currency) when is_binary(username) and is_binary(currency) do
    start_genserver_if_its_not_running()
    parameters = %{username: username, currency: currency}
    GenServer.call(__MODULE__, {:get_balance, parameters})
  end

  def get_balance(_username, _currency) do
    {:error, :wrong_arguments}
  end

  @spec send(
          from_user :: String.t(),
          to_user :: String.t(),
          amount :: number,
          currency :: String.t()
        ) ::
          {:ok, from_user_balance :: number, to_user_balance :: number}
          | {:error,
             :wrong_arguments
             | :not_enough_money
             | :sender_does_not_exist
             | :receiver_does_not_exist
             | :too_many_requests_to_sender
             | :too_many_requests_to_receiver}
  def send(from_username, to_username, amount, currency)
      when is_binary(from_username) and is_binary(to_username) and is_integer(amount) and
             is_binary(currency) do
    parameters = %{
      from_username: from_username,
      to_username: to_username,
      amount: amount,
      currency: currency
    }

    GenServer.call(__MODULE__, {:send, parameters})
  end

  def send(_from_username, _to_username, _amount, _currency) do
    {:error, :wrong_arguments}
  end

  # handler

  def handle_cast({:add_amount_requests_for_user, username}, state) do
    {:noreply, update_amount_of_requests_for_user(state, username, true)}
  end

  def handle_call({:add_new_user, username}, _from, state) do
    if(user_exists?(state, username)) do
      {:reply, {:error, :user_already_exists}, state}
    else
      {:reply, :ok, Map.put(state, username, %User{name: username, balance: %{}})}
    end
  end

  def handle_call({:deposit, parameters}, _from, state) do
    # for check pending requests
    :timer.sleep(10)

    if(!user_exists?(state, parameters.username)) do
      {:reply, {:error, :user_does_not_exist}, state}
    else
      with {:error, error} <- check_pending_requests(state, parameters.username) do
        {:reply, error, state}
      else
        :ok ->
          GenServer.cast(__MODULE__, {:add_amount_requests_for_user, parameters.username})

          {:ok, updated_state} =
            deposit(parameters.username, parameters.amount, parameters.currency, state)

          {:reply,
           {:ok,
            updated_state
            |> Map.get(parameters.username)
            |> extract_balance_from_user(parameters.currency)},
           updated_state |> update_amount_of_requests_for_user(parameters.username, false)}
      end
    end
  end

  def handle_call({:withdraw, parameters}, _from, state) do
    # for check pending requests
    :timer.sleep(10)

    if(!user_exists?(state, parameters.username)) do
      {:reply, {:error, :user_does_not_exist}, state}
    else
      with {:error, error} <- check_pending_requests(state, parameters.username) do
        {:reply, error, state}
      else
        :ok ->
          GenServer.cast(__MODULE__, {:add_amount_requests_for_user, parameters.username})

          case withdraw(parameters.username, parameters.amount, parameters.currency, state) do
            {:ok, new_state} ->
              {:reply,
               {:ok,
                Map.get(new_state, parameters.username)
                |> extract_balance_from_user(parameters.currency)},
               new_state |> update_amount_of_requests_for_user(parameters.username, false)}

            {:error, msg} ->
              {:reply, {:error, msg},
               state |> update_amount_of_requests_for_user(parameters.username, false)}
          end
      end
    end
  end

  def handle_call({:send, parameters}, _from, state) do
    # for check pending requests
    :timer.sleep(10)

    with {:error, user_exists_error} <-
           sender_user_exists_helper(parameters.from_username, parameters.to_username, state) do
      {:reply, {:error, user_exists_error}, state}
    else
      :ok ->
        with {:error, error} <-
               check_pending_requests_for_send_function(
                 state,
                 parameters.from_username,
                 parameters.to_username
               ) do
          {:reply, error, state}
        else
          :ok ->
            GenServer.cast(__MODULE__, {:add_amount_requests_for_user, parameters.from_username})
            GenServer.cast(__MODULE__, {:add_amount_requests_for_user, parameters.to_username})

            with {:ok, updated_state_from_sender} <-
                   withdraw(
                     parameters.from_username,
                     parameters.amount,
                     parameters.currency,
                     state
                   ),
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

              {:reply, {:ok, sender_balance, receiver_balance},
               updated_state_from_receiver
               |> update_amount_of_requests_for_user(parameters.from_username, false)
               |> update_amount_of_requests_for_user(parameters.to_username, false)}
            else
              error ->
                {:reply, error,
                 state
                 |> update_amount_of_requests_for_user(parameters.from_username, false)
                 |> update_amount_of_requests_for_user(parameters.to_username, false)}
            end
        end
    end
  end

  def handle_call({:get_balance, parameters}, _from, state) do
    # for check pending requests
    :timer.sleep(10)

    if(!user_exists?(state, parameters.username)) do
      {:reply, {:error, :user_does_not_exist}, state}
    else
      with {:error, error} <- check_pending_requests(state, parameters.username) do
        {:reply, error, state}
      else
        :ok ->
          GenServer.cast(__MODULE__, {:add_amount_requests_for_user, parameters.username})
          user = state |> Map.get(parameters.username)

          {:reply, {:ok, Map.get(user.balance, parameters.currency, 0)},
           state |> update_amount_of_requests_for_user(parameters.username, false)}
      end
    end
  end

  # private functions
  defp user_exists?(state, username) do
    Map.has_key?(state, username)
  end

  defp sender_user_exists_helper(sender_username, receiver_username, state) do
    cond do
      not user_exists?(state, sender_username) ->
        {:error, :sender_does_not_exist}

      not user_exists?(state, receiver_username) ->
        {:error, :receiver_does_not_exist}

      true ->
        :ok
    end
  end

  defp update_amount_of_requests_for_user(state, username, is_add) when is_add do
    user = state |> Map.get(username)

    state
    |> Map.put(
      username,
      update_user(user.balance, user.name, user.pending_requests + 1)
    )
  end

  defp update_amount_of_requests_for_user(state, username, _is_add) do
    user = state |> Map.get(username)

    state
    |> Map.put(
      username,
      update_user(user.balance, user.name, user.pending_requests - 1)
    )
  end

  defp check_pending_requests(state, username) do
    if abs(extract_pending_requests_from_state(state, username)) + 1 <= 10 do
      :ok
    else
      {:error, {:error, :too_many_requests_to_user}}
    end
  end

  defp check_pending_requests_for_send_function(state, sender_username, receiver_username) do
    with {:error, _error} <- check_pending_requests(state, sender_username) do
      {:error, {:error, :too_many_requests_to_sender}}
    else
      :ok ->
        with {:error, _error} <- check_pending_requests(state, receiver_username) do
          {:error, {:error, :too_many_requests_to_receiver}}
        else
          :ok ->
            :ok
        end
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
      result -> result
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
