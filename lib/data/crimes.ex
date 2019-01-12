defmodule BuffaloCrimeViewer.Data.Crimes do
  use Agent

  defmodule Loader do
    HTTPoison.start()

    def load_crimes!() do
      %HTTPoison.Response{body: body, status_code: 200} = HTTPoison.get!("https://data.buffalony.gov/resource/d6g9-xbgu.json")
      body
      |> Poison.decode!()
      |> Enum.sort_by(fn crime -> crime["incident_datetime"] end, &>=/2)
    end
  end

  @crimes Loader.load_crimes!()

  def start_link() do
    [crime|more] = @crimes
    Agent.start_link(fn -> {[], crime, more, 1, length(@crimes)} end, name: __MODULE__)
  end

  def reset(pid) do
    Agent.get_and_update(pid, fn _old ->
      [cur|more] = @crimes
      size = length(@crimes)
      {{cur, 1, size}, {[], cur, more, 1, size}}
    end)
  end

  def search(pid, term) do
    Agent.get_and_update(pid, fn _old_state ->
      crimes = @crimes
      |> Enum.filter(fn crime ->
        clean_term = term
        |> String.downcase()
        |> String.trim()

        crime["incident_type_primary"]
        |> String.downcase()
        |> String.contains?(clean_term)
        ||
        crime["address_1"]
        |> String.downcase()
        |> String.contains?(clean_term)
      end)
      s = length(crimes)
      case s do
        0 ->
          {{nil, 0, 0}, {[], nil, [], 0, 0}}
        size ->
          [cur|more] = crimes
          {{cur, 1, size}, {[], cur, more, 1, size}}
      end
    end)
  end

  def count(pid) do
    Agent.get(pid, fn {_prev, _cur, _next, _i, size} -> size end)
  end

  def current(pid) do
    Agent.get(pid, fn {_prev, cur, _next, i, size} -> {cur, i, size} end)
  end

  def at(pid, num) do
    Agent.get_and_update(pid, fn
      {_prev, cur, _next, i, size} = state when num > size -> {{cur, i, size}, state}
      state -> navigate_to(state, num)
    end)
  end

  def next(pid) do
    Agent.get_and_update(pid, fn
      {prev, cur, [], count, size} -> {{cur, size, size}, {prev, cur, [], count, size}}
      {prev, cur, [next|more], count, size} -> {{next, count+1, size}, {[cur|prev], next, more, count+1, size}}
    end)
  end

  def prev(pid) do
    Agent.get_and_update(pid, fn
      {[], cur, next, count, size} -> {{cur, count, size}, {[], cur, next, count, size}}
      {[next_cur|prev], cur, next, count, size} -> {{next_cur, count-1, size}, {prev, next_cur, [cur|next], count-1, size}}
    end)
  end

  defp navigate_to({prev, cur, [item|more], i, size}, to) when to > i do
    navigate_to({[cur|prev], item, more, i+1, size}, to)
  end
  defp navigate_to({[item|prev], cur, next, i, size}, to) when to < i do
    navigate_to({prev, item, [cur|next], i-1, size}, to)
  end
  defp navigate_to({prev, cur, next, i, size}, i) do
    {{cur, i, size}, {prev, cur, next, i, size}}
  end
end
