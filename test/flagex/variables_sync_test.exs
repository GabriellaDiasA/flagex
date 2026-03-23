defmodule Flagex.VariablesSyncTest do
  use Flagex.DataCase, async: false

  alias Flagex.{Variable, VariableEvent}

  defmodule SyncVars do
    use Flagex.Variables

    variable(:sync_var_a, default: "alpha", description: "First sync var")
    variable(:sync_var_b, default: "beta")
    variable(:sync_var_c)
  end

  describe "sync/2" do
    test "inserts all declared variables on first run" do
      assert :ok = Flagex.Variables.sync(SyncVars, Repo)

      assert Repo.get_by(Variable, name: "sync_var_a")
      assert Repo.get_by(Variable, name: "sync_var_b")
      assert Repo.get_by(Variable, name: "sync_var_c")
    end

    test "sets the default value on first insert" do
      :ok = Flagex.Variables.sync(SyncVars, Repo)

      var_a = Repo.get_by!(Variable, name: "sync_var_a")
      var_b = Repo.get_by!(Variable, name: "sync_var_b")
      var_c = Repo.get_by!(Variable, name: "sync_var_c")

      assert var_a.value == "alpha"
      assert var_b.value == "beta"
      assert var_c.value == nil
    end

    test "sets description on first insert" do
      :ok = Flagex.Variables.sync(SyncVars, Repo)

      var_a = Repo.get_by!(Variable, name: "sync_var_a")
      assert var_a.description == "First sync var"
    end

    test "records a :create event for each newly inserted variable" do
      :ok = Flagex.Variables.sync(SyncVars, Repo)

      for name <- ["sync_var_a", "sync_var_b", "sync_var_c"] do
        event = Repo.get_by!(VariableEvent, variable_name: name, operation: :create)
        var = Repo.get_by!(Variable, name: name)
        assert event.variable_id == var.id
        assert event.value == var.value
      end
    end

    test "does not overwrite a variable that already exists" do
      :ok = Flagex.Variables.sync(SyncVars, Repo)

      var = Repo.get_by!(Variable, name: "sync_var_a")
      var |> Ecto.Changeset.change(value: "runtime_override") |> Repo.update!()

      :ok = Flagex.Variables.sync(SyncVars, Repo)

      assert Repo.get_by!(Variable, name: "sync_var_a").value == "runtime_override"
    end

    test "does not emit a :create event for variables that already exist" do
      :ok = Flagex.Variables.sync(SyncVars, Repo)
      :ok = Flagex.Variables.sync(SyncVars, Repo)

      count =
        Repo.aggregate(
          from(e in VariableEvent,
            where: e.variable_name == "sync_var_a" and e.operation == :create
          ),
          :count
        )

      assert count == 1
    end

    test "is idempotent — running twice does not duplicate rows" do
      :ok = Flagex.Variables.sync(SyncVars, Repo)
      :ok = Flagex.Variables.sync(SyncVars, Repo)

      count = Repo.aggregate(from(v in Variable, where: v.name == "sync_var_a"), :count)
      assert count == 1
    end
  end
end
