defmodule Nebulex.Adapters.DistTest do
  use Nebulex.NodeCase
  use Nebulex.CacheTest, cache: Nebulex.TestCache.Dist

  alias Nebulex.TestCache.Dist
  alias Nebulex.TestCache.DistLocal, as: Local

  @primary :"primary@127.0.0.1"
  @cluster :lists.usort([@primary | Application.get_env(:nebulex, :nodes, [])])

  setup do
    {:ok, local} = Local.start_link
    {:ok, dist} = Dist.start_link
    node_pid_list = start_caches(Node.list(), [Local, Dist])
    :ok

    on_exit fn ->
      _ = :timer.sleep(100)
      if Process.alive?(local), do: Local.stop(local, 1)
      if Process.alive?(dist), do: Dist.stop(dist, 1)
      stop_caches(node_pid_list)
    end
  end

  test "fail on __before_compile__ because missing local cache" do
    assert_raise ArgumentError, ~r"missing :local configuration", fn ->
      defmodule WrongDist do
        use Nebulex.Cache, otp_app: :nebulex, adapter: Nebulex.Adapters.Dist
      end
    end
  end

  test "check cluster nodes" do
    assert @primary == node()
    assert @cluster -- [node()] == :lists.usort(Node.list())
    assert @cluster == Dist.nodes()
  end

  test "get_and_update" do
    assert {nil, 1} == Dist.get_and_update(1, &Dist.get_and_update_fun/1)
    assert {1, 2} == Dist.get_and_update(1, &Dist.get_and_update_fun/1)
    assert {2, 4} == Dist.get_and_update(1, &Dist.get_and_update_fun/1)

    {4, %Object{key: 1, value: 8, ttl: _, version: _}} =
      Dist.get_and_update(1, &Dist.get_and_update_fun/1, return: :object)

    assert_raise ArgumentError, fn ->
      Dist.get_and_update(1, &Dist.wrong_get_and_update_fun/1)
    end

    assert_raise Nebulex.VersionConflictError, fn ->
      1
      |> Dist.set(1, return: :key)
      |> Dist.get_and_update(&Dist.get_and_update_fun/1, version: -1)
    end
  end
end
