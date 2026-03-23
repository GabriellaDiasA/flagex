defmodule FlagexTest do
  use Flagex.DataCase, async: false

  alias Flagex.{Variable, VariableEvent}

  setup do
    start_supervised!(Flagex.Store)
    :ok
  end

  defp insert_variable(attrs \\ %{}) do
    defaults = %{name: "my_var", value: "on", enabled: true}

    %Variable{}
    |> Variable.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  describe "get/1" do
    test "returns nil when variable is not in store" do
      assert Flagex.get(:my_var) == nil
      assert Flagex.get("my_var") == nil
    end

    test "returns value when variable is loaded in store" do
      Flagex.Store.put("my_var", "hello")
      assert Flagex.get(:my_var) == "hello"
      assert Flagex.get("my_var") == "hello"
    end
  end

  describe "fetch/1" do
    test "returns {:error, :not_found} when absent from store" do
      assert Flagex.fetch(:my_var) == {:error, :not_found}
    end

    test "returns {:ok, value} when present" do
      Flagex.Store.put("my_var", "hello")
      assert Flagex.fetch(:my_var) == {:ok, "hello"}
    end

    test "returns {:ok, nil} for variable with nil value, not :not_found" do
      Flagex.Store.put("my_var", nil)
      assert Flagex.fetch(:my_var) == {:ok, nil}
    end

    test "accepts string key" do
      Flagex.Store.put("my_var", "hello")
      assert Flagex.fetch("my_var") == {:ok, "hello"}
    end
  end

  describe "put/2" do
    test "updates value in database" do
      var = insert_variable()
      assert {:ok, updated} = Flagex.put("my_var", "new_value")
      assert updated.value == "new_value"
      assert Repo.get!(Variable, var.id).value == "new_value"
    end

    test "records an :update event" do
      insert_variable()
      Flagex.put("my_var", "new_value")
      event = Repo.get_by!(VariableEvent, variable_name: "my_var", operation: :update)
      assert event.value == "new_value"
    end

    test "returns {:error, :not_found} for unknown variable" do
      assert Flagex.put("unknown", "value") == {:error, :not_found}
    end

    test "returns {:error, :variable_disabled} for disabled variable" do
      insert_variable()
      Flagex.disable("my_var")
      assert {:error, :variable_disabled} = Flagex.put("my_var", "new")
    end
  end

  describe "update/2" do
    test "updates both value and description atomically" do
      insert_variable()
      assert {:ok, updated} = Flagex.update("my_var", %{value: "new", description: "desc"})
      assert updated.value == "new"
      assert updated.description == "desc"
    end

    test "returns current variable unchanged when attrs produce no changes" do
      insert_variable(%{value: "on"})
      assert {:ok, var} = Flagex.update("my_var", %{value: "on"})
      assert var.value == "on"

      refute Repo.exists?(
               from(e in VariableEvent,
                 where: e.variable_name == "my_var" and e.operation == :update
               )
             )
    end

    test "returns {:error, :not_found} for unknown variable" do
      assert Flagex.update("unknown", %{value: "x"}) == {:error, :not_found}
    end

    test "returns {:error, :variable_disabled} for disabled variable" do
      insert_variable()
      Flagex.disable("my_var")
      assert {:error, :variable_disabled} = Flagex.update("my_var", %{value: "new", description: "desc"})
    end
  end

  describe "disable/1" do
    test "sets enabled to false" do
      insert_variable()
      assert {:ok, disabled} = Flagex.disable("my_var")
      refute disabled.enabled
      refute Repo.get_by!(Variable, name: "my_var").enabled
    end

    test "records a :disable event with the current value" do
      insert_variable(%{value: "on"})
      Flagex.disable("my_var")
      event = Repo.get_by!(VariableEvent, variable_name: "my_var", operation: :disable)
      assert event.value == "on"
    end

    test "returns error when already disabled" do
      insert_variable()
      Flagex.disable("my_var")
      assert {:ok, :already_disabled} = Flagex.disable("my_var")
    end

    test "returns {:error, :not_found} for unknown variable" do
      assert Flagex.disable("unknown") == {:error, :not_found}
    end
  end

  describe "reenable/1" do
    test "sets enabled to true" do
      insert_variable()
      Flagex.disable("my_var")
      assert {:ok, reenabled} = Flagex.reenable("my_var")
      assert reenabled.enabled
    end

    test "records a :reenable event with the current value" do
      insert_variable()
      Flagex.disable("my_var")
      Flagex.reenable("my_var")
      event = Repo.get_by!(VariableEvent, variable_name: "my_var", operation: :reenable)
      assert event.value == "on"
    end

    test "returns {:ok, :already_enabled} when already enabled" do
      insert_variable()
      assert {:ok, :already_enabled} = Flagex.reenable("my_var")
    end
  end

  describe "all/0" do
    test "returns only enabled variables" do
      insert_variable(%{name: "enabled_var", enabled: true})
      insert_variable(%{name: "disabled_var"})
      Flagex.disable("disabled_var")
      names = Flagex.all() |> Enum.map(& &1.name)
      assert "enabled_var" in names
      refute "disabled_var" in names
    end

    test "returns empty list when no enabled variables exist" do
      assert Flagex.all() == []
    end
  end
end
