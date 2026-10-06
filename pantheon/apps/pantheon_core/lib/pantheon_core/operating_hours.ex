defmodule PantheonCore.OperatingHours do
  @moduledoc """
  Configurable server operating-hours schedule.

  Lets an operator define, per weekday, the windows during which the
  live world (WebSocket feed / interactive API) is open to visitors —
  independent of whether the simulation itself is ticking in the
  background. The dashboard's status pill and "opens in / closes in"
  countdown are both driven from `status/1`, computed live from whatever
  schedule the user has entered — nothing here is hard-coded.

  Schedule shape (all user-supplied, persisted to disk):

      %{
        timezone_offset_minutes: 0,
        monday:    [%{"start" => "09:00", "end" => "18:00"}],
        tuesday:   [%{"start" => "09:00", "end" => "18:00"}],
        wednesday: [...], thursday: [...], friday: [...],
        saturday:  [], sunday: []
      }

  An empty list for a day means "closed all day". Multiple windows per
  day (e.g. a midday break) are supported.
  """
  use GenServer

  @weekdays [:monday, :tuesday, :wednesday, :thursday, :friday, :saturday, :sunday]

  @default_schedule %{
    "timezone_offset_minutes" => 0,
    "monday" => [%{"start" => "09:00", "end" => "18:00"}],
    "tuesday" => [%{"start" => "09:00", "end" => "18:00"}],
    "wednesday" => [%{"start" => "09:00", "end" => "18:00"}],
    "thursday" => [%{"start" => "09:00", "end" => "18:00"}],
    "friday" => [%{"start" => "09:00", "end" => "18:00"}],
    "saturday" => [],
    "sunday" => []
  }

  # ---------------------------------------------------------------- API --

  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  @doc "Replace the whole schedule (as submitted by the user from the Settings screen)."
  def set_schedule(schedule) when is_map(schedule) do
    GenServer.call(__MODULE__, {:set_schedule, schedule})
  end

  def get_schedule, do: GenServer.call(__MODULE__, :get_schedule)

  @doc """
  Live status at `now` (defaults to current UTC time). Returns:

      %{open: true,  changes_at: ~U[...], seconds_until_change: 1234, next_state: :closed}
      %{open: false, changes_at: ~U[...], seconds_until_change: 4321, next_state: :open}
      %{open: false, changes_at: nil,     seconds_until_change: nil,  next_state: :none}

  `next_state: :none` means the schedule has no open windows at all in
  the coming 7 days (fully closed schedule).
  """
  def status(now \\ DateTime.utc_now()) do
    GenServer.call(__MODULE__, {:status, now})
  end

  # ----------------------------------------------------------- callbacks --

  @impl true
  def init(_) do
    schedule = load_from_disk() || @default_schedule
    {:ok, %{schedule: schedule}}
  end

  @impl true
  def handle_call({:set_schedule, schedule}, _from, state) do
    normalized = Map.merge(@default_schedule, schedule)
    persist_to_disk(normalized)
    {:reply, :ok, %{state | schedule: normalized}}
  end

  def handle_call(:get_schedule, _from, state), do: {:reply, state.schedule, state}

  def handle_call({:status, now}, _from, state) do
    {:reply, compute_status(state.schedule, now), state}
  end

  # ------------------------------------------------------------ internal --

  defp compute_status(schedule, now_utc) do
    offset = Map.get(schedule, "timezone_offset_minutes", 0)
    local_now = DateTime.add(now_utc, offset * 60, :second)

    case current_window(schedule, local_now) do
      {:open, window_end_local} ->
        window_end_utc = DateTime.add(window_end_local, -offset * 60, :second)

        %{
          open: true,
          next_state: :closed,
          changes_at: window_end_utc,
          seconds_until_change: DateTime.diff(window_end_utc, now_utc, :second)
        }

      :closed ->
        case next_open_moment(schedule, local_now) do
          nil ->
            %{open: false, next_state: :none, changes_at: nil, seconds_until_change: nil}

          next_open_local ->
            next_open_utc = DateTime.add(next_open_local, -offset * 60, :second)

            %{
              open: false,
              next_state: :open,
              changes_at: next_open_utc,
              seconds_until_change: DateTime.diff(next_open_utc, now_utc, :second)
            }
        end
    end
  end

  defp current_window(schedule, local_now) do
    day_key = weekday_key(local_now)
    windows = Map.get(schedule, day_key, [])
    today_minutes = local_now.hour * 60 + local_now.minute

    hit =
      Enum.find(windows, fn %{"start" => s, "end" => e} ->
        today_minutes >= to_minutes(s) and today_minutes < to_minutes(e)
      end)

    case hit do
      nil ->
        :closed

      %{"end" => e} ->
        {h, m} = split_hm(e)
        {:open, %{local_now | hour: h, minute: m, second: 0, microsecond: {0, 0}}}
    end
  end

  # Scan today's remaining windows, then each of the next 6 days, for the
  # earliest future opening moment.
  defp next_open_moment(schedule, local_now) do
    0..7
    |> Enum.find_value(fn day_offset ->
      day = DateTime.add(local_now, day_offset * 86_400, :second)
      day_key = weekday_key(day)
      windows = Map.get(schedule, day_key, [])

      windows
      |> Enum.map(fn %{"start" => s} ->
        {h, m} = split_hm(s)
        %{day | hour: h, minute: m, second: 0, microsecond: {0, 0}}
      end)
      |> Enum.sort({:asc, DateTime})
      |> Enum.find(fn candidate -> DateTime.compare(candidate, local_now) == :gt end)
    end)
  end

  defp weekday_key(dt) do
    Enum.at(@weekdays, Date.day_of_week(dt) - 1) |> Atom.to_string()
  end

  defp to_minutes(hh_mm) do
    {h, m} = split_hm(hh_mm)
    h * 60 + m
  end

  defp split_hm(hh_mm) do
    [h, m] = String.split(hh_mm, ":")
    {String.to_integer(h), String.to_integer(m)}
  end

  defp schedule_file do
    dir = Application.get_env(:pantheon_core, :snapshot_dir, Path.expand("./data/snapshots"))
    Path.join(Path.dirname(dir), "operating_hours.json")
  end

  defp persist_to_disk(schedule) do
    path = schedule_file()
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode!(schedule, pretty: true))
  end

  defp load_from_disk do
    case File.read(schedule_file()) do
      {:ok, body} ->
        case Jason.decode(body) do
          {:ok, map} -> map
          _ -> nil
        end

      _ ->
        nil
    end
  end
end
