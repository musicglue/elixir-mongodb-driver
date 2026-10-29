defmodule Mongo.TopologyDescriptionTest do
  use ExUnit.Case, async: true
  alias Mongo.{ReadPreference, TopologyDescription}
  import Mongo.TopologyTestData

  test "single server selection" do
    single_server = "localhost:27017"

    opts = [
      read_preference: ReadPreference.primary(%{mode: :secondary})
    ]

    assert {:ok, {^single_server, _}} = TopologyDescription.select_servers(single(), :read, opts)

    assert {:ok, {^single_server, _}} = TopologyDescription.select_servers(single(), :write)

    opts = [
      read_preference: ReadPreference.primary(%{mode: :nearest})
    ]

    assert {:ok, {^single_server, _}} = TopologyDescription.select_servers(single(), :read, opts)
  end

  test "shared server selection" do
    sharded_server = "localhost:27017"

    assert {:ok, {^sharded_server, []}} = TopologyDescription.select_servers(sharded(), :write, [])

    opts = [
      read_preference: ReadPreference.primary(%{mode: :primary})
    ]

    assert {:ok, {^sharded_server, []}} = TopologyDescription.select_servers(sharded(), :read, opts)

    opts = [
      read_preference: ReadPreference.primary(%{mode: :secondary})
    ]

    assert {:ok, {^sharded_server, [{:read_preference, [mode: :secondary, tag_sets: [], maxStalenessSeconds: 0]}]}} = TopologyDescription.select_servers(sharded(), :read, opts)

    opts = [
      read_preference: ReadPreference.primary(%{mode: :primary_preferred})
    ]

    assert {:ok, {^sharded_server, [{:read_preference, [mode: :primaryPreferred, tag_sets: [], maxStalenessSeconds: 0]}]}} = TopologyDescription.select_servers(sharded(), :read, opts)

    opts = [
      read_preference: ReadPreference.primary(%{mode: :secondary_preferred})
    ]

    assert {:ok, {^sharded_server, [{:read_preference, [mode: :secondaryPreferred, tag_sets: [], maxStalenessSeconds: 0]}]}} = TopologyDescription.select_servers(sharded(), :read, opts)

    opts = [
      read_preference: ReadPreference.primary(%{mode: :nearest})
    ]

    assert {:ok, {^sharded_server, [{:read_preference, [mode: :nearest, tag_sets: [], maxStalenessSeconds: 0]}]}} = TopologyDescription.select_servers(sharded(), :read, opts)
  end

  test "replica set server selection" do
    all_hosts = ["localhost:27018", "localhost:27019", "localhost:27020"]
    master = "localhost:27018"
    seconardaries = List.delete(all_hosts, master)

    opts = [
      read_preference: ReadPreference.primary(%{mode: :secondary})
    ]

    {:ok, {server, _}} = TopologyDescription.select_servers(repl_set_with_master(), :read, opts)

    assert Enum.any?(seconardaries, fn sec -> sec == server end)

    opts = [
      read_preference: ReadPreference.primary(%{mode: :primary})
    ]

    assert {:ok, {_master, _}} = TopologyDescription.select_servers(repl_set_with_master(), :read, opts)

    opts = [
      read_preference: ReadPreference.primary(%{mode: :primary_preferred})
    ]

    assert {:ok, {_master, _}} = TopologyDescription.select_servers(repl_set_with_master(), :read, opts)

    opts = [
      read_preference: ReadPreference.primary(%{mode: :primary_preferred})
    ]

    {:ok, {server, _}} = TopologyDescription.select_servers(repl_set_no_master(), :read, opts)
    assert Enum.any?(seconardaries, fn sec -> sec == server end)

    opts = [
      read_preference: ReadPreference.primary(%{mode: :nearest})
    ]

    {:ok, {server, _}} = TopologyDescription.select_servers(repl_set_with_master(), :read, opts)
    assert Enum.any?(all_hosts, fn sec -> sec == server end)

    opts = [
      read_preference: ReadPreference.primary(%{mode: :secondary})
    ]

    {:ok, {server, _}} = TopologyDescription.select_servers(repl_set_no_master(), :read, opts)
    assert Enum.any?(seconardaries, fn sec -> sec == server end)

    opts = [
      read_preference: ReadPreference.primary(%{mode: :secondary_preferred})
    ]

    {:ok, {server, _}} = TopologyDescription.select_servers(repl_set_with_master(), :read, opts)
    assert Enum.any?(seconardaries, fn sec -> sec == server end)

    assert {:ok, {^master, _}} = TopologyDescription.select_servers(repl_set_only_master(), :read, opts)

    {:ok, {server, _}} = TopologyDescription.select_servers(repl_set_no_master(), :read, opts)
    assert Enum.any?(seconardaries, fn sec -> sec == server end)

    opts = [
      read_preference: ReadPreference.primary(%{mode: :nearest})
    ]

    {:ok, {server, _}} = TopologyDescription.select_servers(repl_set_no_master(), :read, opts)
    assert Enum.any?(all_hosts, fn sec -> sec == server end)
  end

  test "a primary reporting :rs_other drops the topology to :replica_set_no_primary" do
    # A stepping-down primary answers hello with neither isWritablePrimary nor
    # secondary set, so it is typed :rs_other. The topology type has to follow,
    # otherwise it claims a primary that is no longer in the servers map.
    topology = repl_set_with_master()
    stepping_down = %{topology.servers["localhost:27018"] | type: :rs_other}

    {_actions, topology} = TopologyDescription.update(topology, stepping_down, 3)

    assert topology.type == :replica_set_no_primary
  end

  test "maxStaleness still rejects a lagging secondary when the claimed primary is missing" do
    now = DateTime.utc_now()

    topology =
      repl_set_with_master()
      |> Map.put(:heartbeat_frequency_ms, 10_000)
      |> put_in([:servers, "localhost:27018", :type], :rs_other)
      |> put_in([:servers, "localhost:27019", :last_write_date], now)
      |> put_in([:servers, "localhost:27020", :last_write_date], DateTime.add(now, -200, :second))

    opts = [
      read_preference: ReadPreference.primary(%{mode: :secondary_preferred, max_staleness_ms: 90_000})
    ]

    selected =
      for _ <- 1..50 do
        {:ok, {server, _}} = TopologyDescription.select_servers(topology, :read, opts)
        server
      end

    assert Enum.uniq(selected) == ["localhost:27019"]
  end

  test "Simplified server selection" do
    single_server = "localhost:27017"

    opts = [
      read_preference: %{mode: :secondary}
    ]

    assert {:ok, {^single_server, _}} = TopologyDescription.select_servers(single(), :read, opts)
  end
end
