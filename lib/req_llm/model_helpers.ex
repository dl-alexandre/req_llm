defmodule ReqLLM.ModelHelpers do
  @moduledoc """
  Helper functions for querying LLMDB.Model capabilities.

  Defines helper functions for common capability checks, centralizing knowledge
  of the model capability structure.

  These helpers ensure consistency when checking model capabilities across the codebase
  and provide a single source of truth for capability access patterns.
  """

  # Define helper functions for common capability checks
  # Pattern: capabilities.category.field
  @capability_checks [
    # Reasoning capability
    {:reasoning_enabled?, [:reasoning, :enabled]},

    # JSON capabilities
    {:json_native?, [:json, :native]},
    {:json_schema?, [:json, :schema]},
    {:json_strict?, [:json, :strict]},

    # Tool capabilities
    {:tools_enabled?, [:tools, :enabled]},
    {:tools_strict?, [:tools, :strict]},
    {:tools_parallel?, [:tools, :parallel]},
    {:tools_streaming?, [:tools, :streaming]},

    # Streaming capabilities
    {:streaming_text?, [:streaming, :text]},
    {:streaming_tool_calls?, [:streaming, :tool_calls]},

    # Chat capability (direct boolean)
    {:chat?, [:chat]}
  ]

  for {function_name, path} <- @capability_checks do
    path_str = Enum.map_join(path, ".", &to_string/1)
    example_path = Enum.map_join(path, ": %{", fn key -> "#{key}" end)
    example_close = String.duplicate("}", length(path) - 1)

    @doc """
    Check if model has `#{path_str}` capability.

    Returns `true` if `model.capabilities.#{path_str}` is `true`.

    ## Examples

        iex> model = %LLMDB.Model{capabilities: %{#{example_path}: true#{example_close}}}
        iex> ReqLLM.ModelHelpers.#{function_name}(model)
        true

        iex> model = %LLMDB.Model{capabilities: %{}}
        iex> ReqLLM.ModelHelpers.#{function_name}(model)
        false
    """
    def unquote(function_name)(%LLMDB.Model{} = model) do
      get_in(model.capabilities, unquote(path)) == true
    end

    def unquote(function_name)(_), do: false
  end

  @doc """
  List all available capability helper functions.

  Useful for debugging and understanding what capabilities can be queried.

  ## Examples

      iex> ReqLLM.ModelHelpers.list_helpers()
      [:chat?, :json_native?, :json_schema?, :json_strict?, :reasoning_enabled?, ...]
  """
  def list_helpers do
    @capability_checks
    |> Enum.map(fn {name, _path} -> name end)
    |> Enum.sort()
  end

  @doc """
  Check if the model supports only "adaptive" thinking (certain Claude "thinking-only" models
  like Mythos Preview) and does not support the standard "enabled" thinking type (explicitly false).

  Used to select the correct `type: "adaptive"` form (with display summarized) on platforms
  like Azure/Bedrock/Vertex, and to decide auto-injection in no-param fallback for models
  that only support the adaptive form.

  ## Examples

      iex> model = %LLMDB.Model{extra: %{"capabilities" => %{"thinking" => %{"types" => %{"adaptive" => %{"supported" => true}, "enabled" => %{"supported" => false}}}}}}
      iex> ReqLLM.ModelHelpers.adaptive_thinking_required?(model)
      true
  """
  def adaptive_thinking_required?(%LLMDB.Model{} = model) do
    extra = model.extra || %{}

    adaptive_supported =
      get_in(extra, ["capabilities", "thinking", "types", "adaptive", "supported"]) == true

    enabled_supported =
      get_in(extra, ["capabilities", "thinking", "types", "enabled", "supported"])

    adaptive_supported and enabled_supported == false
  end

  def adaptive_thinking_required?(_), do: false
end
