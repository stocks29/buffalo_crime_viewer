defmodule BuffaloCrimeViewer.Scene.Home do
  require Logger
  use Scenic.Scene

  alias Scenic.Graph

  import Scenic.Primitives
  import Scenic.Components

  alias BuffaloCrimeViewer.Data.Crimes

  @graph Graph.build(font: :roboto, font_size: 24)
  |> text("Buffalo Crime Viewer", id: :intro_text, font_size: 36, translate: {250, 40})
  |> text_field("", id: :search_text, translate: {150, 80})
  |> button("Search", id: :search_button, translate: {400, 80})
  |> button("Reset", id: :reset_button, translate: {500, 80})
  |> text("", id: :crime_text, translate: {20, 200})
  |> text("", id: :crime_loc_text, translate: {400, 200})
  |> button("Map", id: :map_button, translate: {400, 350})
  |> button("Previous", id: :prev_button, translate: {300, 650})
  |> button("Next", id: :next_button, translate: {420, 650})
  |> slider({{0, 1}, 1}, id: :num_slider, translate: {250, 700})
  |> text("", id: :pos_text, translate: {350, 750})

  # ============================================================================
  # setup

  # --------------------------------------------------------
  def init(_, _) do
    {:ok, crimes_pid} = Crimes.start_link()
    {_crime, i, size} = crime_pos = Crimes.current(crimes_pid)
    graph = @graph
    |> Graph.modify(:num_slider, &slider(&1, {{min(1, size), size}, i}))
    |> update_crime(crime_pos)
    {:ok, %{graph: graph, search_term: "", crimes_pid: crimes_pid, command: ""}}
  end

  def handle_input({:key, {"escape", :press, _}}, _context, sc_state) do
    {:noreply, reset(sc_state)}
  end

  def handle_input({:key, {"M", :press, _}}, _context, sc_state) do
    open_map(sc_state)
    {:noreply, sc_state}
  end

  def handle_input({:key, {"G", :press, _}}, _context, sc_state) do
    {:noreply, %{sc_state | command: "G"}}
  end

  def handle_input({:key, {"Q", :press, _}}, _context, sc_state) do
    System.stop()
    {:noreply, sc_state}
  end

  def handle_input({:key, {key, action, _}}, _context, sc_state) when key in ["P", "left", "backspace"] and action in [:press, :repeat] do
    {:noreply, go_to_prev(sc_state)}
  end

  def handle_input({:key, {key, action, _}}, _context, sc_state) when key in ["N", "right", " "] and action in [:press, :repeat] do
    {:noreply, go_to_next(sc_state)}
  end

  def handle_input({:key, {"enter", :press, _other}}, _context, sc_state = %{command: "G" <> command}) do
    {:noreply, %{go_to_at(sc_state, String.to_integer(command), &update_crime_with_slider/2) | command: ""}}
  end

  def handle_input({:key, {key, :press, _other}}, _context, sc_state = %{command: "G" <> command}) when key in ~w(0 1 2 3 4 5 6 7 8 9) do
    {:noreply, %{sc_state | command: "G#{command}#{key}"}}
  end

  def handle_input({:key, {_key, _action, _other}}, _context, sc_state) do
    # Logger.debug("key=#{_key} action=#{inspect _action} other=#{inspect _other}")
    {:noreply, sc_state}
  end

  def handle_input(_input, _context, sc_state) do
    {:noreply, sc_state}
  end


  def filter_event({:value_changed, :search_text, value}, _from_pid, sc_state) do
    {:stop, %{sc_state | search_term: value}}
  end

  def filter_event({:value_changed, :num_slider, value}, _from_pid, sc_state) do
    {:stop, go_to_at(sc_state, value)}
  end

  def filter_event({:click, :reset_button}, _from_pid, sc_state) do
    {:stop, reset(sc_state)}
  end

  def filter_event({:click, :search_button}, _from_pid, sc_state = %{graph: graph, search_term: search_term, crimes_pid: crimes_pid}) do
    graph = update_crime_with_slider(graph, Crimes.search(crimes_pid, search_term))
    {:stop, %{sc_state | graph: graph}}
  end

  def filter_event({:click, :map_button}, _from_pid, sc_state) do
    open_map(sc_state)
    {:stop, sc_state}
  end

  def filter_event({:click, :prev_button}, _from_pid, sc_state) do
    {:stop, go_to_prev(sc_state)}
  end

  def filter_event({:click, :next_button}, _from_pid, sc_state) do
    {:stop, go_to_next(sc_state)}
  end

  def filter_event(event, from_pid, sc_state) do
    super(event, from_pid, sc_state)
  end

  defp go_to_at(sc_state = %{crimes_pid: crimes_pid, graph: graph}, num, updater \\ &update_crime/2) do
    graph = updater.(graph, Crimes.at(crimes_pid, num))
    %{sc_state | graph: graph}
  end

  defp go_to_prev(sc_state) do
    go_to(sc_state, &Crimes.prev/1)
  end

  defp go_to_next(sc_state) do
    go_to(sc_state, &Crimes.next/1)
  end

  defp go_to(sc_state = %{graph: graph, crimes_pid: crimes_pid}, display_data_fn) do
    graph = update_crime_with_slider(graph, display_data_fn.(crimes_pid))
    %{sc_state | graph: graph}
  end

  defp reset(sc_state = %{graph: graph, crimes_pid: crimes_pid}) do
    graph = graph
    |> update_crime_with_slider(Crimes.reset(crimes_pid))
    %{sc_state | graph: graph}
  end

  defp open_map(%{crimes_pid: crimes_pid}) do
    {crime, _, _size} = Crimes.current(crimes_pid)
    System.cmd("open", ["https://www.google.com/maps/search/?api=1&query=#{crime["latitude"]},#{crime["longitude"]}"])
  end

  defp update_crime(graph, {crime, i, size}) do
    hidden = size < 1
    graph
    |> Graph.modify(:crime_text, &text(&1, crime_text(crime)))
    |> Graph.modify(:crime_loc_text, &text(&1, crime_location_text(crime)))
    |> Graph.modify(:pos_text, &text(&1, "#{i} of #{size}"))
    |> Graph.modify(:map_button, &button(&1, "Map", hidden: hidden))
    |> Graph.modify(:prev_button, &button(&1, "Previous", hidden: hidden))
    |> Graph.modify(:next_button, &button(&1, "Next", hidden: hidden))
    |> push_graph()
  end

  defp update_crime_with_slider(graph, crime_context) do
    graph
    |> update_slider(crime_context)
    |> update_crime(crime_context)
  end

  defp update_slider(graph, {_crime, _i, 0}) do
    graph
    |> Graph.modify(:num_slider, &slider(&1, {{0,1}, 0}, hidden: true))
  end
  defp update_slider(graph, {_crime, i, size}) do
    graph
    |> Graph.modify(:num_slider, &slider(&1, {{1,size}, i}, hidden: false))
  end

  defp crime_text(nil), do: "No crime found"
  defp crime_text(crime) do
    """
    Case #: #{crime["case_number"]}
    Incident Id: #{crime["incident_id"]}
    #{crime["incident_datetime"]}

    Primary Type: #{crime["incident_type_primary"]}
    Parent Type: #{crime["parent_incident_type"]}
    """
  end

  defp crime_location_text(nil), do: ""
  defp crime_location_text(crime) do
    """
    Address:
    #{crime["address_1"]}
    #{crime["city"]}, #{crime["state"]}

    Latitude: #{crime["latitude"]}
    Longitude: #{crime["longitude"]}
    """
  end
end
