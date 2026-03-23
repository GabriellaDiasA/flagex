defmodule Flagex.Variable do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          name: String.t(),
          value: String.t() | nil,
          description: String.t() | nil,
          enabled: boolean(),
          events: list(Flagex.VariableEvent.t()) | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @primary_key {:id, Ecto.UUID, autogenerate: true}

  schema "flagex_variables" do
    field(:name, :string)
    field(:value, :string)
    field(:description, :string)
    field(:enabled, :boolean, default: true)

    has_many(:events, Flagex.VariableEvent, foreign_key: :variable_id)

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(variable, attrs) do
    variable
    |> cast(attrs, [:name, :value, :description])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 255)
    |> validate_format(:name, ~r/^[a-zA-Z_][a-zA-Z0-9@_]*$/,
      message: "must be a valid atom name according to erlang specifications."
    )
    |> unique_constraint(:name)
  end

  def update_changeset(%__MODULE__{enabled: false} = variable, _attrs) do
    variable
    |> change()
    |> add_error(:enabled, "variable is disabled and cannot be updated")
  end

  def update_changeset(variable, attrs) do
    variable
    |> cast(attrs, [:value, :description])
  end

  def disable_changeset(%__MODULE__{enabled: false} = variable) do
    variable
    |> change()
    |> add_error(:enabled, "variable is already disabled")
  end

  def disable_changeset(variable) do
    variable
    |> change(enabled: false)
  end

  def reenable_changeset(%__MODULE__{enabled: true} = variable) do
    variable
    |> change()
    |> add_error(:enabled, "variable is already enabled")
  end

  def reenable_changeset(variable) do
    variable
    |> change(enabled: true)
  end
end
