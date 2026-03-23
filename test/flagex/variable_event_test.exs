defmodule Flagex.VariableEventTest do
  use ExUnit.Case, async: true

  alias Flagex.VariableEvent

  @valid_attrs %{
    variable_name: "my_var",
    operation: :create,
    value: "on",
    changed_at: DateTime.utc_now()
  }

  describe "changeset/2" do
    test "valid with required fields" do
      assert %{valid?: true} = VariableEvent.changeset(%VariableEvent{}, @valid_attrs)
    end

    test "valid without optional fields" do
      attrs = Map.take(@valid_attrs, [:variable_name, :operation, :changed_at])
      assert %{valid?: true} = VariableEvent.changeset(%VariableEvent{}, attrs)
    end

    test "requires variable_name" do
      attrs = Map.delete(@valid_attrs, :variable_name)
      changeset = VariableEvent.changeset(%VariableEvent{}, attrs)
      assert "can't be blank" in errors_on(changeset).variable_name
    end

    test "requires operation" do
      attrs = Map.delete(@valid_attrs, :operation)
      changeset = VariableEvent.changeset(%VariableEvent{}, attrs)
      assert "can't be blank" in errors_on(changeset).operation
    end

    test "requires changed_at" do
      attrs = Map.delete(@valid_attrs, :changed_at)
      changeset = VariableEvent.changeset(%VariableEvent{}, attrs)
      assert "can't be blank" in errors_on(changeset).changed_at
    end

    test "accepts all valid operations" do
      for op <- [:create, :update, :disable, :reenable] do
        attrs = Map.put(@valid_attrs, :operation, op)
        assert %{valid?: true} = VariableEvent.changeset(%VariableEvent{}, attrs)
      end
    end

    test "rejects invalid operation" do
      attrs = Map.put(@valid_attrs, :operation, :invalid)
      changeset = VariableEvent.changeset(%VariableEvent{}, attrs)
      refute changeset.valid?
    end

    test "allows nil value" do
      attrs = Map.put(@valid_attrs, :value, nil)
      assert %{valid?: true} = VariableEvent.changeset(%VariableEvent{}, attrs)
    end

    test "allows nil variable_id (FK may be null after parent deletion)" do
      attrs = Map.put(@valid_attrs, :variable_id, nil)
      assert %{valid?: true} = VariableEvent.changeset(%VariableEvent{}, attrs)
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
