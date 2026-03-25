defmodule Flagex.Migrations do
  @moduledoc """
  Ecto migrations for Flagex tables.

  Intended to be called from within your own application migrations so that
  Flagex schema changes live in your migration history and run alongside your
  other migrations.

  ## Usage

  Generate a migration in your application:

      mix ecto.gen.migration add_flagex

  Then call `up/0` and `down/0` from it:

      defmodule MyApp.Repo.Migrations.AddFlagex do
        use Ecto.Migration

        def up, do: Flagex.Migrations.up()
        def down, do: Flagex.Migrations.down()
      end

  Run your migrations as usual:

      mix ecto.migrate

  """

  use Ecto.Migration

  @doc """
  Creates the Flagex tables, indexes, trigger function, and trigger.
  """
  def up do
    create_if_not_exists table(:flagex_variables, primary_key: false) do
      add(:id, :uuid, primary_key: true, default: fragment("gen_random_uuid()"))
      add(:name, :text, null: false)
      add(:value, :text)
      add(:description, :text)
      add(:enabled, :boolean, null: false, default: true)

      timestamps(type: :utc_datetime_usec)
    end

    create_if_not_exists(unique_index(:flagex_variables, [:name]))

    create_if_not_exists table(:flagex_variable_events, primary_key: false) do
      add(:id, :uuid, primary_key: true, default: fragment("gen_random_uuid()"))
      add(:variable_id, references(:flagex_variables, type: :uuid, on_delete: :nilify_all))
      add(:variable_name, :text, null: false)
      add(:operation, :text, null: false)
      add(:value, :text)
      add(:changed_by, :text)
      add(:changed_at, :utc_datetime_usec, null: false)
    end

    drop_if_exists(constraint("flagex_variable_events", "operation_check"))

    create(
      constraint("flagex_variable_events", "operation_check",
        check: "operation IN ('CREATE', 'UPDATE', 'DISABLE', 'REENABLE')"
      )
    )

    create_if_not_exists(index(:flagex_variable_events, [:variable_name]))
    create_if_not_exists(index(:flagex_variable_events, [:variable_id]))
    create_if_not_exists(index(:flagex_variable_events, [:changed_at]))
    create_if_not_exists(index(:flagex_variable_events, [:operation]))

    execute(
      """
      CREATE OR REPLACE FUNCTION flagex_notify() RETURNS trigger AS $$
      BEGIN
        PERFORM pg_notify(
          'flagex',
          json_build_object(
            'op',      TG_OP,
            'name',    NEW.name,
            'value',   NEW.value,
            'enabled', NEW.enabled
          )::text
        );
        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;
      """,
      "DROP FUNCTION IF EXISTS flagex_notify();"
    )

    execute("DROP TRIGGER IF EXISTS flagex_variable_changed ON flagex_variables;")

    execute(
      """
      CREATE TRIGGER flagex_variable_changed
        AFTER INSERT OR UPDATE ON flagex_variables
        FOR EACH ROW EXECUTE FUNCTION flagex_notify();
      """,
      "DROP TRIGGER IF EXISTS flagex_variable_changed ON flagex_variables;"
    )
  end

  @doc """
  Drops the Flagex trigger, trigger function, indexes, and tables.
  """
  def down do
    execute("DROP TRIGGER IF EXISTS flagex_variable_changed ON flagex_variables;")
    execute("DROP FUNCTION IF EXISTS flagex_notify();")

    drop_if_exists(constraint("flagex_variable_events", "operation_check"))

    drop_if_exists(index(:flagex_variable_events, [:operation]))
    drop_if_exists(index(:flagex_variable_events, [:changed_at]))
    drop_if_exists(index(:flagex_variable_events, [:variable_id]))
    drop_if_exists(index(:flagex_variable_events, [:variable_name]))
    drop_if_exists(table(:flagex_variable_events))

    drop_if_exists(index(:flagex_variables, [:name]))
    drop_if_exists(table(:flagex_variables))
  end
end
