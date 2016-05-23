defmodule PropCheck.Test.PingPongFSM do
  @moduledoc """
  Similar to `PingPongStateM`, but this time depending on the FSM module to
  understand the difference between both approaches.
  """

  # State is modelled as tuples of `{state_name, state}`
  use PropCheck.FSM
  alias PropCheck.Test.PingPongMaster
  require Logger

  defstruct players: [], scores: %{}

  @max_players 100
  @players 1..@max_players |> Enum.map(&("player_#{&1}") |> String.to_atom)

  def initial_state(), do: :empty_state
  def initial_state_data, do: %__MODULE__{}

  def empty_state(_) do
    [{:player_state, {:call, PingPongMaster, :add_player, [oneof(@players)]}}]
  end

  def player_state(s = %__MODULE__{players: [last_player]}) do
    empty_state(s) ++ play_games(s) ++ [
      {:player_state, {:call, PingPongMaster, :get_score, [last_player]}},
      {:empty_state, {:call, PingPongMaster, :remove_player, [last_player]}},
    ]
  end
  def player_state(s = %__MODULE__{players: ps}) do
    empty_state(s) ++ play_games(s) ++ [
      {:player_state, {:call, PingPongMaster, :get_score, [oneof ps]}},
      {:player_state, {:call, PingPongMaster, :remove_player, [oneof ps]}},
    ]
  end

  defp play_games(s = %__MODULE__{players: ps}) do
    [:play_ping_pong, :play_tennis, :play_football]
    |> Enum.map(fn f -> {:history, {:call, PingPongMaster, f, [oneof ps]}} end)
  end

  # no specific preconditions
  def precondition(_from, _target, _state, {:call, _m, _f, _a,}), do: true

  # inprecise get_score due to async play-functions
  def postcondition(_from, _target, %__MODULE__{scores: scores},
                    {:call, _, :get_score, [player]}, res) do
    res <= scores[player]
  end
  def postcondition(_from, _target, _state, {:call, _m, _f, _a}, _res) do
    true
  end

  # state data is updates for adding, removing, playing.
  def next_state_data(_from, _target, state, _res, {:call, _m, :add_player, [p]}) do
    if not Enum.member?(state.players, p) do
      %__MODULE__{state |
          players: [p | state.players],
          scores: Map.put_new(state.scores, p, 0)
        }
    else
      state
    end
  end
  def next_state_data(_from, _target, state, _res, {:call, _, :remove_player, [p]}) do
    if Enum.member?(state.players, p) do
      %__MODULE__{state |
          players: List.delete(state.players, p),
          scores: Map.delete(state.scores, p)
        }
    else
      state
    end
  end
  def next_state_data(_from, _target, state, _res, {:call, _, :play_ping_pong, [p]}) do
    if Enum.member?(state.players, p) do
      %__MODULE__{state |
          scores: Map.update!(state.scores, p, fn v -> v+1 end)}
    else
      state
    end
  end
  def next_state_data(_from, _target, state, _res, _call), do: state


  property "ping-pong FSM works properly" do
    numtests(3_000, forall cmds in commands(__MODULE__) do
      trap_exit do
        kill_all_player_processes()
        PingPongMaster.start_link()
        r = run_commands(__MODULE__, cmds)
        {history, state, result} = r
        PingPongMaster.stop
        #IO.puts "Property finished. result is: #{inspect r}"
        when_fail(
          IO.puts("""
          History: #{inspect history, pretty: true}\n
          State: #{inspect state, pretty: true}\n
          Result: #{inspect result, pretty: true}
          """),
          aggregate(state_names(cmds), result == :ok))
      end
    end)
  end

  # ensure all player processes are dead
  defp kill_all_player_processes() do
    Process.registered
    |> Enum.filter(&(Atom.to_string(&1) |> String.starts_with?("player_")))
    |> Enum.each(fn name ->
      pid = Process.whereis(name)
      if is_pid(pid) and Process.alive?(pid) do
        try do
          Process.exit(pid, :kill)
        catch
          _what, _value -> Logger.debug "Already killed process #{name}"
        end
      end
    end)
  end

end