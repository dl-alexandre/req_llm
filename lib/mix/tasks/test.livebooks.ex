defmodule Mix.Tasks.Test.Livebooks do
  @moduledoc """
  Tests livebook files by extracting and executing Elixir code blocks.

  This task finds all `*.livemd` files in the guides directory, extracts
  Elixir code blocks, and executes them to verify they run without errors.

  ## Usage

      mix test.livebooks

  ## Options

      --verbose    Print detailed output for each livebook
      --path       Specify custom path to search for livebooks (default: guides/)

  ## Exit Codes

  - 0: All livebooks passed
  - 1: One or more livebooks failed

  ## Limitations

  This task executes code blocks sequentially and does not support:
  - Kino UI interactions (inputs, outputs, frames)
  - Livebook-specific features like branching or smart cells
  - Code blocks marked with ` ```elixir#test:skip ` will be skipped

  For interactive livebooks, manual testing in Livebook is still required.
  """

  use Mix.Task

  @shortdoc "Test livebook files by executing Elixir code blocks"

  @impl true
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, strict: [verbose: :boolean, path: :string])

    path = Keyword.get(opts, :path, "guides/")
    verbose = Keyword.get(opts, :verbose, false)

    livebooks = find_livebooks(path)

    if livebooks == [] do
      Mix.shell().info("No livebooks found in #{path}")
      exit(0)
    end

    Mix.shell().info("Testing #{length(livebooks)} livebook(s)...\n")

    results =
      Enum.map(livebooks, fn livebook ->
        test_livebook(livebook, verbose)
      end)

    passed = Enum.count(results, & &1.passed)
    failed = length(results) - passed

    Mix.shell().info("\n#{String.duplicate("=", 50)}")
    Mix.shell().info("Results: #{passed} passed, #{failed} failed")

    if failed > 0 do
      Mix.shell().error("\nFailed livebooks:")

      Enum.filter(results, fn r -> not r.passed end)
      |> Enum.each(fn r ->
        Mix.shell().error("  - #{r.file}: #{r.error}")
      end)

      exit({:shutdown, 1})
    else
      Mix.shell().info("\nAll livebooks passed!")
      exit(0)
    end
  end

  defp find_livebooks(path) do
    Path.join([path, "**", "*.livemd"])
    |> Path.wildcard()
    |> Enum.sort()
  end

  defp test_livebook(file, verbose) do
    Mix.shell().info("Testing: #{file}")

    content = File.read!(file)
    code_blocks = extract_elixir_blocks(content)

    if verbose do
      Mix.shell().info("  Found #{length(code_blocks)} Elixir code block(s)")
    end

    if code_blocks == [] do
      Mix.shell().info("  ⚠️  No Elixir code blocks found")
      %{file: file, passed: true, error: nil}
    else
      execute_code_blocks(file, code_blocks, verbose)
    end
  end

  defp extract_elixir_blocks(content) do
    ~r/```elixir\n(.*?)```/s
    |> Regex.scan(content)
    |> Enum.map(fn [_, code] -> String.trim(code) end)
    |> Enum.reject(&skip_block?/1)
  end

  defp skip_block?(code) do
    String.starts_with?(code, "# test:skip") or
      String.starts_with?(code, "#test:skip")
  end

  defp execute_code_blocks(file, code_blocks, verbose) do
    # Create a temporary script that combines all code blocks
    combined_code = Enum.join(code_blocks, "\n\n")

    # Write to temp file
    temp_file =
      Path.join(System.tmp_dir!(), "livebook_test_#{:erlang.unique_integer([:positive])}.exs")

    File.write!(temp_file, combined_code)

    if verbose do
      Mix.shell().info("  Executing combined script...")
    end

    # Execute with mix run
    result =
      try do
        {output, exit_code} =
          System.cmd("elixir", [temp_file], stderr_to_stdout: true, timeout: 30_000)

        if exit_code == 0 do
          {:ok, output}
        else
          {:error, "Exit code #{exit_code}: #{String.slice(output, 0, 200)}"}
        end
      catch
        :exit, {:timeout, _} ->
          {:error, "Execution timed out (30s)"}
      after
        File.rm(temp_file)
      end

    case result do
      {:ok, _} ->
        Mix.shell().info("  ✓ Passed")
        %{file: file, passed: true, error: nil}

      {:error, reason} ->
        Mix.shell().error("  ✗ Failed: #{reason}")
        %{file: file, passed: false, error: reason}
    end
  end
end
