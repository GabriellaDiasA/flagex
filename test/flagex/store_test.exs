defmodule Flagex.StoreTest do
  use ExUnit.Case, async: false

  alias Flagex.Store

  setup do
    start_supervised!(Store)
    :ok
  end

  describe "get/1" do
    test "returns nil for unknown key" do
      assert Store.get("unknown") == nil
    end

    test "returns value after put" do
      Store.put("my_var", "hello")
      assert Store.get("my_var") == "hello"
    end

    test "returns nil for a nil value" do
      Store.put("my_var", nil)
      assert Store.get("my_var") == nil
    end
  end

  describe "fetch/1" do
    test "returns {:error, :not_found} for unknown key" do
      assert Store.fetch("unknown") == {:error, :not_found}
    end

    test "returns {:ok, value} after put" do
      Store.put("my_var", "hello")
      assert Store.fetch("my_var") == {:ok, "hello"}
    end

    test "returns {:ok, nil} for a key with nil value, distinguishing from absent" do
      Store.put("my_var", nil)
      assert Store.fetch("my_var") == {:ok, nil}
    end
  end

  describe "put/2" do
    test "overwrites existing value" do
      Store.put("my_var", "first")
      Store.put("my_var", "second")
      assert Store.get("my_var") == "second"
    end
  end

  describe "delete/1" do
    test "removes key from store" do
      Store.put("my_var", "hello")
      Store.delete("my_var")
      assert Store.get("my_var") == nil
    end

    test "is a no-op for unknown key" do
      assert Store.delete("unknown") == :ok
    end
  end

  describe "load/1" do
    test "bulk inserts entries" do
      Store.load([{"foo", "1"}, {"bar", "2"}])
      assert Store.get("foo") == "1"
      assert Store.get("bar") == "2"
    end

    test "overwrites existing entries" do
      Store.put("foo", "old")
      Store.load([{"foo", "new"}])
      assert Store.get("foo") == "new"
    end

    test "accepts empty list" do
      assert Store.load([]) == :ok
    end
  end

  describe "all/0" do
    test "returns empty list when store is empty" do
      assert Store.all() == []
    end

    test "returns all entries as {name, value} tuples" do
      Store.load([{"a", "1"}, {"b", "2"}])
      entries = Store.all()
      assert length(entries) == 2
      assert {"a", "1"} in entries
      assert {"b", "2"} in entries
    end
  end
end
