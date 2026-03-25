defmodule Flagex.VariableTest do
  use ExUnit.Case, async: true

  alias Flagex.Variable

  describe "changeset/2" do
    test "valid with name only" do
      assert %{valid?: true} = Variable.changeset(%Variable{}, %{name: "my_var"})
    end

    test "valid with all fields" do
      changeset =
        Variable.changeset(%Variable{}, %{name: "my_var", value: "on", description: "desc"})

      assert changeset.valid?
    end

    test "requires name" do
      changeset = Variable.changeset(%Variable{}, %{})
      assert "can't be blank" in errors_on(changeset).name
    end

    test "rejects name too long" do
      changeset = Variable.changeset(%Variable{}, %{name: String.duplicate("a", 256)})
      assert "should be at most 255 character(s)" in errors_on(changeset).name
    end

    test "rejects name starting with a digit" do
      changeset = Variable.changeset(%Variable{}, %{name: "1invalid"})
      assert errors_on(changeset).name != []
    end

    test "rejects name with invalid characters" do
      changeset = Variable.changeset(%Variable{}, %{name: "invalid-name"})
      assert errors_on(changeset).name != []
    end

    test "accepts name with uppercase, digits, underscores, and @" do
      for name <- ["MyVar", "my_var", "myVar2", "_var", "my@var"] do
        assert %{valid?: true} = Variable.changeset(%Variable{}, %{name: name})
      end
    end

    test "value defaults to nil" do
      changeset = Variable.changeset(%Variable{}, %{name: "my_var"})
      assert Ecto.Changeset.get_field(changeset, :value) == nil
    end

    test "enabled defaults to true" do
      changeset = Variable.changeset(%Variable{}, %{name: "my_var"})
      assert Ecto.Changeset.get_field(changeset, :enabled) == true
    end

    test "ignores enabled field passed by caller" do
      changeset = Variable.changeset(%Variable{}, %{name: "my_var", enabled: false})
      assert Ecto.Changeset.get_field(changeset, :enabled) == true
      assert Map.get(changeset.changes, :enabled) == nil
    end
  end

  describe "update_changeset/2" do
    test "allows updating value and description on enabled variable" do
      variable = %Variable{id: "some-id", name: "my_var", value: "old", enabled: true}
      changeset = Variable.update_changeset(variable, %{value: "new", description: "desc"})
      assert changeset.valid?
      assert changeset.changes == %{value: "new", description: "desc"}
    end

    test "blocks updates on disabled variable" do
      variable = %Variable{id: "some-id", name: "my_var", value: "old", enabled: false}
      changeset = Variable.update_changeset(variable, %{value: "new"})
      refute changeset.valid?
      assert "variable is disabled and cannot be updated" in errors_on(changeset).enabled
    end

    test "does not allow changing enabled through update_changeset" do
      variable = %Variable{id: "some-id", name: "my_var", enabled: true}
      changeset = Variable.update_changeset(variable, %{enabled: false})
      assert changeset.changes == %{}
    end
  end

  describe "disable_changeset/1" do
    test "sets enabled to false" do
      variable = %Variable{id: "some-id", name: "my_var", enabled: true}
      changeset = Variable.disable_changeset(variable)
      assert changeset.valid?
      assert changeset.changes == %{enabled: false}
    end

    test "returns error when already disabled" do
      variable = %Variable{id: "some-id", name: "my_var", enabled: false}
      changeset = Variable.disable_changeset(variable)
      refute changeset.valid?
      assert "variable is already disabled" in errors_on(changeset).enabled
    end
  end

  describe "reenable_changeset/1" do
    test "sets enabled to true" do
      variable = %Variable{id: "some-id", name: "my_var", enabled: false}
      changeset = Variable.reenable_changeset(variable)
      assert changeset.valid?
      assert changeset.changes == %{enabled: true}
    end

    test "returns error when already enabled" do
      variable = %Variable{id: "some-id", name: "my_var", enabled: true}
      changeset = Variable.reenable_changeset(variable)
      refute changeset.valid?
      assert "variable is already enabled" in errors_on(changeset).enabled
    end
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
