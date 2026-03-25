defmodule Flagex.VariableEvent do
  use Ecto.Schema
  import Ecto.Changeset

  @type operation :: :create | :update | :disable | :reenable

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          variable_id: Ecto.UUID.t() | nil,
          variable_name: String.t(),
          operation: operation(),
          value: String.t() | nil,
          changed_by: String.t() | nil,
          changed_at: DateTime.t()
        }

  @primary_key {:id, Ecto.UUID, autogenerate: true}

  schema "flagex_variable_events" do
    field(:variable_name, :string)

    field(:operation, Ecto.Enum,
      values: [create: "CREATE", update: "UPDATE", disable: "DISABLE", reenable: "REENABLE"]
    )

    field(:value, :string)
    field(:changed_by, :string)
    field(:changed_at, :utc_datetime_usec)

    belongs_to(:variable, Flagex.Variable, type: Ecto.UUID, foreign_key: :variable_id)
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [:variable_id, :variable_name, :operation, :value, :changed_by, :changed_at])
    |> validate_required([:variable_name, :operation, :changed_at])
  end
end
