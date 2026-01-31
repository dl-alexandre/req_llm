defmodule ReqLLM.GenerationTest do
  use ExUnit.Case, async: true

  alias ReqLLM.{Context, Generation, Response, StreamResponse}

  setup do
    # Stub HTTP responses for testing
    Req.Test.stub(ReqLLM.GenerationTest, fn conn ->
      Req.Test.json(conn, %{
        "id" => "cmpl_test_123",
        "model" => "gpt-4o-mini-2024-07-18",
        "choices" => [
          %{
            "message" => %{"role" => "assistant", "content" => "Hello! How can I help you today?"}
          }
        ],
        "usage" => %{"prompt_tokens" => 10, "completion_tokens" => 9, "total_tokens" => 19}
      })
    end)

    :ok
  end

  describe "generate_text/3 core functionality" do
    test "accepts string input format" do
      {:ok, response} =
        Generation.generate_text(
          "openai:gpt-4o-mini",
          "Hello",
          req_http_options: [plug: {Req.Test, ReqLLM.GenerationTest}]
        )

      assert %Response{} = response
      # Model might have version suffix
      assert response.model =~ "gpt-4o-mini"
      assert is_binary(Response.text(response))
      assert String.length(Response.text(response)) > 0
    end

    test "accepts Context input format" do
      context = Context.new([Context.user("Hello world")])

      {:ok, response} =
        Generation.generate_text(
          "openai:gpt-4o-mini",
          context,
          req_http_options: [plug: {Req.Test, ReqLLM.GenerationTest}]
        )

      assert %Response{} = response
    end

    test "accepts message list input format" do
      messages = [
        %{role: "user", content: "Hello"},
        %{role: "assistant", content: "Hi there!"}
      ]

      {:ok, response} =
        Generation.generate_text(
          "openai:gpt-4o-mini",
          messages,
          req_http_options: [plug: {Req.Test, ReqLLM.GenerationTest}]
        )

      assert %Response{} = response
    end

    test "handles system prompt option" do
      {:ok, response} =
        Generation.generate_text(
          "openai:gpt-4o-mini",
          "Hello",
          system_prompt: "Be helpful",
          req_http_options: [plug: {Req.Test, ReqLLM.GenerationTest}]
        )

      assert %Response{} = response
      # System prompt gets added to context, which we can verify indirectly
      # system + user at minimum
      assert length(response.context.messages) >= 2
    end
  end

  describe "generate_text/3 error cases" do
    test "returns error for invalid model spec" do
      assert {:error, :unknown_provider} = Generation.generate_text("invalid:model", "Hello")
    end

    test "returns error for invalid role in message list" do
      messages = [
        %{role: "invalid_role", content: "Hello"}
      ]

      {:error, error} = Generation.generate_text("openai:gpt-4o-mini", messages)

      # Should get a Role error
      assert %ReqLLM.Error.Invalid.Role{} = error
      assert error.role == "invalid_role"
    end

    test "returns validation error for invalid options" do
      {:error, error} =
        Generation.generate_text(
          "openai:gpt-4o-mini",
          "Hello",
          temperature: "invalid"
        )

      # The error gets wrapped in Unknown, so we need to check the wrapped error
      assert %ReqLLM.Error.Unknown.Unknown{} = error
      assert %NimbleOptions.ValidationError{} = error.error
    end

    test "handles warnings correctly with on_unsupported: :error" do
      # Use OpenAI o1 model which doesn't support temperature
      {:error, error} =
        Generation.generate_text(
          "openai:o1-mini",
          "Hello",
          temperature: 0.7,
          on_unsupported: :error
        )

      # Should get error due to unsupported temperature parameter
      assert is_struct(error)
    end
  end

  describe "generate_text!/3" do
    test "returns text on success" do
      result =
        Generation.generate_text!(
          "openai:gpt-4o-mini",
          "Hello",
          req_http_options: [plug: {Req.Test, ReqLLM.GenerationTest}]
        )

      assert is_binary(result)
      assert String.length(result) > 0
    end

    test "raises on error" do
      assert_raise UndefinedFunctionError, fn ->
        Generation.generate_text!("invalid:model", "Hello")
      end
    end
  end

  describe "stream_text/3 core functionality" do
    setup do
      # Stub streaming response with SSE format
      Req.Test.stub(ReqLLM.GenerationStreamTest, fn conn ->
        sse_body =
          ~s(data: {"id":"chatcmpl-123","choices":[{"delta":{"content":"Hello"}}]}\n\n) <>
            ~s(data: {"id":"chatcmpl-123","choices":[{"delta":{"content":" world"}}]}\n\n) <>
            "data: [DONE]\n\n"

        conn
        |> Plug.Conn.put_resp_header("content-type", "text/event-stream")
        |> Plug.Conn.send_resp(200, sse_body)
      end)

      :ok
    end

    test "returns streaming response" do
      {:ok, response} =
        Generation.stream_text(
          "openai:gpt-4o-mini",
          "Tell me a story",
          req_http_options: [plug: {Req.Test, ReqLLM.GenerationStreamTest}]
        )

      assert %StreamResponse{} = response
      assert is_function(response.stream)
    end
  end

  describe "stream_text/3 error cases" do
    test "returns error for invalid model spec" do
      assert {:error, :unknown_provider} = Generation.stream_text("invalid:model", "Hello")
    end
  end

  describe "option validation and translation" do
    test "validates base schema options" do
      schema = Generation.schema()

      {:ok, validated} =
        NimbleOptions.validate([temperature: 0.7, max_tokens: 100], schema)

      assert validated[:temperature] == 0.7
      assert validated[:max_tokens] == 100
    end

    test "includes on_unsupported option in schema" do
      schema = Generation.schema()
      on_unsupported_spec = Keyword.get(schema.schema, :on_unsupported)

      assert on_unsupported_spec != nil
      assert on_unsupported_spec[:type] == {:in, [:warn, :error, :ignore]}
      assert on_unsupported_spec[:default] == :warn
    end

    test "provider schema composition works" do
      provider_schema =
        ReqLLM.Provider.Options.compose_schema(
          Generation.schema(),
          ReqLLM.Providers.OpenAI
        )

      # Should include both base and provider options
      assert provider_schema.schema[:temperature] != nil
      assert provider_schema.schema[:provider_options] != nil
    end
  end

  describe "options and generation parameters" do
    test "accepts generation options without errors" do
      {:ok, response} =
        Generation.generate_text(
          "openai:gpt-4o-mini",
          "Hello",
          temperature: 0.8,
          max_tokens: 50,
          top_p: 0.9,
          req_http_options: [plug: {Req.Test, ReqLLM.GenerationTest}]
        )

      assert %Response{} = response
    end

    test "handles provider-specific options" do
      {:ok, response} =
        Generation.generate_text(
          "openai:gpt-4o-mini",
          "Hello",
          frequency_penalty: 0.1,
          req_http_options: [plug: {Req.Test, ReqLLM.GenerationTest}]
        )

      assert %Response{} = response
    end
  end

  describe "generate_text/3 with req_http_options" do
    test "correctly passes http options to Req" do
      # We pass an intentionally invalid option to Req. If `req_http_options` are being passed correctly,
      # Req's internal validation will raise an ArgumentError. This confirms the options are being passed
      # all the way to `Req.new/1` without making a real network request.
      assert_raise ArgumentError, ~r/got unsupported atom method :invalid_method/, fn ->
        Generation.generate_text("openai:gpt-4o-mini", "Hello",
          req_http_options: [method: :invalid_method]
        )
      end
    end
  end

  describe "api_key option precedence" do
    test "api_key option takes precedence over other configuration methods" do
      custom_key = "test-api-key-#{System.unique_integer([:positive])}"

      Req.Test.stub(ReqLLM.GenerationTestAPIKey, fn conn ->
        auth_header = Plug.Conn.get_req_header(conn, "authorization")

        assert auth_header == ["Bearer #{custom_key}"],
               "Expected Authorization header to contain custom api_key"

        Req.Test.json(conn, %{
          "id" => "cmpl_test_123",
          "model" => "gpt-4o-mini-2024-07-18",
          "choices" => [
            %{
              "message" => %{"role" => "assistant", "content" => "Response"}
            }
          ],
          "usage" => %{"prompt_tokens" => 10, "completion_tokens" => 5, "total_tokens" => 15}
        })
      end)

      {:ok, response} =
        Generation.generate_text(
          "openai:gpt-4o-mini",
          "Hello",
          api_key: custom_key,
          req_http_options: [plug: {Req.Test, ReqLLM.GenerationTestAPIKey}]
        )

      assert %Response{} = response
    end
  end

  describe "stream_text/3 api_key option precedence" do
    test "api_key option takes precedence in streaming requests" do
      custom_key = "test-stream-key-#{System.unique_integer([:positive])}"

      Req.Test.stub(ReqLLM.GenerationStreamTestAPIKey, fn conn ->
        auth_header = Plug.Conn.get_req_header(conn, "authorization")

        assert auth_header == ["Bearer #{custom_key}"],
               "Expected Authorization header to contain custom api_key in streaming request"

        sse_body =
          ~s(data: {"id":"chatcmpl-123","choices":[{"delta":{"content":"Hello"}}]}\n\n) <>
            "data: [DONE]\n\n"

        conn
        |> Plug.Conn.put_resp_header("content-type", "text/event-stream")
        |> Plug.Conn.send_resp(200, sse_body)
      end)

      {:ok, response} =
        Generation.stream_text(
          "openai:gpt-4o-mini",
          "Hello",
          api_key: custom_key,
          req_http_options: [plug: {Req.Test, ReqLLM.GenerationStreamTestAPIKey}]
        )

      assert %StreamResponse{} = response
    end
  end

  describe "req_plugins option" do
    test "generate_text/3 applies plugins to the request" do
      test_pid = self()

      Req.Test.stub(ReqLLM.GenerationTestPlugins, fn conn ->
        custom_header = Plug.Conn.get_req_header(conn, "x-custom-header")
        send(test_pid, {:custom_header, custom_header})

        Req.Test.json(conn, %{
          "id" => "cmpl_test_123",
          "model" => "gpt-4o-mini-2024-07-18",
          "choices" => [
            %{
              "message" => %{"role" => "assistant", "content" => "Hello!"}
            }
          ],
          "usage" => %{"prompt_tokens" => 10, "completion_tokens" => 5, "total_tokens" => 15}
        })
      end)

      add_header_plugin = fn req ->
        Req.Request.put_header(req, "x-custom-header", "custom-value")
      end

      {:ok, response} =
        Generation.generate_text(
          "openai:gpt-4o-mini",
          "Hello",
          req_plugins: [add_header_plugin],
          req_http_options: [plug: {Req.Test, ReqLLM.GenerationTestPlugins}]
        )

      assert %Response{} = response
      assert_receive {:custom_header, ["custom-value"]}
    end

    test "generate_text/3 applies multiple plugins in order" do
      test_pid = self()

      Req.Test.stub(ReqLLM.GenerationTestPluginsOrder, fn conn ->
        header1 = Plug.Conn.get_req_header(conn, "x-first-header")
        header2 = Plug.Conn.get_req_header(conn, "x-second-header")
        send(test_pid, {:headers, header1, header2})

        Req.Test.json(conn, %{
          "id" => "cmpl_test_123",
          "model" => "gpt-4o-mini-2024-07-18",
          "choices" => [
            %{
              "message" => %{"role" => "assistant", "content" => "Hello!"}
            }
          ],
          "usage" => %{"prompt_tokens" => 10, "completion_tokens" => 5, "total_tokens" => 15}
        })
      end)

      first_plugin = fn req ->
        Req.Request.put_header(req, "x-first-header", "first-value")
      end

      second_plugin = fn req ->
        Req.Request.put_header(req, "x-second-header", "second-value")
      end

      {:ok, _response} =
        Generation.generate_text(
          "openai:gpt-4o-mini",
          "Hello",
          req_plugins: [first_plugin, second_plugin],
          req_http_options: [plug: {Req.Test, ReqLLM.GenerationTestPluginsOrder}]
        )

      assert_receive {:headers, ["first-value"], ["second-value"]}
    end

    test "generate_object/4 applies plugins to the request" do
      test_pid = self()

      Req.Test.stub(ReqLLM.GenerationTestObjectPlugins, fn conn ->
        custom_header = Plug.Conn.get_req_header(conn, "x-object-header")
        send(test_pid, {:object_header, custom_header})

        Req.Test.json(conn, %{
          "id" => "cmpl_test_123",
          "model" => "gpt-4o-mini-2024-07-18",
          "choices" => [
            %{
              "message" => %{
                "role" => "assistant",
                "content" => Jason.encode!(%{"name" => "Alice", "age" => 30})
              }
            }
          ],
          "usage" => %{"prompt_tokens" => 10, "completion_tokens" => 5, "total_tokens" => 15}
        })
      end)

      add_header_plugin = fn req ->
        Req.Request.put_header(req, "x-object-header", "object-value")
      end

      schema = [
        name: [type: :string, required: true],
        age: [type: :integer, required: true]
      ]

      {:ok, response} =
        Generation.generate_object(
          "openai:gpt-4o-mini",
          "Generate a person",
          schema,
          req_plugins: [add_header_plugin],
          req_http_options: [plug: {Req.Test, ReqLLM.GenerationTestObjectPlugins}]
        )

      assert %Response{} = response
      assert_receive {:object_header, ["object-value"]}
    end
  end
end
