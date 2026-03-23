defmodule Flagex.VariablesTest do
  use ExUnit.Case, async: true

  defmodule SampleVariables do
    use Flagex.Variables

    variable(:first_var, default: "on", description: "The first variable")
    variable(:second_var, default: "off")
    variable(:third_var)
  end

  describe "__flagex_variables__/0" do
    test "returns declared variables in declaration order" do
      assert SampleVariables.__flagex_variables__() == [
               {:first_var, [default: "on", description: "The first variable"]},
               {:second_var, [default: "off"]},
               {:third_var, []}
             ]
    end

    test "atoms are accessible via String.to_existing_atom/1 after module load" do
      for name <- [:first_var, :second_var, :third_var] do
        assert String.to_existing_atom(Atom.to_string(name)) == name
      end
    end
  end

  describe "variable/2 compile-time guard" do
    test "raises on non-atom name" do
      assert_raise FunctionClauseError, fn ->
        defmodule BadVariables do
          use Flagex.Variables
          variable("string_name")
        end
      end
    end
  end
end
